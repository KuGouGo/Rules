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

PUBLISH_GIT_ROOT="$ROOT"
# shellcheck source=scripts/lib/baseline.sh
source "$ROOT/scripts/lib/baseline.sh"

inject_restore_failure() {
  local point="$1"
  if [ "${RULES_RESTORE_FAIL_AT:-}" = "$point" ]; then
    echo "injected artifact restore failure at $point" >&2
    return 1
  fi
}

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

restore_branch_artifacts() {
  local branch="$1"
  local commit generation source
  local tmpdir="$TMP_ROOT/$branch"

  if ! commit="$(git rev-parse --verify "origin/$branch^{commit}" 2>/dev/null)"; then
    echo "origin/$branch does not exist; cannot restore artifacts" >&2
    return 1
  fi
  generation="$(awk -F '\t' -v branch="$branch" '$1 == branch {print $3}' "$RESTORE_METADATA_FILE")"
  source="$(awk -F '\t' -v branch="$branch" '$1 == branch {print $4}' "$RESTORE_METADATA_FILE")"
  if [ -z "$generation" ] || [ "$generation" = "-" ] \
    || [ -z "$source" ] || [ "$source" = "-" ]; then
    echo "origin/$branch lacks valid generation/source publication metadata" >&2
    return 1
  fi

  mkdir -p "$tmpdir"
  git archive "origin/$branch" domain ip README.md | tar -xf - -C "$tmpdir"

  rm -rf "$ARTIFACT_ROOT/domain/$branch" "$ARTIFACT_ROOT/ip/$branch"
  mkdir -p "$ARTIFACT_ROOT/domain/$branch" "$ARTIFACT_ROOT/ip/$branch"

  cp -R "$tmpdir/domain/." "$ARTIFACT_ROOT/domain/$branch/"
  cp -R "$tmpdir/ip/." "$ARTIFACT_ROOT/ip/$branch/"

  echo "restored $branch artifacts at $commit (generation $generation, source $source)"
}

mkdir -p "$ARTIFACT_ROOT"

if ! fetch_publish_branch_metadata "$RESTORE_METADATA_FILE"; then
  exit 1
fi

restore_branch_artifacts surge
restore_branch_artifacts quanx
restore_branch_artifacts egern
inject_restore_failure late-text
restore_branch_artifacts sing-box
restore_branch_artifacts mihomo
inject_restore_failure late-binary

restoration_identity="$(build_baseline_json "$RESTORE_METADATA_FILE" "$ARTIFACT_ROOT/restoration-metadata.json")"
read -r RESTORATION_STATUS _ <<< "$restoration_identity"
if [ "$RESTORATION_STATUS" != "consistent" ]; then
  echo "restored branches are from inconsistent publications" >&2
  exit 1
fi

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
