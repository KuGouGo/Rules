#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

BASELINES="$ROOT/config/upstream-first-batch-baselines.json"
FIXTURE_ROOT="$ROOT/tests/fixtures/upstream"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_status() {
  local source="$1"
  local raw_file="$2"
  local expected_status="$3"
  local label="$4"
  local output actual_status

  output="$(python3 "$ROOT/scripts/tools/classify-upstream-health.py" classify "$source" "$raw_file" "$BASELINES")"
  actual_status="$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  if [ "$actual_status" != "$expected_status" ]; then
    echo "test failed: $label" >&2
    echo "expected status: $expected_status" >&2
    echo "actual output: $output" >&2
    exit 1
  fi
}

assert_status "google-json" "$FIXTURE_ROOT/google-json/pass.raw.json" "ok" "google-json pass fixture stays healthy in sync classification"
assert_status "github-json" "$FIXTURE_ROOT/github-json/fail.raw.json" "semantic_regression" "github-json semantic drift is classified correctly"
assert_status "telegram" "$TMP_DIR/missing.raw.txt" "transport_incident" "missing telegram payload is a transport incident"

echo "sync upstream classification tests passed"
