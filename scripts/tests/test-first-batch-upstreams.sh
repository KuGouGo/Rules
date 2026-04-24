#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

BASELINES="$ROOT/config/upstream-first-batch-baselines.json"
FIXTURE_ROOT="$ROOT/tests/fixtures/upstream"

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

assert_status "google-json" "$FIXTURE_ROOT/google-json/pass.raw.json" "ok" "google-json pass fixture is healthy"
assert_status "google-json" "$FIXTURE_ROOT/google-json/fail.raw.json" "semantic_regression" "google-json fail fixture trips semantic regression"
assert_status "github-json" "$FIXTURE_ROOT/github-json/pass.raw.json" "ok" "github-json pass fixture is healthy"
assert_status "github-json" "$FIXTURE_ROOT/github-json/fail.raw.json" "semantic_regression" "github-json fail fixture trips semantic regression"
assert_status "telegram" "$FIXTURE_ROOT/telegram/pass.raw.txt" "ok" "telegram pass fixture is healthy"
assert_status "telegram" "$FIXTURE_ROOT/telegram/fail.raw.txt" "semantic_regression" "telegram fail fixture trips semantic regression"

echo "first-batch upstream invariant tests passed"
