#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/scripts/commands" "$REPO/scripts/tools" "$REPO/.output"
cp \
  "$ROOT/scripts/commands/build-artifacts-transaction.sh" \
  "$ROOT/scripts/commands/check-runtime.sh" \
  "$REPO/scripts/commands/"
printf 'old live tree\n' > "$REPO/.output/sentinel"

cat > "$REPO/scripts/commands/sync-upstream.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$RULES_ARTIFACT_ROOT"
printf 'partial staged tree\n' > "$RULES_ARTIFACT_ROOT/new"
printf '[{"status":"ok"}]\n' > "$RULES_ARTIFACT_ROOT/upstream-summary.json"
case "${RULES_SYNC_FAIL_AT:-}" in
  late-domain|late-ip|late-compiler) exit 1 ;;
esac
EOF
cat > "$REPO/scripts/commands/restore-artifacts.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$RULES_ARTIFACT_ROOT"
printf 'partial restore\n' > "$RULES_ARTIFACT_ROOT/new"
case "${RULES_RESTORE_FAIL_AT:-}" in late-text|late-binary) exit 1 ;; esac
EOF
for command in build-custom.sh guard-artifacts.sh generate-artifact-manifest.sh verify-artifact-manifest.sh; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/scripts/commands/$command"
done
cat > "$REPO/scripts/tools/summarize-artifacts.py" <<'EOF'
import argparse
p=argparse.ArgumentParser(); p.add_argument('root'); p.add_argument('--output'); a=p.parse_args()
open(a.output, 'w').write('{}\n')
EOF
chmod +x "$REPO/scripts/commands/"*.sh

snapshot() {
  python3 - "$REPO/.output" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
for path in sorted(item for item in root.rglob("*") if item.is_file()):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"{path.relative_to(root).as_posix()}\t{digest}")
PY
}
assert_preserved() {
  local label="$1"; shift
  local health_file
  snapshot > "$TMP/before"
  if env ARTIFACT_GENERATION_ID="$label" "$@" \
    "$REPO/scripts/commands/build-artifacts-transaction.sh" \
    >/dev/null 2>"$TMP/$label.err"; then
    echo "expected transaction failure: $label" >&2; exit 1
  fi
  snapshot > "$TMP/after"
  cmp -s "$TMP/before" "$TMP/after" || { echo "$label changed live output" >&2; exit 1; }
  health_file="$(find "$REPO/.artifacts/diagnostics" -type f -path "*/${label}-*/transaction-health.json" | sort | tail -n 1)"
  [ -n "$health_file" ]
  python3 - "$health_file" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["status"] == "failed"
PY
}

health_file_for() {
  local generation="$1"
  find "$REPO/.artifacts/diagnostics" -type f \
    -path "*/${generation}-*/transaction-health.json" | sort | tail -n 1
}

assert_health() {
  local generation="$1"
  local reason="$2"
  local promotion_state="$3"
  local rollback_status="$4"
  local signal="${5:-}"
  local health_file
  health_file="$(health_file_for "$generation")"
  [ -n "$health_file" ]
  python3 - "$health_file" "$reason" "$promotion_state" "$rollback_status" "$signal" <<'PY'
import json, sys
path, reason, promotion_state, rollback_status, signal = sys.argv[1:]
payload = json.load(open(path, encoding="utf-8"))
assert payload["status"] == "failed"
assert payload["failure_reason"] == reason
assert payload["promotion_state"] == promotion_state
assert payload["rollback_status"] == rollback_status
if signal:
    assert payload["signal"] == signal
else:
    assert "signal" not in payload
PY
}

for point in late-domain late-ip late-compiler; do
  assert_preserved "sync-$point" RULES_BUILD_SCOPE=full RULES_SYNC_FAIL_AT="$point"
done
for point in late-text late-binary; do
  assert_preserved "restore-$point" RULES_BUILD_SCOPE=custom RULES_RESTORE_FAIL_AT="$point"
done

if RULES_ARTIFACT_ROOT="$TMP/caller-stage" "$REPO/scripts/commands/build-artifacts-transaction.sh" >"$TMP/root.out" 2>"$TMP/root.err"; then
  echo "transaction accepted caller-supplied RULES_ARTIFACT_ROOT" >&2; exit 1
fi
grep -F 'RULES_ARTIFACT_ROOT is transaction-owned' "$TMP/root.err" >/dev/null
[ ! -e "$TMP/caller-stage" ]

NO_PYTHON_BIN="$TMP/no-python-bin"
mkdir -p "$NO_PYTHON_BIN"
ln -s "$(command -v bash)" "$NO_PYTHON_BIN/bash"
ln -s "$(command -v dirname)" "$NO_PYTHON_BIN/dirname"
if PATH="$NO_PYTHON_BIN" \
  "$REPO/scripts/commands/build-artifacts-transaction.sh" \
  >"$TMP/missing-python.out" 2>"$TMP/missing-python.err"; then
  echo "transaction accepted a missing Python runtime" >&2
  exit 1
