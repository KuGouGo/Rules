#!/usr/bin/env bash
set -euo pipefail

EVENT_NAME="${EVENT_NAME:-}"
INPUT_SCOPE="${INPUT_SCOPE:-auto}"
BEFORE_SHA="${BEFORE_SHA:-}"
CURRENT_SHA="${CURRENT_SHA:-HEAD}"
CHANGED_FILES_INPUT="${CHANGED_FILES:-}"
DELETED_CUSTOM_FILES_INPUT="${DELETED_CUSTOM_FILES:-}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BASELINE_FILE="${ARTIFACT_BASELINE_FILE:-$ROOT/.tmp/publication-baseline.json}"
BASELINE_INPUT_FILE="${RULES_PUBLICATION_BASELINE_INPUT:-}"
PUBLISH_BRANCHES=(surge quanx egern sing-box mihomo)

scope="full"
reason="scheduled sync refresh"
base_sha=""

print_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "scope=$scope"
      echo "reason=$reason"
      echo "base_sha=$base_sha"
      echo "baseline_file=$BASELINE_FILE"
    } >> "$GITHUB_OUTPUT"
  fi

  echo "scope=$scope"
  echo "reason=$reason"
  echo "base_sha=$base_sha"
  echo "baseline_file=$BASELINE_FILE"
  echo "Build scope: $scope ($reason)"
}

validate_and_write_baseline() {
  local input_file="$1"
  local output_file="$2"

  mkdir -p "$(dirname "$output_file")"
  python3 - "$input_file" "$output_file" <<'PY'
import json
import re
import sys
from pathlib import Path

source_path, output_path = map(Path, sys.argv[1:])
branches = {"surge", "quanx", "egern", "sing-box", "mihomo"}
sha_re = re.compile(r"[0-9a-f]{40}")
generation_re = re.compile(r"[0-9]+-[0-9]+")

try:
    payload = json.loads(source_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"publication baseline unreadable: {exc}")

if not isinstance(payload, dict) or set(payload) != {"status", "generation_id", "source_commit", "branches"}:
    raise SystemExit("publication baseline has an invalid top-level schema")
if payload["status"] not in {"consistent", "inconsistent"}:
    raise SystemExit("publication baseline status must be consistent or inconsistent")
if not isinstance(payload["branches"], dict) or set(payload["branches"]) != branches:
    raise SystemExit("publication baseline must record exactly the five publish branches")
for branch, item in payload["branches"].items():
    if not isinstance(item, dict) or set(item) != {"commit", "generation_id", "source_commit"}:
        raise SystemExit(f"publication baseline branch entry is invalid: {branch}")
    if not isinstance(item["commit"], str) or not sha_re.fullmatch(item["commit"]):
        raise SystemExit(f"publication baseline branch commit is invalid: {branch}")
    if item["generation_id"] is not None and (
        not isinstance(item["generation_id"], str) or not generation_re.fullmatch(item["generation_id"])
    ):
        raise SystemExit(f"publication baseline branch generation is invalid: {branch}")
    if item["source_commit"] is not None and (
        not isinstance(item["source_commit"], str) or not sha_re.fullmatch(item["source_commit"])
    ):
        raise SystemExit(f"publication baseline branch source is invalid: {branch}")

if payload["status"] == "consistent":
    if not isinstance(payload["generation_id"], str) or not generation_re.fullmatch(payload["generation_id"]):
        raise SystemExit("consistent publication baseline generation_id is invalid")
    if not isinstance(payload["source_commit"], str) or not sha_re.fullmatch(payload["source_commit"]):
        raise SystemExit("consistent publication baseline source_commit is invalid")
    identities = {(item["generation_id"], item["source_commit"]) for item in payload["branches"].values()}
    if identities != {(payload["generation_id"], payload["source_commit"])}:
        raise SystemExit("consistent publication baseline branch identities disagree")
elif payload["generation_id"] is not None or payload["source_commit"] is not None:
    raise SystemExit("inconsistent publication baseline must use null cohort identity")

output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(payload["status"], payload["generation_id"] or "-", payload["source_commit"] or "-")
PY
}

