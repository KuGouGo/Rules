#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPDATER="$ROOT/scripts/commands/update-upstream-pins.sh"
WORKFLOW="$ROOT/.github/workflows/update-upstream-pins.yml"

python3 - "$UPDATER" "$WORKFLOW" <<'PY'
import sys
from pathlib import Path

updater_path, workflow_path = map(Path, sys.argv[1:])
updater = updater_path.read_text(encoding="utf-8")
workflow = workflow_path.read_text(encoding="utf-8")

for required in (
    'BRANCH="automation/upstream-pins"',
    'VALIDATION_CONTEXT="upstream-pin-validation"',
    "gh workflow run validate.yml",
    "--event workflow_dispatch",
    "gh run watch",
    "statuses/${head_sha}",
    "record_validation_status",
):
    if required not in updater:
        raise SystemExit(f"{updater_path}: missing trusted validation behavior: {required}")

main_body = updater[updater.index("main()") :]
validate_call = main_body.rfind("  validate_update_branch")
status_call = main_body.rfind("  record_validation_status")
if validate_call < 0 or status_call < 0 or validate_call > status_call:
    raise SystemExit(f"{updater_path}: validation must finish before success is recorded")

for permission in ("actions: write", "statuses: write"):
    if permission not in workflow:
        raise SystemExit(f"{workflow_path}: missing permission: {permission}")
PY

echo "upstream pin updater tests passed"