fi
grep -F 'Python 3.11+ is required (python3 not found in PATH)' "$TMP/missing-python.err" >/dev/null
if grep -F 'cross-device' "$TMP/missing-python.err" >/dev/null; then
  echo "missing Python runtime was misreported as a filesystem error" >&2
  exit 1
fi

assert_preserved \
  filesystem-preflight \
  RULES_TRANSACTION_TEST_DEVICE_MISMATCH=1
assert_health filesystem-preflight filesystem-preflight-failed building not-required
grep -F 'cross-device artifact promotion refused before build' \
  "$TMP/filesystem-preflight.err" >/dev/null

assert_preserved \
  backup-rename-failure \
  RULES_TRANSACTION_TEST_RENAME_FAILURES=backup:EIO
assert_health backup-rename-failure backup-rename-failed rolled-back succeeded
grep -F 'artifact transaction backup rename failed (strict rename refused)' \
  "$TMP/backup-rename-failure.err" >/dev/null

assert_preserved \
  promotion-exdev \
  RULES_TRANSACTION_TEST_RENAME_FAILURES=promote:EXDEV
assert_health promotion-exdev promotion-rename-failed rolled-back succeeded
grep -F 'artifact transaction promote rename failed (cross-device rename refused)' \
  "$TMP/promotion-exdev.err" >/dev/null

for signal in HUP INT TERM; do
  label="signal-${signal,,}"
  case "$signal" in
    HUP) expected_status=129 ;;
    INT) expected_status=130 ;;
    TERM) expected_status=143 ;;
  esac
  snapshot > "$TMP/$label.before"
  if env \
    ARTIFACT_GENERATION_ID="$label" \
    RULES_TRANSACTION_TEST_SIGNAL_AFTER_BACKUP="$signal" \
    "$REPO/scripts/commands/build-artifacts-transaction.sh" \
    >"$TMP/$label.out" 2>"$TMP/$label.err"; then
    echo "expected transaction signal failure: $signal" >&2
    exit 1
  else
    actual_status=$?
  fi
  [ "$actual_status" -eq "$expected_status" ]
  snapshot > "$TMP/$label.after"
  cmp -s "$TMP/$label.before" "$TMP/$label.after"
  assert_health "$label" signal rolled-back succeeded "$signal"
  grep -F "artifact transaction received $signal signal" "$TMP/$label.err" >/dev/null
done

snapshot > "$TMP/rollback-restore.before"
if env \
  ARTIFACT_GENERATION_ID=rollback-restore-failure \
  RULES_TRANSACTION_TEST_RENAME_FAILURES=promote:EIO,rollback-restore:EIO \
  "$REPO/scripts/commands/build-artifacts-transaction.sh" \
  >"$TMP/rollback-restore.out" 2>"$TMP/rollback-restore.err"; then
  echo "expected rollback restore failure" >&2
  exit 1
fi
[ ! -e "$REPO/.output" ]
assert_health rollback-restore-failure promotion-rename-failed promotion-pending failed
recovery_root="$(sed -n 's/^transaction recovery data preserved in //p' "$TMP/rollback-restore.err" | tail -n 1)"
[ -n "$recovery_root" ]
grep -Fx 'old live tree' "$recovery_root/previous-output/sentinel" >/dev/null
python3 - "$recovery_root/previous-output" "$REPO/.output" <<'PY'
import os, sys
os.replace(sys.argv[1], sys.argv[2])
PY
rm -rf "$recovery_root"
snapshot > "$TMP/rollback-restore.after"
cmp -s "$TMP/rollback-restore.before" "$TMP/rollback-restore.after"

LIVE_OVERRIDE="$TMP/live-override"
RULES_BUILD_SCOPE=full RULES_LIVE_ARTIFACT_ROOT="$LIVE_OVERRIDE" "$REPO/scripts/commands/build-artifacts-transaction.sh" >/dev/null
[ -f "$LIVE_OVERRIDE/new" ]
grep -F 'partial staged tree' "$LIVE_OVERRIDE/new" >/dev/null
[ -f "$REPO/.output/sentinel" ]

grep -F 'inject_sync_failure late-domain' "$ROOT/scripts/commands/sync-upstream.sh" >/dev/null
grep -F 'inject_sync_failure late-ip' "$ROOT/scripts/commands/sync-upstream.sh" >/dev/null
grep -F 'inject_sync_failure late-compiler' "$ROOT/scripts/commands/sync-upstream.sh" >/dev/null
grep -F 'inject_restore_failure late-binary' "$ROOT/scripts/commands/restore-artifacts.sh" >/dev/null

echo 'artifact transaction atomic failure tests passed'
