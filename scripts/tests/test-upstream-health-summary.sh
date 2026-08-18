#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

helper="$({
  awk '
    /^verify_and_record_upstream_health\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
  ' "$ROOT/scripts/commands/sync-upstream.sh"
})"
[ -n "$helper" ] || {
  echo "test failed: verify_and_record_upstream_health helper not found" >&2
  exit 1
}
eval "$helper"

record_upstream_summary() {
  printf '%s\n' "$3" > "$TMP_DIR/recorded-status"
}

write_config() {
  local requirement="$1"
  cat > "$TMP_DIR/upstreams.json" <<EOF
{"ip":{"fixture":{"health":{"requirement":"$requirement","min_raw_bytes":1,"min_entries":1,"family":"any","fallback_policy":"none"}}}}
EOF
}

export ROOT_DIR="$ROOT"
export UPSTREAMS_CONFIG_FILE="$TMP_DIR/upstreams.json"
: > "$TMP_DIR/raw"
: > "$TMP_DIR/normalized"

write_config optional
verify_and_record_upstream_health \
  ip fixture https://example.com "$TMP_DIR/raw" "$TMP_DIR/normalized" 0 >/dev/null
grep -Fx semantic_regression "$TMP_DIR/recorded-status" >/dev/null

write_config required
if verify_and_record_upstream_health \
  ip fixture https://example.com "$TMP_DIR/raw" "$TMP_DIR/normalized" 0 \
  >"$TMP_DIR/required.stdout" 2>"$TMP_DIR/required.stderr"; then
  echo "test failed: required semantic regression did not block" >&2
  exit 1
fi
grep -Fx semantic_regression "$TMP_DIR/recorded-status" >/dev/null
grep -F 'required upstream fixture failed configured health policy' "$TMP_DIR/required.stderr" >/dev/null

echo "upstream health summary tests passed"
