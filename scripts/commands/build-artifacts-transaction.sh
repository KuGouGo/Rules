#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/scripts/commands/check-runtime.sh"

if [ -n "${RULES_ARTIFACT_ROOT:-}" ]; then
  echo "RULES_ARTIFACT_ROOT is transaction-owned; use RULES_LIVE_ARTIFACT_ROOT to override the promotion destination" >&2
  exit 2
fi

SCOPE="${RULES_BUILD_SCOPE:-full}"
LIVE_ROOT="${RULES_LIVE_ARTIFACT_ROOT:-$ROOT/.output}"
TMP_PARENT="$ROOT/.tmp"
DIAGNOSTICS_ROOT="${RULES_ARTIFACT_DIAGNOSTICS_ROOT:-$ROOT/.artifacts/diagnostics}"
LIVE_PARENT="$(dirname "$LIVE_ROOT")"
mkdir -p "$TMP_PARENT" "$LIVE_PARENT"
TRANSACTION_ROOT="$(mktemp -d "$TMP_PARENT/artifacts.XXXXXX")"
STAGE_ROOT="$TRANSACTION_ROOT/output"
BACKUP_ROOT="$TRANSACTION_ROOT/previous-output"
FAILED_ROOT="$TRANSACTION_ROOT/failed-output"
PRESERVE_TRANSACTION_ROOT=0
HAD_LIVE_ROOT=0
PROMOTION_STATE=building
ROLLBACK_STATUS=not-required
TRANSACTION_FAILURE_REASON=command-failure
TRANSACTION_SIGNAL=""
mkdir -p "$STAGE_ROOT"

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

strict_rename() {
  local operation="$1"
  local source="$2"
  local target="$3"

  python3 - "$operation" "$source" "$target" <<'PY'
import errno
import os
import sys

operation, source, target = sys.argv[1:]
try:
    for specification in filter(
        None, os.environ.get("RULES_TRANSACTION_TEST_RENAME_FAILURES", "").split(",")
    ):
        name, separator, error_name = specification.partition(":")
        if name != operation:
            continue
        error_name = error_name if separator else "EIO"
        error_number = getattr(errno, error_name, None)
        if not isinstance(error_number, int):
            raise ValueError(f"unsupported injected errno: {error_name}")
        raise OSError(error_number, f"injected {error_name}")

    if os.path.lexists(target):
        raise FileExistsError(errno.EEXIST, "rename target already exists", target)
    os.replace(source, target)
except (OSError, ValueError) as exc:
    if isinstance(exc, OSError) and exc.errno == errno.EXDEV:
        category = "cross-device rename refused"
    else:
        category = "strict rename refused"
    print(
        f"artifact transaction {operation} rename failed ({category}): "
        f"{source} -> {target}: {exc}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

assert_promotion_filesystem() {
  python3 - "$TRANSACTION_ROOT" "$LIVE_PARENT" "$LIVE_ROOT" <<'PY'
import os
import sys

transaction_root, live_parent, live_root = map(os.path.abspath, sys.argv[1:])
transaction_device = os.stat(transaction_root).st_dev
parent_device = os.stat(live_parent).st_dev

if os.environ.get("RULES_TRANSACTION_TEST_DEVICE_MISMATCH") == "1":
    parent_device = transaction_device + 1

if transaction_device != parent_device:
    raise SystemExit(
        "cross-device artifact promotion refused before build: "
        f"staging device {transaction_device}, live parent device {parent_device}"
    )

if os.path.lexists(live_root):
    live_device = os.lstat(live_root).st_dev
    if transaction_device != live_device:
        raise SystemExit(
            "cross-device artifact promotion refused before build: "
            f"staging device {transaction_device}, existing live device {live_device}"
        )
PY
}

rollback_promotion() {
  case "$PROMOTION_STATE" in
    building|committed)
      return 0
      ;;
    rolled-back)
      ROLLBACK_STATUS=succeeded
      return 0
      ;;
    backup-pending|backed-up|promotion-pending) ;;
    *)
      echo "unknown artifact promotion state during rollback: $PROMOTION_STATE" >&2
      ROLLBACK_STATUS=failed
      PRESERVE_TRANSACTION_ROOT=1
      return 1
      ;;
  esac

  ROLLBACK_STATUS=in-progress
  if [ "$HAD_LIVE_ROOT" -eq 1 ]; then
    if path_exists "$BACKUP_ROOT"; then
      if path_exists "$LIVE_ROOT" \
        && ! strict_rename rollback-discard "$LIVE_ROOT" "$FAILED_ROOT"; then
        echo "failed to move incomplete live root aside: $LIVE_ROOT" >&2
        ROLLBACK_STATUS=failed
        PRESERVE_TRANSACTION_ROOT=1
        return 1
      fi
      if ! strict_rename rollback-restore "$BACKUP_ROOT" "$LIVE_ROOT"; then
        echo "failed to restore previous live root; recover it from $BACKUP_ROOT" >&2
        ROLLBACK_STATUS=failed
        PRESERVE_TRANSACTION_ROOT=1
        return 1
      fi
    elif ! path_exists "$LIVE_ROOT"; then
      echo "previous live root is missing from both live and backup paths" >&2
      ROLLBACK_STATUS=failed
      PRESERVE_TRANSACTION_ROOT=1
      return 1
    fi
  elif path_exists "$LIVE_ROOT"; then
    if ! strict_rename rollback-discard "$LIVE_ROOT" "$FAILED_ROOT"; then
      echo "failed to remove incomplete first-time live root: $LIVE_ROOT" >&2
      ROLLBACK_STATUS=failed
      PRESERVE_TRANSACTION_ROOT=1
      return 1
    fi
  fi

  PROMOTION_STATE=rolled-back
  ROLLBACK_STATUS=succeeded
}

