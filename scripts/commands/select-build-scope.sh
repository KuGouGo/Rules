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
elif [ "$EVENT_NAME" = "push" ] || [ "$EVENT_NAME" = "pull_request" ]; then
  before="$BEFORE_SHA"
  if [ "$EVENT_NAME" = "push" ] && { [ -z "$before" ] || [ "$before" = "0000000000000000000000000000000000000000" ]; }; then
    before="$(git rev-parse "${CURRENT_SHA}^" 2>/dev/null || true)"
  fi
  base_sha="$before"

  if [ -z "$CHANGED_FILES_INPUT" ] && {
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

print_output
