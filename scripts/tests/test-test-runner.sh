#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/scripts/tests/run.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FIXTURES="$TMP_DIR/tests"
mkdir -p "$FIXTURES"

cat > "$FIXTURES/test-01-pass.sh" <<'EOF'
#!/usr/bin/env bash
echo pass-ran
EOF
cat > "$FIXTURES/test-02-fail.sh" <<'EOF'
#!/usr/bin/env bash
echo fail-ran
exit 7
EOF
cat > "$FIXTURES/test-03-timeout.sh" <<'EOF'
#!/usr/bin/env bash
echo timeout-ran
sleep 5
EOF
cat > "$FIXTURES/test-04-after.sh" <<'EOF'
#!/usr/bin/env bash
echo after-ran
EOF
chmod +x "$FIXTURES"/*.sh

set +e
output="$(TEST_DIR="$FIXTURES" TEST_TIMEOUT_SECONDS=0.2 bash "$RUNNER" 2>&1)"
status=$?
set -e

[ "$status" -ne 0 ] || {
  echo "test failed: runner should fail when any test fails" >&2
  exit 1
}
for expected in \
  pass-ran fail-ran timeout-ran after-ran \
  "PASS  test-01-pass.sh" \
  "FAIL  test-02-fail.sh (exit 7)" \
  "TIMEOUT  test-03-timeout.sh (0.2s)" \
  "PASS  test-04-after.sh" \
  "total=4 passed=2 failed=2 timed_out=1"; do
  grep -F "$expected" <<< "$output" >/dev/null || {
    echo "test failed: missing runner output: $expected" >&2
    echo "$output" >&2
    exit 1
  }
done

filtered="$(TEST_DIR="$FIXTURES" TEST_FILTER=01-pass TEST_TIMEOUT_SECONDS=1 bash "$RUNNER")"
grep -F "total=1 passed=1 failed=0 timed_out=0" <<< "$filtered" >/dev/null

set +e
invalid="$(TEST_DIR="$FIXTURES" TEST_TIMEOUT_SECONDS=invalid bash "$RUNNER" 2>&1)"
invalid_status=$?
set -e
[ "$invalid_status" -eq 2 ]
grep -F "TEST_TIMEOUT_SECONDS must be a positive number" <<< "$invalid" >/dev/null

echo "test runner tests passed"