write_transaction_health() {
  local output_file="$1"
  python3 - \
    "$output_file" \
    "$SCOPE" \
    "$TRANSACTION_FAILURE_REASON" \
    "$PROMOTION_STATE" \
    "$ROLLBACK_STATUS" \
    "$TRANSACTION_SIGNAL" <<'PY'
import json
import sys

output, scope, reason, promotion_state, rollback_status, signal = sys.argv[1:]
payload = {
    "failure_reason": reason,
    "promotion_state": promotion_state,
    "rollback_status": rollback_status,
    "scope": scope,
    "status": "failed",
}
if signal:
    payload["signal"] = signal
with open(output, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(payload, handle, separators=(",", ":"), sort_keys=True)
    handle.write("\n")
PY
}

preserve_failure_diagnostics() {
  local status=$?
  trap - EXIT HUP INT TERM
  set +e
  if [ "$status" -ne 0 ]; then
    rollback_promotion
    local failure_dir
    failure_dir="$DIAGNOSTICS_ROOT/${ARTIFACT_GENERATION_ID:-local}-$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$failure_dir"
    [ ! -f "$STAGE_ROOT/upstream-summary.json" ] || cp "$STAGE_ROOT/upstream-summary.json" "$failure_dir/"
    [ ! -f "$STAGE_ROOT/build-summary.json" ] || cp "$STAGE_ROOT/build-summary.json" "$failure_dir/"
    [ ! -f "$DIAGNOSTICS_ROOT/upstream-summary.jsonl" ] || mv "$DIAGNOSTICS_ROOT/upstream-summary.jsonl" "$failure_dir/"
    write_transaction_health "$failure_dir/transaction-health.json"
    echo "failure diagnostics preserved in $failure_dir" >&2
  fi
  if [ "$PRESERVE_TRANSACTION_ROOT" -eq 1 ]; then
    echo "transaction recovery data preserved in $TRANSACTION_ROOT" >&2
  else
    rm -rf "$TRANSACTION_ROOT"
  fi
  return "$status"
}

handle_transaction_signal() {
  local signal="$1"
  local status="$2"

  trap - HUP INT TERM
  TRANSACTION_FAILURE_REASON=signal
  TRANSACTION_SIGNAL="$signal"
  echo "artifact transaction received $signal signal" >&2
  rollback_promotion || true
  exit "$status"
}

inject_signal_after_backup() {
  local signal="${RULES_TRANSACTION_TEST_SIGNAL_AFTER_BACKUP:-}"

  case "$signal" in
    '') return 0 ;;
    HUP|INT|TERM) kill -s "$signal" "$$" ;;
    *)
      echo "unsupported injected transaction signal: $signal" >&2
      return 2
      ;;
  esac
}

trap preserve_failure_diagnostics EXIT
trap 'handle_transaction_signal HUP 129' HUP
trap 'handle_transaction_signal INT 130' INT
trap 'handle_transaction_signal TERM 143' TERM

if ! assert_promotion_filesystem; then
  TRANSACTION_FAILURE_REASON=filesystem-preflight-failed
  exit 2
fi

export RULES_ARTIFACT_ROOT="$STAGE_ROOT"
export RULES_ARTIFACT_DIAGNOSTICS_ROOT="$DIAGNOSTICS_ROOT"

case "$SCOPE" in
  full) "$ROOT/scripts/commands/sync-upstream.sh" ;;
  custom) "$ROOT/scripts/commands/restore-artifacts.sh" ;;
  *) echo "unsupported build scope: $SCOPE" >&2; exit 2 ;;
esac

"$ROOT/scripts/commands/build-custom.sh"
"$ROOT/scripts/commands/guard-artifacts.sh"
python3 "$ROOT/scripts/tools/summarize-artifacts.py" "$STAGE_ROOT" --output "$STAGE_ROOT/build-summary.json" >/dev/null
ARTIFACT_BUILD_SCOPE="$SCOPE" "$ROOT/scripts/commands/generate-artifact-manifest.sh"
"$ROOT/scripts/commands/verify-artifact-manifest.sh"

if path_exists "$LIVE_ROOT"; then
  HAD_LIVE_ROOT=1
  PROMOTION_STATE=backup-pending
  if ! strict_rename backup "$LIVE_ROOT" "$BACKUP_ROOT"; then
    TRANSACTION_FAILURE_REASON=backup-rename-failed
    rollback_promotion || true
    exit 1
  fi
  PROMOTION_STATE=backed-up
  inject_signal_after_backup
fi

PROMOTION_STATE=promotion-pending
if ! strict_rename promote "$STAGE_ROOT" "$LIVE_ROOT"; then
  TRANSACTION_FAILURE_REASON=promotion-rename-failed
  rollback_promotion || true
  exit 1
fi
PROMOTION_STATE=committed

if ! rm -rf "$BACKUP_ROOT"; then
  echo "warning: promoted artifacts but could not remove backup: $BACKUP_ROOT" >&2
fi
echo "artifact transaction promoted: $LIVE_ROOT"
