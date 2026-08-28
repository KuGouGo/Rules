#!/usr/bin/env bash
# Regenerate or verify the binary golden fixtures.
#
# The .srs/.mrs goldens pin the exact bytes produced by the locked compiler
# versions for the fixture inputs, giving the binary artifact pipeline a
# regression tripwire that the decompile round-trip verifier cannot provide.
#
# Usage:
#   update-binary-goldens.sh            regenerate fixtures/expected/ in place
#   update-binary-goldens.sh --check    compile into a temp dir and compare
#
# Requires the locked sing-box/mihomo binaries (ensure_sing_box/ensure_mihomo).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=scripts/lib/rules.sh
source "$ROOT/scripts/lib/rules.sh"

FIXTURE_DIR="$ROOT/scripts/tests/fixtures/binary"
INPUT_DIR="$FIXTURE_DIR/input"
EXPECTED_DIR="$FIXTURE_DIR/expected"

mode="regenerate"
if [ "${1:-}" = "--check" ]; then
  mode="check"
elif [ -n "${1:-}" ]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

compile_fixtures() {
  local dest_dir="$1"
  local work_dir source_version
  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' RETURN
  source_version="$(detect_singbox_rule_set_source_version)"

  mkdir -p "$dest_dir"
  rm -f "$dest_dir"/*.srs "$dest_dir"/*.mrs
  SINGBOX_RULE_SET_VERSION="$source_version" \
    python3 "$ROOT/scripts/tools/export-domain-rules.py" binary-input-dir \
    "$INPUT_DIR" "$work_dir"

  local json_file plain_file base
  for json_file in "$work_dir"/*.json; do
    [ -f "$json_file" ] || continue
    base="$(basename "$json_file" .json)"
    sing-box rule-set compile "$json_file" --output "$dest_dir/$base.srs"
  done
  for plain_file in "$work_dir"/*.mihomo.txt; do
    [ -f "$plain_file" ] || continue
    [ -s "$plain_file" ] || continue
    base="$(basename "$plain_file" .mihomo.txt)"
    mihomo convert-ruleset domain text "$plain_file" "$dest_dir/$base.mrs" >/dev/null
  done
}

record_tool_versions() {
  {
    printf 'sing-box=%s\n' "$(tool_lock_value sing-box version)"
    printf 'mihomo=%s\n' "$(tool_lock_value mihomo version)"
  } > "$FIXTURE_DIR/tool-versions"
}

if [ "$mode" = "check" ]; then
  if [ ! -f "$FIXTURE_DIR/tool-versions" ]; then
    echo "binary golden tool-versions file is missing; regenerate with $0" >&2
    exit 1
  fi
  current_versions="$(printf 'sing-box=%s\nmihomo=%s\n' "$(tool_lock_value sing-box version)" "$(tool_lock_value mihomo version)")"
  pinned_versions="$(cat "$FIXTURE_DIR/tool-versions")"
  if [ "$current_versions" != "$pinned_versions" ]; then
    echo "binary golden fixtures were generated with different tool versions:" >&2
    echo "  fixtures: $(printf '%s' "$pinned_versions" | tr '\n' ' ')" >&2
    echo "  lock:     $(printf '%s' "$current_versions" | tr '\n' ' ')" >&2
    echo "regenerate with scripts/commands/update-binary-goldens.sh" >&2
    exit 1
  fi
  check_dir="$(mktemp -d)"
  diff_file="$(mktemp)"
  trap 'rm -rf "$check_dir" "$diff_file"' RETURN
  compile_fixtures "$check_dir"
  if ! diff -r "$EXPECTED_DIR" "$check_dir" >"$diff_file" 2>&1; then
    echo "binary golden mismatch; compiled bytes differ from fixtures:" >&2
    cat "$diff_file" >&2
    echo "regenerate with scripts/commands/update-binary-goldens.sh" >&2
    exit 1
  fi
  echo "binary golden fixtures verified"
  exit 0
fi

ensure_sing_box
ensure_mihomo
compile_fixtures "$EXPECTED_DIR"
record_tool_versions
echo "binary golden fixtures regenerated:"
for artifact in "$EXPECTED_DIR"/*.srs "$EXPECTED_DIR"/*.mrs; do
  [ -f "$artifact" ] || continue
  printf '%s  %s\n' "$(sha256_file "$artifact")" "$(basename "$artifact")"
done
