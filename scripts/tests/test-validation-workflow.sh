#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/validate.yml"

if [ ! -f "$WORKFLOW" ]; then
  echo "test failed: shared validation workflow is missing" >&2
  exit 1
fi

python3 - "$WORKFLOW" <<'PY'
import re
import sys
from pathlib import Path

workflow = Path(sys.argv[1])
text = workflow.read_text(encoding="utf-8")
validate_command = re.compile(
    r"^\s*run:\s*(?:REQUIRE_SHELLCHECK=1\s+)?make\s+validate\s*$",
    re.MULTILINE,
)

if not validate_command.search(text):
    raise SystemExit(
        f"{workflow}: shared validation must run the full make validate target"
    )

pull_request = re.compile(r"^\s*pull_request:\s*$", re.MULTILINE)
if not pull_request.search(text):
    raise SystemExit(
        f"{workflow}: shared validation must also run on pull_request so "
        "auto-upgrade and contribution PRs are validated before merge"
    )

workflow_dispatch = re.compile(r"^\s*workflow_dispatch:\s*$", re.MULTILINE)
if not workflow_dispatch.search(text):
    raise SystemExit(
        f"{workflow}: dependency updates must be able to dispatch validation"
    )
PY

echo "shared validation workflow tests passed"