resolve_remote_baseline() {
  local metadata_file branch commit subject generation source
  metadata_file="$(mktemp)"
  trap 'rm -f "$metadata_file"' RETURN

  : > "$metadata_file"
  for branch in "${PUBLISH_BRANCHES[@]}"; do
    if ! git fetch --quiet --no-tags --depth=1 origin \
      "+refs/heads/$branch:refs/remotes/origin/$branch"; then
      echo "required remote publication branch origin/$branch is unavailable" >&2
      return 1
    fi
    commit="$(git rev-parse --verify "origin/$branch^{commit}")"
    subject="$(git log -1 --format=%s "origin/$branch")"
    if [[ "$subject" =~ ^chore:\ publish\ ${branch}\ artifacts\ \[generation\ ([0-9]+-[0-9]+)\ source\ ([0-9a-f]{40})\]$ ]]; then
      generation="${BASH_REMATCH[1]}"
      source="${BASH_REMATCH[2]}"
    else
      generation="-"
      source="-"
    fi
    printf '%s\t%s\t%s\t%s\n' "$branch" "$commit" "$generation" "$source" >> "$metadata_file"
  done

  mkdir -p "$(dirname "$BASELINE_FILE")"
  python3 - "$metadata_file" "$BASELINE_FILE" <<'PY'
import json
import sys
from pathlib import Path

rows = [line.split("\t") for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line]
if len(rows) != 5:
    raise SystemExit(f"publication baseline incomplete: expected 5 branches, got {len(rows)}")
valid_identities = {(row[2], row[3]) for row in rows if row[2] != "-" and row[3] != "-"}
consistent = len(valid_identities) == 1 and all(row[2] != "-" and row[3] != "-" for row in rows)
generation, source = next(iter(valid_identities)) if consistent else (None, None)
payload = {
    "status": "consistent" if consistent else "inconsistent",
    "generation_id": generation,
    "source_commit": source,
    "branches": {
        row[0]: {
            "commit": row[1],
            "generation_id": None if row[2] == "-" else row[2],
            "source_commit": None if row[3] == "-" else row[3],
        }
        for row in rows
    },
}
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(payload["status"], payload["generation_id"] or "-", payload["source_commit"] or "-")
PY
}

if ! git cat-file -e "${CURRENT_SHA}^{commit}" 2>/dev/null; then
  echo "current source commit is unavailable: $CURRENT_SHA" >&2
  exit 1
fi
CURRENT_SHA="$(git rev-parse "${CURRENT_SHA}^{commit}")"

baseline_loaded=0
baseline_status=""
baseline_generation=""
baseline_source=""

load_publication_baseline() {
  if [ "$baseline_loaded" -eq 1 ]; then
    return 0
  fi
  if [ -n "$BASELINE_INPUT_FILE" ]; then
    read -r baseline_status baseline_generation baseline_source < <(
      validate_and_write_baseline "$BASELINE_INPUT_FILE" "$BASELINE_FILE"
    )
  else
    read -r baseline_status baseline_generation baseline_source < <(resolve_remote_baseline)
  fi
  baseline_loaded=1
  echo "Publication baseline: status $baseline_status, generation $baseline_generation, source $baseline_source"

  if [ "$baseline_status" = "consistent" ]; then
    if ! git cat-file -e "${baseline_source}^{commit}" 2>/dev/null; then
      echo "published source commit is unavailable locally: $baseline_source" >&2
      return 1
    fi
    if ! git merge-base --is-ancestor "$baseline_source" "$CURRENT_SHA"; then
      echo "stale source refused: published source $baseline_source is not an ancestor of candidate $CURRENT_SHA" >&2
      return 1
    fi
  fi
}

collect_changed_files() {
  local before="$1"
  local current="$2"

  if [ -n "$CHANGED_FILES_INPUT" ]; then
    printf '%s\n' "$CHANGED_FILES_INPUT"
    return 0
  fi

  if [ -n "$before" ]; then
    git diff --no-renames --name-only "$before" "$current"
  else
    git diff-tree --no-renames --no-commit-id --name-only -r "$current"
  fi
}

collect_deleted_custom_files() {
  local before="$1"
  local current="$2"

  if [ -n "$DELETED_CUSTOM_FILES_INPUT" ]; then
    printf '%s\n' "$DELETED_CUSTOM_FILES_INPUT"
    return 0
  fi

  if [ -n "$CHANGED_FILES_INPUT" ]; then
    return 0
  fi

  if [ -n "$before" ]; then
    git diff --no-renames --name-only --diff-filter=D "$before" "$current" -- 'sources/custom/**'
  else
    git diff-tree --no-renames --no-commit-id --name-only --diff-filter=D -r "$current" -- 'sources/custom/**'
  fi
}

has_build_relevant_changes() {
  grep -Eq '^(\.github/workflows/|Makefile$|config/|scripts/|sources/custom/|templates/|tests/)'
}

has_only_non_build_changes() {
  ! grep -Eqv '^(\.github/(CODEOWNERS$|ISSUE_TEMPLATE/|dependabot\.yml$|pull_request_template\.md$)|\.gitignore$|CONTRIBUTING\.md$|LICENSE$|NOTICE$|README\.md$|SECURITY\.md$|THIRD_PARTY_NOTICES\.md$|docs/)'
}

if [ "$EVENT_NAME" != "pull_request" ]; then
  load_publication_baseline
