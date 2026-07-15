#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW_ROOT="${WORKFLOW_ROOT:-$ROOT/.github/workflows}"

python3 - "$WORKFLOW_ROOT" <<'PY'
import re
import sys
from pathlib import Path

workflow_root = Path(sys.argv[1])
workflow_paths = sorted(
    [*workflow_root.rglob("*.yml"), *workflow_root.rglob("*.yaml")]
)
uses_key = re.compile(r"^\s*(?:-\s*)?uses\s*:")
uses_value = re.compile(
    r'''^\s*(?:-\s*)?uses\s*:\s*(?:"([^"]+)"|'([^']+)'|([^\s#]+))\s*(?:#.*)?$'''
)
pinned_ref = re.compile(r"^[^@\s]+@[0-9a-fA-F]{40}$")
errors = []
uses_count = 0

if not workflow_paths:
    errors.append(f"no workflow files found under {workflow_root}")

for workflow_path in workflow_paths:
    for line_number, line in enumerate(
        workflow_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not uses_key.match(line):
            continue
        uses_count += 1
        match = uses_value.match(line)
        reference = next((value for value in match.groups() if value), None) if match else None
        if reference is None or not pinned_ref.fullmatch(reference):
            shown = reference if reference is not None else line.strip()
            errors.append(
                f"{workflow_path}:{line_number}: uses reference must end in a full "
                f"40-character commit SHA: {shown}"
            )

if uses_count == 0:
    errors.append(f"no uses references found under {workflow_root}")

if errors:
    print("workflow action pinning validation failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"workflow action pinning validated: {uses_count} references")
PY
