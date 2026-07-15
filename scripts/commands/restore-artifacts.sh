#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ -z "${RULES_ARTIFACT_ROOT:-}" ]; then
  RULES_BUILD_SCOPE=custom exec "$ROOT/scripts/commands/build-artifacts-transaction.sh"
fi

ARTIFACT_ROOT="${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
TMP_ROOT="$ROOT/.tmp/restore-published"
RESTORE_METADATA_FILE="$TMP_ROOT/restored-branches.tsv"
BASELINE_FILE="${ARTIFACT_BASELINE_FILE:-$ROOT/.tmp/publication-baseline.json}"

inject_restore_failure() {
  local point="$1"
  if [ "${RULES_RESTORE_FAIL_AT:-}" = "$point" ]; then
    echo "injected artifact restore failure at $point" >&2
    return 1
  fi
}

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
: > "$RESTORE_METADATA_FILE"
trap 'rm -rf "$TMP_ROOT"' EXIT

remote_branch_exists() {
  local branch="$1"
  git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
}

fetch_branch_ref() {
  local branch="$1"
  git fetch --depth=1 origin "+${branch}:refs/remotes/origin/${branch}" >/dev/null 2>&1
}

restore_branch_artifacts() {
  local branch="$1"
  local tmpdir="$TMP_ROOT/$branch"

  if ! remote_branch_exists "$branch"; then
    echo "required remote branch origin/$branch not found" >&2
    return 1
  fi

  mkdir -p "$tmpdir"
  fetch_branch_ref "$branch"
  git archive "origin/$branch" domain ip README.md | tar -xf - -C "$tmpdir"

  rm -rf "$ARTIFACT_ROOT/domain/$branch" "$ARTIFACT_ROOT/ip/$branch"
  mkdir -p "$ARTIFACT_ROOT/domain/$branch" "$ARTIFACT_ROOT/ip/$branch"

  cp -R "$tmpdir/domain/." "$ARTIFACT_ROOT/domain/$branch/"
  cp -R "$tmpdir/ip/." "$ARTIFACT_ROOT/ip/$branch/"

  local commit subject generation source
  commit="$(git rev-parse "origin/$branch^{commit}")"
  subject="$(git log -1 --format=%s "origin/$branch")"
  if [[ "$subject" =~ ^chore:\ publish\ ${branch}\ artifacts\ \[generation\ ([0-9]+-[0-9]+)\ source\ ([0-9a-f]{40})\]$ ]]; then
    generation="${BASH_REMATCH[1]}"
    source="${BASH_REMATCH[2]}"
  else
    echo "origin/$branch lacks valid generation/source publication metadata" >&2
    return 1
  fi
  printf '%s\t%s\t%s\t%s\n' "$branch" "$commit" "$generation" "$source" >> "$RESTORE_METADATA_FILE"
  echo "restored $branch artifacts at $commit (generation $generation, source $source)"
}

mkdir -p "$ARTIFACT_ROOT"

restore_branch_artifacts surge
restore_branch_artifacts quanx
restore_branch_artifacts egern
inject_restore_failure late-text
restore_branch_artifacts sing-box
restore_branch_artifacts mihomo
inject_restore_failure late-binary

python3 - <<'PY' "$RESTORE_METADATA_FILE" "$ARTIFACT_ROOT/restoration-metadata.json"
import json, sys
from pathlib import Path
rows = [line.split("\t") for line in Path(sys.argv[1]).read_text().splitlines() if line]
if len(rows) != 5:
    raise SystemExit(f"restoration identity incomplete: expected 5 branch records, got {len(rows)}")
generations = {row[2] for row in rows}; sources = {row[3] for row in rows}
if len(generations) != 1 or len(sources) != 1:
    raise SystemExit(f"restored branches are from inconsistent publications: generations={sorted(generations)}, sources={sorted(sources)}")
generation = next(iter(generations)); source = next(iter(sources))
payload = {
    "status": "consistent",
    "generation_id": generation,
    "source_commit": source,
    "branches": {
        row[0]: {
            "commit": row[1],
            "generation_id": generation,
            "source_commit": source,
        }
        for row in rows
    },
}
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if [ -f "$BASELINE_FILE" ]; then
  python3 - "$BASELINE_FILE" "$ARTIFACT_ROOT/restoration-metadata.json" <<'PY'
import json
import sys
from pathlib import Path

baseline = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
restored = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if restored != baseline:
    raise SystemExit(
        "restored publication cohort differs from the selected build baseline; "
        "refusing a mixed custom build"
    )
PY
else
  mkdir -p "$(dirname "$BASELINE_FILE")"
  cp "$ARTIFACT_ROOT/restoration-metadata.json" "$BASELINE_FILE"
fi

python3 "$ROOT/scripts/tools/artifact_origins.py" reset \
  "$ARTIFACT_ROOT" \
  restored-published-branch

echo "published artifact restore done"
