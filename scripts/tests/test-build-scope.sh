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
  EVENT_NAME=workflow_dispatch INPUT_SCOPE=custom CURRENT_SHA=HEAD \
  CHANGED_FILES=$'sources/custom/domain/emby.list'

assert_scope full "custom deletions require full sync" \
  EVENT_NAME=workflow_dispatch INPUT_SCOPE=custom CURRENT_SHA=HEAD \
  CHANGED_FILES=$'sources/custom/domain/old.list' \
  DELETED_CUSTOM_FILES=$'sources/custom/domain/old.list'

assert_scope custom "push only updates custom sources" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/emby.list\nsources/custom/ip/example.list'

assert_scope full "push includes changes outside custom sources" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/emby.list\nscripts/commands/build-custom.sh'

assert_scope full "custom deletions require full sync" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/emby.list' \
  DELETED_CUSTOM_FILES=$'sources/custom/domain/old.list'

assert_scope full "push base unavailable; using full sync" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=missing-build-scope-base

assert_scope none "pull_request has no build-relevant changes" \
  EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'README.md\ndocs/DEVELOPMENT.md'

assert_scope custom "pull_request only updates custom sources" \
  EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/fakeip-filter.list'

assert_scope full "custom deletions require full sync" \
  EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/old.list' \
  DELETED_CUSTOM_FILES=$'sources/custom/domain/old.list'

assert_scope full "pull_request includes changes outside custom sources" \
  EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'README.md\nscripts/commands/build-custom.sh'

assert_scope full "pull_request includes unclassified changes" \
  EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'pyproject.toml'

assert_scope full "pull_request includes changes outside custom sources" \
  EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA=base \
  CHANGED_FILES=$'sources/custom/domain/fakeip-filter.list\ntools/generate.py'

assert_scope full "pull_request base unavailable; using full sync" \
  EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA=missing-build-scope-base

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
ROOT_COMMIT_REPO="$TEST_TMP/root-commit"
mkdir -p "$ROOT_COMMIT_REPO"
git -C "$ROOT_COMMIT_REPO" init -q
git -C "$ROOT_COMMIT_REPO" config user.name test
git -C "$ROOT_COMMIT_REPO" config user.email test@example.com
printf 'root\n' > "$ROOT_COMMIT_REPO/root.txt"
git -C "$ROOT_COMMIT_REPO" add root.txt
git -C "$ROOT_COMMIT_REPO" commit -m root >/dev/null
root_output="$(cd "$ROOT_COMMIT_REPO" && env EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=0000000000000000000000000000000000000000 "$SCRIPT")"
grep -Fx "scope=full" <<< "$root_output" >/dev/null
grep -Fx "reason=push base unavailable; using full sync" <<< "$root_output" >/dev/null
grep -Fx "base_sha=" <<< "$root_output" >/dev/null

RENAME_REPO="$TEST_TMP/rename"
mkdir -p "$RENAME_REPO/sources/custom/domain"
git -C "$RENAME_REPO" init -q
git -C "$RENAME_REPO" config user.name test
git -C "$RENAME_REPO" config user.email test@example.com
printf 'DOMAIN,old.example\n' > "$RENAME_REPO/sources/custom/domain/old.list"
git -C "$RENAME_REPO" add sources/custom/domain/old.list
git -C "$RENAME_REPO" commit -m base >/dev/null
rename_base="$(git -C "$RENAME_REPO" rev-parse HEAD)"
git -C "$RENAME_REPO" mv sources/custom/domain/old.list sources/custom/domain/new.list
git -C "$RENAME_REPO" commit -m rename >/dev/null
rename_output="$(cd "$RENAME_REPO" && env EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA="$rename_base" "$SCRIPT")"
grep -Fx "scope=full" <<< "$rename_output" >/dev/null
grep -Fx "reason=custom deletions require full sync" <<< "$rename_output" >/dev/null

echo "build scope tests passed"
