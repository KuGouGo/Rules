#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/commands/select-build-scope.sh"

assert_scope() {
  local expected_scope="$1"
  local expected_reason="$2"
  shift 2

  local output
  output="$(env "$@" "$SCRIPT")"
  grep -Fx "scope=$expected_scope" <<< "$output" >/dev/null || {
    echo "expected scope=$expected_scope" >&2
    echo "$output" >&2
    return 1
  }
  grep -Fx "reason=$expected_reason" <<< "$output" >/dev/null || {
    echo "expected reason=$expected_reason" >&2
    echo "$output" >&2
    return 1
  }
}

assert_scope full "manual full sync" \
  EVENT_NAME=workflow_dispatch INPUT_SCOPE=auto

assert_scope custom "manual custom-only publish" \
  EVENT_NAME=workflow_dispatch INPUT_SCOPE=custom

assert_scope custom "push only updates custom sources" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/emby.list\nsources/custom/ip/private.list'

assert_scope full "push includes non-custom changes" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/emby.list\nscripts/commands/build-custom.sh'

assert_scope full "custom deletions require full sync" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/emby.list' \
  DELETED_CUSTOM_FILES=$'sources/custom/domain/old.list'

echo "build scope tests passed"
