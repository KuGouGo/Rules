#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARTIFACT_ROOT="$TMP_DIR/output"
DOMAIN_SOURCES="$TMP_DIR/sources/domain"
IP_SOURCES="$TMP_DIR/sources/ip"
TOOL="$ROOT/scripts/tools/artifact_origins.py"

mkdir -p "$DOMAIN_SOURCES" "$IP_SOURCES"
printf 'DOMAIN-REGEX,^example$\n' > "$DOMAIN_SOURCES/sample.list"

create_domain_artifacts() {
  local platform extension
  while read -r platform extension; do
    mkdir -p "$ARTIFACT_ROOT/domain/$platform"
    printf 'fixture\n' > "$ARTIFACT_ROOT/domain/$platform/sample.$extension"
    printf 'upstream\n' > "$ARTIFACT_ROOT/domain/$platform/upstream.$extension"
  done <<'EOF'
surge list
quanx list
egern yaml
sing-box srs
mihomo mrs
EOF
}

assert_origin_state() {
  local expression="$1"
  python3 - "$ARTIFACT_ROOT/artifact-origins.json" "$expression" <<'PY'
import json
import sys

origins = json.load(open(sys.argv[1], encoding="utf-8"))
if not eval(sys.argv[2], {"origins": origins}):
    raise SystemExit(f"origin assertion failed: {sys.argv[2]}\n{origins}")
PY
}

create_domain_artifacts
python3 "$TOOL" reset "$ARTIFACT_ROOT" restored-published-branch
rm \
  "$ARTIFACT_ROOT/domain/surge/sample.list" \
  "$ARTIFACT_ROOT/domain/quanx/sample.list" \
  "$ARTIFACT_ROOT/domain/mihomo/sample.mrs"
python3 "$TOOL" mark-custom "$ARTIFACT_ROOT" "$DOMAIN_SOURCES" "$IP_SOURCES"

assert_origin_state \
  'origins["domain/egern/sample.yaml"] == "generated-custom" and origins["domain/sing-box/sample.srs"] == "generated-custom"'
assert_origin_state \
  'all(f"domain/{platform}/sample.{extension}" not in origins for platform, extension in (("surge", "list"), ("quanx", "list"), ("mihomo", "mrs")))'
assert_origin_state \
  'all(value == "restored-published-branch" for key, value in origins.items() if "/upstream." in key)'

actual_custom="$(python3 "$TOOL" list "$ARTIFACT_ROOT" --origin generated-custom)"
expected_custom="domain/egern/sample.yaml
domain/sing-box/sample.srs"
[ "$actual_custom" = "$expected_custom" ] || {
  echo "test failed: custom origin listing mismatch" >&2
  printf 'expected:\n%s\nactual:\n%s\n' "$expected_custom" "$actual_custom" >&2
  exit 1
}

create_domain_artifacts
python3 "$TOOL" reset "$ARTIFACT_ROOT" restored-published-branch
rm "$ARTIFACT_ROOT/domain/surge/sample.list"
python3 "$TOOL" mark-custom \
  "$ARTIFACT_ROOT" "$DOMAIN_SOURCES" "$IP_SOURCES" --text-only

assert_origin_state \
  '"domain/surge/sample.list" not in origins and origins["domain/quanx/sample.list"] == "generated-custom" and origins["domain/egern/sample.yaml"] == "generated-custom"'
assert_origin_state \
  'origins["domain/sing-box/sample.srs"] == "restored-published-branch" and origins["domain/mihomo/sample.mrs"] == "restored-published-branch"'

printf '[]\n' > "$ARTIFACT_ROOT/artifact-origins.json"
if python3 "$TOOL" list "$ARTIFACT_ROOT" >"$TMP_DIR/invalid.stdout" 2>"$TMP_DIR/invalid.stderr"; then
  echo "test failed: invalid origin map was accepted" >&2
  exit 1
fi
grep -F 'invalid artifact origin map' "$TMP_DIR/invalid.stderr" >/dev/null

echo "artifact origin lifecycle tests passed"
