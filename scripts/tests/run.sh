#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit

TEST_DIR="${TEST_DIR:-$ROOT/scripts/tests}"
TEST_FILTER="${TEST_FILTER:-}"
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-300}"
TIMEOUT_HELPER="$ROOT/scripts/tools/run-with-timeout.py"
ran=0
passed=0
failed=0
timed_out=0
test_scripts=()
results=()

if ! [[ "$TEST_TIMEOUT_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] || [ "$TEST_TIMEOUT_SECONDS" = "0" ] || [ "$TEST_TIMEOUT_SECONDS" = "0.0" ]; then
  echo "TEST_TIMEOUT_SECONDS must be a positive number" >&2
  exit 2
fi

for test_script in "$TEST_DIR"/test-*.sh; do
  [ -f "$test_script" ] || continue
  test_scripts+=("$test_script")
done

if [ "${#test_scripts[@]}" -eq 0 ]; then
  echo "no test scripts found in $TEST_DIR" >&2
  exit 1
fi

for test_script in "${test_scripts[@]}"; do
  test_name="$(basename "$test_script")"
  if [ -n "$TEST_FILTER" ] && [[ "$test_name" != *"$TEST_FILTER"* ]]; then
    continue
  fi

  ran=$((ran + 1))
  echo "==> $test_name (timeout: ${TEST_TIMEOUT_SECONDS}s)"
  python3 "$TIMEOUT_HELPER" --timeout "$TEST_TIMEOUT_SECONDS" bash "$test_script"
  status=$?
  case "$status" in
    0)
      passed=$((passed + 1))
      results+=("PASS  $test_name")
      ;;
    124)
      timed_out=$((timed_out + 1))
      failed=$((failed + 1))
      results+=("TIMEOUT  $test_name (${TEST_TIMEOUT_SECONDS}s)")
      ;;
    *)
      failed=$((failed + 1))
      results+=("FAIL  $test_name (exit $status)")
      ;;
  esac
done

if [ -d "$TEST_DIR/python" ] && { [ -z "$TEST_FILTER" ] || [[ "test-python-unittest" == *"$TEST_FILTER"* ]]; }; then
  ran=$((ran + 1))
  echo "==> test-python-unittest (timeout: ${TEST_TIMEOUT_SECONDS}s)"
  python3 "$TIMEOUT_HELPER" --timeout "$TEST_TIMEOUT_SECONDS" \
    python3 -m unittest discover -s "$TEST_DIR/python" -t "$TEST_DIR/python"
  status=$?
  case "$status" in
    0)
      passed=$((passed + 1))
      results+=("PASS  test-python-unittest")
      ;;
    124)
      timed_out=$((timed_out + 1))
      failed=$((failed + 1))
      results+=("TIMEOUT  test-python-unittest (${TEST_TIMEOUT_SECONDS}s)")
      ;;
    *)
      failed=$((failed + 1))
      results+=("FAIL  test-python-unittest (exit $status)")
      ;;
  esac
fi

if [ "$ran" -eq 0 ]; then
  echo "no test scripts matched TEST_FILTER=$TEST_FILTER" >&2
  exit 1
fi

printf '\nTest summary:\n'
printf '  %s\n' "${results[@]}"
printf 'total=%d passed=%d failed=%d timed_out=%d\n' "$ran" "$passed" "$failed" "$timed_out"

[ "$failed" -eq 0 ]
