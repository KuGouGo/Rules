#!/usr/bin/env bash
set -euo pipefail

EVENT_NAME="${EVENT_NAME:-}"
INPUT_SCOPE="${INPUT_SCOPE:-auto}"
BEFORE_SHA="${BEFORE_SHA:-}"
CURRENT_SHA="${CURRENT_SHA:-HEAD}"
CHANGED_FILES_INPUT="${CHANGED_FILES:-}"
DELETED_CUSTOM_FILES_INPUT="${DELETED_CUSTOM_FILES:-}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PUBLISH_GIT_ROOT="$ROOT"
# shellcheck source=scripts/lib/baseline.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/baseline.sh"
BASELINE_FILE="${ARTIFACT_BASELINE_FILE:-$ROOT/.tmp/publication-baseline.json}"
BASELINE_INPUT_FILE="${RULES_PUBLICATION_BASELINE_INPUT:-}"

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

resolve_remote_baseline() {
  local metadata_file
  metadata_file="$(mktemp)"

  if ! fetch_publish_branch_metadata "$metadata_file"; then
    rm -f "$metadata_file"
    return 1
  fi
  mkdir -p "$(dirname "$BASELINE_FILE")"
  build_baseline_json "$metadata_file" "$BASELINE_FILE"
  rm -f "$metadata_file"
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
  local baseline_values
  if [ -n "$BASELINE_INPUT_FILE" ]; then
    baseline_values="$(validate_and_write_baseline "$BASELINE_INPUT_FILE" "$BASELINE_FILE")"
  else
    baseline_values="$(resolve_remote_baseline)"
  fi
  read -r baseline_status baseline_generation baseline_source <<< "$baseline_values"
  baseline_loaded=1
  echo "Publication baseline: status $baseline_status, generation $baseline_generation, source $baseline_source"

  if [ "$baseline_status" = "consistent" ]; then
    if ! git cat-file -e "${baseline_source}^{commit}" 2>/dev/null; then
      echo "published source commit is unavailable locally: $baseline_source; degrading baseline to inconsistent" >&2
      baseline_status="inconsistent"
      baseline_generation="-"
      baseline_source=""
    elif ! git merge-base --is-ancestor "$baseline_source" "$CURRENT_SHA"; then
      echo "published source $baseline_source is not an ancestor of candidate $CURRENT_SHA; degrading baseline to inconsistent" >&2
      baseline_status="inconsistent"
      baseline_generation="-"
      baseline_source=""
    fi
    if [ "$baseline_status" = "inconsistent" ]; then
      degrade_baseline_file "$BASELINE_FILE"
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
  grep -Eq '^(\.github/workflows/|Makefile$|config/|scripts/|sources/(builtin|custom)/|templates/|tests/)'
}

has_only_non_build_changes() {
  ! grep -Eqv '^(\.gitignore$|LICENSE$|NOTICE$|README\.md$|THIRD_PARTY_NOTICES\.md$|docs/)'
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
