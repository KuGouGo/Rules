#!/usr/bin/env bash
set -euo pipefail

EVENT_NAME="${EVENT_NAME:-}"
INPUT_SCOPE="${INPUT_SCOPE:-auto}"
BEFORE_SHA="${BEFORE_SHA:-}"
CURRENT_SHA="${CURRENT_SHA:-HEAD}"
CHANGED_FILES_INPUT="${CHANGED_FILES:-}"
DELETED_CUSTOM_FILES_INPUT="${DELETED_CUSTOM_FILES:-}"

scope="full"
reason="scheduled sync refresh"
base_sha=""

print_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "scope=$scope"
      echo "reason=$reason"
      echo "base_sha=$base_sha"
    } >> "$GITHUB_OUTPUT"
  fi

  echo "scope=$scope"
  echo "reason=$reason"
  echo "base_sha=$base_sha"
  echo "Build scope: $scope ($reason)"
}

collect_changed_files() {
  local before="$1"
  local current="$2"

  if [ -n "$CHANGED_FILES_INPUT" ]; then
    printf '%s\n' "$CHANGED_FILES_INPUT"
    return 0
  fi

  if [ -n "$before" ]; then
    git diff --name-only "$before" "$current"
  else
    git diff-tree --no-commit-id --name-only -r "$current"
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
    git diff --name-only --diff-filter=D "$before" "$current" -- 'sources/custom/**'
  else
    git diff-tree --no-commit-id --name-only --diff-filter=D -r "$current" -- 'sources/custom/**'
  fi
}

if [ "$EVENT_NAME" = "workflow_dispatch" ]; then
  case "$INPUT_SCOPE" in
    custom)
      base_sha="$(git rev-parse HEAD^ 2>/dev/null || true)"
      if [ -z "$base_sha" ] || ! changed_files="$(collect_changed_files "$base_sha" "$CURRENT_SHA")"; then
        scope="full"
        reason="manual custom baseline unavailable; using full sync"
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
elif [ "$EVENT_NAME" = "push" ]; then
  before="$BEFORE_SHA"
  if [ -z "$before" ] || [ "$before" = "0000000000000000000000000000000000000000" ]; then
    before="$(git rev-parse "${CURRENT_SHA}^" 2>/dev/null || true)"
  fi
  base_sha="$before"

  if [ -z "$CHANGED_FILES_INPUT" ] && {
    [ -z "$before" ] ||
    ! git cat-file -e "${before}^{commit}" 2>/dev/null ||
    ! git cat-file -e "${CURRENT_SHA}^{commit}" 2>/dev/null
  }; then
    scope="full"
    reason="push base unavailable; using full sync"
    base_sha=""
  else
    if ! changed_files="$(collect_changed_files "$before" "$CURRENT_SHA")"; then
      scope="full"
      reason="push diff unavailable; using full sync"
      base_sha=""
      changed_files=""
    elif ! deleted_custom_files="$(collect_deleted_custom_files "$before" "$CURRENT_SHA")"; then
      scope="full"
      reason="push diff unavailable; using full sync"
      base_sha=""
      deleted_custom_files=""
    else
      echo "Changed files:"
      printf '%s\n' "$changed_files"

      if [ -z "$changed_files" ]; then
        scope="full"
        reason="push diff empty; using full sync"
      elif [ -n "$deleted_custom_files" ]; then
        scope="full"
        reason="custom deletions require full sync"
      elif printf '%s\n' "$changed_files" | grep -Eqv '^sources/custom/'; then
        scope="full"
        reason="push includes non-custom changes"
      else
        scope="custom"
        reason="push only updates custom sources"
      fi
    fi
  fi
fi

print_output
