#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "test failed: $*" >&2
  exit 1
}

# assert_lint_fails_with <label> <expected-message> [lint args...]
assert_lint_fails_with() {
  local label="$1" expected="$2"
  shift 2
  local stderr
  if stderr="$(python3 scripts/tools/lint-config.py "$@" 2>&1)"; then
    fail "$label: lint should reject the config"
  fi
  if ! grep -Fq "$expected" <<< "$stderr"; then
    fail "$label: lint message missing: expected '$expected' in: $stderr"
  fi
}

COMMIT_A="1111111111111111111111111111111111111111"
COMMIT_B="2222222222222222222222222222222222222222"

# --- pins config lint ---
assert_lint_fails_with \
  "pins-schema" \
  "upstream_pins.schema_version: must equal 1" \
  --upstream-pins /dev/null

cat > "$TMP_DIR/bad-commit.json" <<EOF
{"schema_version": 1, "pins": {"domain.dlc": {"commit": "xyz", "note": "n"}}}
EOF
assert_lint_fails_with \
  "pins-commit" \
  "upstream_pins.pins.domain.dlc.commit: must be a lowercase 40-character Git commit" \
  --upstream-pins "$TMP_DIR/bad-commit.json"

cat > "$TMP_DIR/good.json" <<EOF
{"schema_version": 1, "pins": {"domain.dlc": {"commit": "$COMMIT_A", "note": "audited"}}}
EOF
if ! python3 scripts/tools/lint-config.py --upstream-pins "$TMP_DIR/good.json" >/dev/null; then
  fail "valid pins config should pass lint"
fi

# --- apply-upstream-pins.sh behavior against a local git fixture ---
ORIGIN="$TMP_DIR/origin.git"
CLONE="$TMP_DIR/clone"
git init -q --bare "$ORIGIN"
# Serve fetch-by-SHA for the pinned-commit checkout path, and pin the bare
# repo's HEAD to the pushed branch: git's default branch name differs across
# platforms, and a HEAD pointing at a branch that was never pushed makes the
# clone see an empty repository.
git -C "$ORIGIN" config uploadpack.allowAnySHA1InWant true
git init -q "$CLONE"
git -C "$CLONE" config user.email t@t
git -C "$CLONE" config user.name t
echo one > "$CLONE/data.txt"
git -C "$CLONE" add data.txt
git -C "$CLONE" commit -qm one
COMMIT_A="$(git -C "$CLONE" rev-parse HEAD)"
echo two >> "$CLONE/data.txt"
git -C "$CLONE" commit -qam two
COMMIT_B="$(git -C "$CLONE" rev-parse HEAD)"
git -C "$CLONE" push -q "$ORIGIN" HEAD:refs/heads/main
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

# A fresh shallow clone sits on the remote default branch (COMMIT_B).
git clone -q --depth=1 --single-branch "$ORIGIN" "$TMP_DIR/shallow"
test "$(git -C "$TMP_DIR/shallow" rev-parse HEAD)" = "$COMMIT_B" || fail "fixture setup: clone should be at COMMIT_B"

# No pin entry -> no-op.
cat > "$TMP_DIR/empty.json" <<EOF
{"schema_version": 1, "pins": {}}
EOF
bash "$ROOT/scripts/commands/apply-upstream-pins.sh" "$TMP_DIR/empty.json" "$TMP_DIR/shallow" domain.dlc \
  | grep -q "no upstream pin" || fail "missing pin entry should be reported as a no-op"
test "$(git -C "$TMP_DIR/shallow" rev-parse HEAD)" = "$COMMIT_B" || fail "no-pin run must not move HEAD"

# Pin to the older audited commit -> HEAD moves to it.
cat > "$TMP_DIR/pinned.json" <<EOF
{"schema_version": 1, "pins": {"domain.dlc": {"commit": "$COMMIT_A", "note": "audited"}}}
EOF
bash "$ROOT/scripts/commands/apply-upstream-pins.sh" "$TMP_DIR/pinned.json" "$TMP_DIR/shallow" domain.dlc >/dev/null \
  || fail "pin application should succeed"
test "$(git -C "$TMP_DIR/shallow" rev-parse HEAD)" = "$COMMIT_A" || fail "pin application must check out the pinned commit"

# Already pinned -> idempotent success.
bash "$ROOT/scripts/commands/apply-upstream-pins.sh" "$TMP_DIR/pinned.json" "$TMP_DIR/shallow" domain.dlc >/dev/null \
  || fail "re-running a satisfied pin should succeed"
test "$(git -C "$TMP_DIR/shallow" rev-parse HEAD)" = "$COMMIT_A" || fail "idempotent run must not move HEAD"

# Float override leaves the tree on remote HEAD.
git -C "$TMP_DIR/shallow" checkout -q FETCH_HEAD 2>/dev/null || true
git -C "$TMP_DIR/shallow" checkout -q -B main origin/main 2>/dev/null || git -C "$TMP_DIR/shallow" checkout -q main
RULES_UPSTREAM_FLOAT=1 bash "$ROOT/scripts/commands/apply-upstream-pins.sh" "$TMP_DIR/pinned.json" "$TMP_DIR/shallow" domain.dlc \
  | grep -q "RULES_UPSTREAM_FLOAT=1" || fail "float override should be reported"
test "$(git -C "$TMP_DIR/shallow" rev-parse HEAD)" = "$COMMIT_B" || fail "float override must not move HEAD"

# Unfetchable pin commit -> loud failure.
cat > "$TMP_DIR/bogus.json" <<EOF
{"schema_version": 1, "pins": {"domain.dlc": {"commit": "3333333333333333333333333333333333333333", "note": "bogus"}}}
EOF
if bash "$ROOT/scripts/commands/apply-upstream-pins.sh" "$TMP_DIR/bogus.json" "$TMP_DIR/shallow" domain.dlc >/dev/null 2>&1; then
  fail "unfetchable pin commit must fail"
fi

# The sync pipeline must invoke the pin applier before the DLC audit.
if ! grep -q "apply-upstream-pins.sh" "$ROOT/scripts/commands/sync-upstream.sh"; then
  fail "sync-upstream.sh must apply upstream pins before auditing DLC data"
fi

echo "upstream pin tests passed"
