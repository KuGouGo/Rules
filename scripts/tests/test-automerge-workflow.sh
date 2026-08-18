#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/automerge.yml"

python3 - "$WORKFLOW" <<'PY'
import sys
from pathlib import Path

workflow = Path(sys.argv[1])
text = workflow.read_text(encoding="utf-8")

if "workflow_run:" not in text or "workflows: [Update dependencies]" not in text:
    raise SystemExit(
        f"{workflow}: token-created dependency PRs need a workflow_run trigger"
    )
if "github.event.workflow_run.conclusion == 'success'" not in text:
    raise SystemExit(f"{workflow}: failed dependency updates must not be merged")
if "gh pr merge" not in text:
    raise SystemExit(f"{workflow}: trusted PRs must be merged after checks")
if "gh pr checks" not in text or "--required" not in text:
    raise SystemExit(f"{workflow}: required PR checks must pass before merge")
if "gh pr review" in text:
    raise SystemExit(
        f"{workflow}: GitHub Actions cannot approve PRs when repository approval is disabled"
    )
if "gh pr checks" in text and text.index("gh pr checks") > text.index("gh pr merge"):
    raise SystemExit(f"{workflow}: merge runs before validation checks")
if "github.head_ref == 'automation/dependency-updates'" not in text:
    raise SystemExit(f"{workflow}: fixed dependency branch is not trusted")
if "github.event.pull_request.head.repo.full_name == github.repository" not in text:
    raise SystemExit(f"{workflow}: dependency PR must originate from this repository")
if "github.event.pull_request.user.login == 'github-actions[bot]'" not in text:
    raise SystemExit(f"{workflow}: dependency PR author is not restricted to Actions")
for guard in (".head.ref", ".head.repo.full_name", ".user.login"):
    if guard not in text:
        raise SystemExit(f"{workflow}: runtime trust guard is missing: {guard}")
if "dependabot/" in text or "chore/update-tool-versions" in text:
    raise SystemExit(f"{workflow}: legacy dependency branches remain trusted")
PY

echo "automerge workflow tests passed"