fi

if [ "$EVENT_NAME" = "workflow_dispatch" ]; then
  case "$INPUT_SCOPE" in
    custom)
      if [ "$baseline_status" != "consistent" ]; then
        scope="full"
        reason="publication cohort inconsistent; using full sync"
        base_sha=""
      else
        base_sha="$baseline_source"
      fi
      if [ "$scope" = "full" ] && [ "$reason" = "publication cohort inconsistent; using full sync" ]; then
        :
      elif [ -z "$base_sha" ] || ! changed_files="$(collect_changed_files "$base_sha" "$CURRENT_SHA")"; then
        scope="full"
        reason="manual custom publication baseline unavailable; using full sync"
        base_sha=""
      elif ! deleted_custom_files="$(collect_deleted_custom_files "$base_sha" "$CURRENT_SHA")"; then
        scope="full"
        reason="manual custom diff unavailable; using full sync"
        base_sha=""
      elif [ -z "$changed_files" ]; then
        scope="full"
        reason="manual custom delta empty; using full sync"
      elif [ -n "$deleted_custom_files" ]; then
        scope="full"
        reason="custom deletions require full sync"
      elif printf '%s\n' "$changed_files" | grep -Eqv '^sources/custom/'; then
        echo "manual custom scope refused: delta contains non-custom paths" >&2
        printf '%s\n' "$changed_files" >&2
        exit 1
      else
        scope="custom"
        reason="manual custom-only publish"
      fi
      ;;
    full|auto)
      scope="full"
      reason="manual full sync"
      ;;
    *)
      echo "unsupported workflow_dispatch scope: $INPUT_SCOPE" >&2
      exit 1
      ;;
  esac
elif [ "$EVENT_NAME" = "push" ] || [ "$EVENT_NAME" = "pull_request" ]; then
  if [ "$EVENT_NAME" = "push" ]; then
    if [ "$baseline_status" != "consistent" ]; then
      scope="full"
      reason="publication cohort inconsistent; using full sync"
      base_sha=""
      before=""
    else
      before="$baseline_source"
    fi
  else
    before="$BEFORE_SHA"
  fi
  if [ "$baseline_status" = "consistent" ] || [ "$EVENT_NAME" = "pull_request" ]; then
    base_sha="$before"
  fi

  if [ "$EVENT_NAME" = "push" ] && [ "$baseline_status" != "consistent" ]; then
    :
  elif [ -z "$CHANGED_FILES_INPUT" ] && {
    [ -z "$before" ] ||
    ! git cat-file -e "${before}^{commit}" 2>/dev/null ||
    ! git cat-file -e "${CURRENT_SHA}^{commit}" 2>/dev/null
  }; then
    scope="full"
    reason="$EVENT_NAME base unavailable; using full sync"
    base_sha=""
  else
    if ! changed_files="$(collect_changed_files "$before" "$CURRENT_SHA")"; then
      scope="full"
      reason="$EVENT_NAME diff unavailable; using full sync"
      base_sha=""
      changed_files=""
    elif ! deleted_custom_files="$(collect_deleted_custom_files "$before" "$CURRENT_SHA")"; then
      scope="full"
      reason="$EVENT_NAME diff unavailable; using full sync"
      base_sha=""
      deleted_custom_files=""
    else
      echo "Changed files:"
      printf '%s\n' "$changed_files"

      if [ -z "$changed_files" ]; then
        scope="full"
        reason="$EVENT_NAME diff empty; using full sync"
      elif [ -n "$deleted_custom_files" ]; then
        scope="full"
        reason="custom deletions require full sync"
      elif ! printf '%s\n' "$changed_files" | has_build_relevant_changes; then
        if [ "$EVENT_NAME" = "pull_request" ] \
          && printf '%s\n' "$changed_files" | has_only_non_build_changes; then
          scope="none"
          reason="pull_request has no build-relevant changes"
        elif [ "$EVENT_NAME" = "pull_request" ]; then
          scope="full"
          reason="pull_request includes unclassified changes"
        else
          scope="full"
          reason="push includes non-custom changes"
        fi
      elif printf '%s\n' "$changed_files" | grep -Eqv '^sources/custom/'; then
        scope="full"
        reason="$EVENT_NAME includes changes outside custom sources"
      else
        scope="custom"
        reason="$EVENT_NAME only updates custom sources"
      fi
    fi
  fi
fi

if [ "$EVENT_NAME" = "pull_request" ] && [ "$scope" != "none" ]; then
  load_publication_baseline
  if [ "$scope" = "custom" ] && [ "$baseline_status" != "consistent" ]; then
    scope="full"
    reason="publication cohort inconsistent; using full sync"
    base_sha=""
  fi
fi

print_output
