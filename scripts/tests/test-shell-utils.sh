#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/common.sh
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

test_write_if_nonempty_or_remove_moves_nonempty_source() {
  printf 'old\n' > "$TMP_DIR/nonempty-dst"
  printf 'new\n' > "$TMP_DIR/nonempty-src"

  write_if_nonempty_or_remove "$TMP_DIR/nonempty-src" "$TMP_DIR/nonempty-dst"

  assert_file_content "$TMP_DIR/nonempty-dst" "new"
  if [ -e "$TMP_DIR/nonempty-src" ]; then
    echo "test failed: nonempty source should be moved" >&2
    exit 1
  fi
}

test_write_if_nonempty_or_remove_deletes_empty_output_and_stale_target() {
  printf 'stale\n' > "$TMP_DIR/empty-dst"
  : > "$TMP_DIR/empty-src"

  write_if_nonempty_or_remove "$TMP_DIR/empty-src" "$TMP_DIR/empty-dst"

  if [ -e "$TMP_DIR/empty-src" ] || [ -e "$TMP_DIR/empty-dst" ]; then
    echo "test failed: empty source and stale target should be removed" >&2
    exit 1
  fi
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

test_sha256_file_uses_python_fallback_without_sha256sum() {
  local fallback_path="$TMP_DIR/no-sha256sum"
  local input_file="$TMP_DIR/empty"
  local actual

  mkdir -p "$fallback_path"
  ln -s "$(command -v python3)" "$fallback_path/python3"
  : > "$input_file"

  actual="$(PATH="$fallback_path" sha256_file "$input_file")"
  assert_equals \
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" \
    "$actual" \
    "sha256_file Python fallback"
}

test_parallel_downloads_preserve_failure_semantics() {
  local download_root="$TMP_DIR/parallel-downloads"
  local ready_dir="$download_root/ready"
  mkdir -p "$ready_dir"

  download_file() {
    local url="$1"
    local output="$2"
    local name="${url##*/}"
    touch "$ready_dir/$name"
    local attempts=0
    while [ "$(find "$ready_dir" -type f | wc -l | tr -d ' ')" -lt 3 ]; do
      attempts=$((attempts + 1))
      if [ "$attempts" -gt 100 ]; then
        echo "downloads did not start concurrently" >&2
        return 1
      fi
      sleep 0.01
    done
    if [ "$name" = "classified-fail" ] || [ "$name" = "required-fail" ]; then
      return 1
    fi
    printf '%s\n' "$name" > "$output"
  }

  RULES_DOWNLOAD_LOG_DIR="$download_root/logs" download_files_parallel \
    one required mock://one "$download_root/one.out" \
    two required mock://two "$download_root/two.out" \
    classified-fail classified mock://classified-fail "$download_root/classified.out"
  assert_file_content "$download_root/one.out" "one"
  assert_file_content "$download_root/two.out" "two"
  if [ -e "$download_root/classified.out" ]; then
    echo "test failed: failed classified download output should be removed" >&2
    exit 1
  fi

  find "$ready_dir" -type f -delete
  if RULES_DOWNLOAD_LOG_DIR="$download_root/logs" download_files_parallel \
    one required mock://one "$download_root/one.out" \
    two required mock://two "$download_root/two.out" \
    required-fail required mock://required-fail "$download_root/required.out"; then
    echo "test failed: required parallel download failure should fail the batch" >&2
    exit 1
  fi
  if [ -e "$download_root/required.out" ]; then
    echo "test failed: failed required download output should be removed" >&2
    exit 1
  fi
}

test_list_rule_files_sorts_lists_only
test_list_rule_files_missing_dir_is_empty
test_write_if_changed_replaces_different_file
test_write_if_changed_removes_identical_source
test_write_if_nonempty_or_remove_moves_nonempty_source
test_write_if_nonempty_or_remove_deletes_empty_output_and_stale_target
test_common_source_has_no_tool_cache_side_effects
test_setup_tool_cache_creates_bin_and_updates_path_once
test_sha256_file_uses_python_fallback_without_sha256sum
test_parallel_downloads_preserve_failure_semantics

echo "shell utility tests passed"
