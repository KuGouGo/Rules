#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/.github/workflows" "$TMP_DIR/.github/actions/setup"
cat > "$TMP_DIR/.github/workflows/test.yml" <<'YAML'
steps:
  - uses: actions/checkout@0000000000000000000000000000000000000000 # v1.0.0
  - uses: actions/upload-artifact@0000000000000000000000000000000000000000 # v1.0.0
YAML
cat > "$TMP_DIR/.github/actions/setup/action.yml" <<'YAML'
runs:
  using: composite
  steps:
    - uses: actions/cache@0000000000000000000000000000000000000000 # v1.0.0
    - uses: actions/setup-python@0000000000000000000000000000000000000000 # v1.0.0
YAML
cat > "$TMP_DIR/releases.json" <<'JSON'
{
  "actions/cache": {"version": "v6.1.0", "sha": "1111111111111111111111111111111111111111"},
  "actions/checkout": {"version": "v7.0.1", "sha": "2222222222222222222222222222222222222222"},
  "actions/download-artifact": {"version": "v8.0.1", "sha": "3333333333333333333333333333333333333333"},
  "actions/setup-python": {"version": "v7.0.0", "sha": "4444444444444444444444444444444444444444"},
  "actions/upload-artifact": {"version": "v7.0.1", "sha": "5555555555555555555555555555555555555555"}
}
JSON

output="$(python3 "$ROOT/scripts/tools/update-action-pins.py" \
  --root "$TMP_DIR" --metadata "$TMP_DIR/releases.json")"
grep -Fxq "changed=true" <<< "$output"
grep -Fq "actions/checkout@2222222222222222222222222222222222222222 # v7.0.1" \
  "$TMP_DIR/.github/workflows/test.yml"
grep -Fq "actions/cache@1111111111111111111111111111111111111111 # v6.1.0" \
  "$TMP_DIR/.github/actions/setup/action.yml"

output="$(python3 "$ROOT/scripts/tools/update-action-pins.py" \
  --root "$TMP_DIR" --metadata "$TMP_DIR/releases.json")"
grep -Fxq "changed=false" <<< "$output"

echo "action pin update tests passed"
