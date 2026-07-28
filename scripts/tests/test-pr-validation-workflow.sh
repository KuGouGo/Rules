#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pull-request.yml"

if [ ! -f "$WORKFLOW" ]; then
  echo "test failed: pull request workflow is missing" >&2
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
        f"{workflow}: pull request validation must run the full make validate target"
    )
PY

echo "pull request validation workflow tests passed"
