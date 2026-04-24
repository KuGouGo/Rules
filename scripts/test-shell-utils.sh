#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/lib/common.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$expected" != "$actual" ]; then
    echo "test failed: $label" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

assert_file_content() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(cat "$file")"
  assert_equals "$expected" "$actual" "$file content"
}

test_list_rule_files_sorts_lists_only() {
  mkdir -p "$TMP_DIR/rules"
  touch "$TMP_DIR/rules/z.list" "$TMP_DIR/rules/a.list" "$TMP_DIR/rules/ignore.txt"
  mkdir -p "$TMP_DIR/rules/nested.list"

  local actual expected
  actual="$(list_rule_files "$TMP_DIR/rules")"
  expected="$TMP_DIR/rules/a.list
$TMP_DIR/rules/z.list"

  assert_equals "$expected" "$actual" "list_rule_files returns sorted .list files only"
}

test_list_rule_files_missing_dir_is_empty() {
  local actual
  actual="$(list_rule_files "$TMP_DIR/missing")"
  assert_equals "" "$actual" "list_rule_files missing directory is empty"
}

test_write_if_changed_replaces_different_file() {
  printf 'old\n' > "$TMP_DIR/dst"
  printf 'new\n' > "$TMP_DIR/src"

  write_if_changed "$TMP_DIR/src" "$TMP_DIR/dst"

  assert_file_content "$TMP_DIR/dst" "new"
  if [ -e "$TMP_DIR/src" ]; then
    echo "test failed: write_if_changed should move changed source" >&2
    exit 1
  fi
}

test_write_if_changed_removes_identical_source() {
  printf 'same\n' > "$TMP_DIR/dst"
  printf 'same\n' > "$TMP_DIR/src"

  write_if_changed "$TMP_DIR/src" "$TMP_DIR/dst"

  assert_file_content "$TMP_DIR/dst" "same"
  if [ -e "$TMP_DIR/src" ]; then
    echo "test failed: write_if_changed should remove identical source" >&2
    exit 1
  fi
}

test_normalize_version_strips_leading_v() {
  assert_equals "1.2.3" "$(normalize_version v1.2.3)" "normalize_version strips v"
  assert_equals "1.2.3" "$(normalize_version 1.2.3)" "normalize_version keeps bare version"
}

test_common_source_has_no_tool_cache_side_effects() {
  local probe_root="$TMP_DIR/source_probe"
  local probe_output
  mkdir -p "$probe_root"

  probe_output="$(
    ROOT="$probe_root" \
    BIN_DIR="$probe_root/.bin" \
    ORIGINAL_PATH="$PATH" \
    bash -c 'set -euo pipefail; source scripts/lib/common.sh; [ ! -e "$BIN_DIR" ]; printf "bin=%s\npath=%s\n" "$([ -e "$BIN_DIR" ] && printf exists || printf missing)" "$([ "$PATH" = "$ORIGINAL_PATH" ] && printf unchanged || printf changed)"'
  )"

  assert_equals "bin=missing
path=unchanged" "$probe_output" "sourcing common.sh has no tool-cache side effects"
}

test_setup_tool_cache_creates_bin_and_updates_path_once() {
  local probe_root="$TMP_DIR/setup_probe"
  local probe_output
  mkdir -p "$probe_root"

  probe_output="$(
    ROOT="$probe_root" \
    BIN_DIR="$probe_root/.bin" \
    bash -c 'set -euo pipefail; source scripts/lib/common.sh; setup_tool_cache; setup_tool_cache; case ":$PATH:" in *":$BIN_DIR:$BIN_DIR:"*) path=duplicated ;; *":$BIN_DIR:"*) path=present ;; *) path=missing ;; esac; printf "bin=%s\npath=%s\n" "$([ -d "$BIN_DIR" ] && printf exists || printf missing)" "$path"'
  )"

  assert_equals "bin=exists
path=present" "$probe_output" "setup_tool_cache is explicit and idempotent"
}

test_list_rule_files_sorts_lists_only
test_list_rule_files_missing_dir_is_empty
test_write_if_changed_replaces_different_file
test_write_if_changed_removes_identical_source
test_normalize_version_strips_leading_v
test_common_source_has_no_tool_cache_side_effects
test_setup_tool_cache_creates_bin_and_updates_path_once

echo "shell utility tests passed"
