#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ -n "${RULES_ARTIFACT_ROOT:-}" ]; then
  echo "RULES_ARTIFACT_ROOT is transaction-owned; use RULES_LIVE_ARTIFACT_ROOT to override the promotion destination" >&2
  exit 2
fi

SCOPE="${RULES_BUILD_SCOPE:-full}"
LIVE_ROOT="${RULES_LIVE_ARTIFACT_ROOT:-$ROOT/.output}"
TMP_PARENT="$ROOT/.tmp"
DIAGNOSTICS_ROOT="${RULES_ARTIFACT_DIAGNOSTICS_ROOT:-$ROOT/.artifacts/diagnostics}"
mkdir -p "$TMP_PARENT"
TRANSACTION_ROOT="$(mktemp -d "$TMP_PARENT/artifacts.XXXXXX")"
STAGE_ROOT="$TRANSACTION_ROOT/output"
BACKUP_ROOT="$TRANSACTION_ROOT/previous-output"
mkdir -p "$STAGE_ROOT"

preserve_failure_diagnostics() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    local failure_dir
    failure_dir="$DIAGNOSTICS_ROOT/${ARTIFACT_GENERATION_ID:-local}-$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$failure_dir"
    [ ! -f "$STAGE_ROOT/upstream-summary.json" ] || cp "$STAGE_ROOT/upstream-summary.json" "$failure_dir/"
    [ ! -f "$STAGE_ROOT/build-summary.json" ] || cp "$STAGE_ROOT/build-summary.json" "$failure_dir/"
    [ ! -f "$DIAGNOSTICS_ROOT/upstream-summary.jsonl" ] || mv "$DIAGNOSTICS_ROOT/upstream-summary.jsonl" "$failure_dir/"
    printf '{"scope":"%s","status":"failed"}\n' "$SCOPE" > "$failure_dir/transaction-health.json"
    echo "failure diagnostics preserved in $failure_dir" >&2
  fi
  rm -rf "$TRANSACTION_ROOT"
  return "$status"
}
trap preserve_failure_diagnostics EXIT

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

mkdir -p "$(dirname "$LIVE_ROOT")"
if [ -e "$LIVE_ROOT" ]; then
  mv "$LIVE_ROOT" "$BACKUP_ROOT"
fi
if ! mv "$STAGE_ROOT" "$LIVE_ROOT"; then
  [ ! -e "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$LIVE_ROOT"
  exit 1
fi
rm -rf "$BACKUP_ROOT"
echo "artifact transaction promoted: $LIVE_ROOT"
