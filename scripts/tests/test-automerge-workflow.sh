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
    raise SystemExit(f"{workflow}: trusted PRs must be merged after validation")
if "gh pr merge --auto" in text:
    raise SystemExit(
        f"{workflow}: native auto-merge (--auto) must not be used for "
        "token-created PRs; GITHUB_TOKEN pushes suppress the pull_request "
        "check suite, so no check ever associates with the branch and --auto "
        "stalls forever waiting on a check that can never resolve"
    )
if not __import__("re").search(r"gh pr merge\b[^\n]*--squash[^\n]*--delete-branch", text):
    raise SystemExit(
        f"{workflow}: trusted PRs must squash-merge and delete the branch"
    )
if "gh pr review" in text:
    raise SystemExit(
        f"{workflow}: GitHub Actions cannot approve PRs when repository approval is disabled"
    )
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
