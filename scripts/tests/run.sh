#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TEST_DIR="$ROOT/scripts/tests"
TEST_FILTER="${TEST_FILTER:-}"
ran=0
test_scripts=()

while IFS= read -r test_script; do
  test_scripts+=("$test_script")
done < <(find "$TEST_DIR" -maxdepth 1 -type f -name 'test-*.sh' | sort)

if [ "${#test_scripts[@]}" -eq 0 ]; then
  echo "no test scripts found in $TEST_DIR" >&2
  exit 1
fi

for test_script in "${test_scripts[@]}"; do
  test_name="$(basename "$test_script")"
  if [ -n "$TEST_FILTER" ] && [[ "$test_name" != *"$TEST_FILTER"* ]]; then
    continue
  fi

  echo "==> $test_name"
  "$test_script"
  ran=$((ran + 1))
done

if [ "$ran" -eq 0 ]; then
  echo "no test scripts matched TEST_FILTER=$TEST_FILTER" >&2
  exit 1
fi

echo "test runner completed: $ran script(s)"
