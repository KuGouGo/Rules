#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/commands/select-build-scope.sh"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
SCOPE_REPO="$TEST_TMP/scope-repo"
BASELINE_INPUT="$TEST_TMP/publication-baseline.json"
BASELINE_AT_MIDDLE_INPUT="$TEST_TMP/publication-baseline-at-middle.json"
INCONSISTENT_BASELINE_INPUT="$TEST_TMP/publication-baseline-inconsistent.json"
BASELINE_OUTPUT="$TEST_TMP/selected-publication-baseline.json"

write_baseline() {
  local path="$1"
  local source="$2"
  python3 - "$path" "$source" <<'PY'
import json
import sys
from pathlib import Path

path, source = sys.argv[1:]
branches = ("surge", "quanx", "egern", "sing-box", "mihomo")
payload = {
    "status": "consistent",
    "generation_id": "10-1",
    "source_commit": source,
    "branches": {
        branch: {
            "commit": f"{index + 1:040x}",
            "generation_id": "10-1",
            "source_commit": source,
        }
        for index, branch in enumerate(branches)
    },
}
Path(path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

mkdir -p "$SCOPE_REPO"
git -C "$SCOPE_REPO" init -q
git -C "$SCOPE_REPO" config user.name test
git -C "$SCOPE_REPO" config user.email test@example.com
printf 'base\n' > "$SCOPE_REPO/README.md"
git -C "$SCOPE_REPO" add README.md
git -C "$SCOPE_REPO" commit -m baseline >/dev/null
PUBLISHED_SOURCE="$(git -C "$SCOPE_REPO" rev-parse HEAD)"
write_baseline "$BASELINE_INPUT" "$PUBLISHED_SOURCE"
mkdir -p "$SCOPE_REPO/scripts/commands"
printf '# change requiring full\n' > "$SCOPE_REPO/scripts/commands/example.sh"
git -C "$SCOPE_REPO" add scripts/commands/example.sh
git -C "$SCOPE_REPO" commit -m full-change >/dev/null
MIDDLE_SOURCE="$(git -C "$SCOPE_REPO" rev-parse HEAD)"
write_baseline "$BASELINE_AT_MIDDLE_INPUT" "$MIDDLE_SOURCE"
mkdir -p "$SCOPE_REPO/sources/custom/domain"
printf 'DOMAIN,custom.example\n' > "$SCOPE_REPO/sources/custom/domain/custom.list"
git -C "$SCOPE_REPO" add sources/custom/domain/custom.list
git -C "$SCOPE_REPO" commit -m custom-change >/dev/null
python3 - "$BASELINE_AT_MIDDLE_INPUT" "$INCONSISTENT_BASELINE_INPUT" <<'PY'
import json, sys
payload=json.load(open(sys.argv[1], encoding='utf-8'))
payload['status']='inconsistent'; payload['generation_id']=None; payload['source_commit']=None
payload['branches']['surge']['generation_id']='9-1'
json.dump(payload, open(sys.argv[2], 'w', encoding='utf-8'), indent=2, sort_keys=True)
PY

assert_scope() {
  local expected_scope="$1"
  local expected_reason="$2"
  shift 2

  local output
  output="$(
    cd "$SCOPE_REPO"
    env \
      ARTIFACT_BASELINE_FILE="$BASELINE_OUTPUT" \
      RULES_PUBLICATION_BASELINE_INPUT="$BASELINE_INPUT" \
      "$@" \
      "$SCRIPT"
  )"
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

assert_scope full "push includes changes outside custom sources" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA="$MIDDLE_SOURCE"

assert_scope custom "push only updates custom sources" \
  RULES_PUBLICATION_BASELINE_INPUT="$BASELINE_AT_MIDDLE_INPUT" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA="$MIDDLE_SOURCE"

assert_scope full "publication cohort inconsistent; using full sync" \
  RULES_PUBLICATION_BASELINE_INPUT="$INCONSISTENT_BASELINE_INPUT" \
  EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA="$MIDDLE_SOURCE" \
  CHANGED_FILES=$'sources/custom/domain/custom.list'

set +e
manual_cumulative_output="$(
  cd "$SCOPE_REPO"
  env ARTIFACT_BASELINE_FILE="$BASELINE_OUTPUT" \
    RULES_PUBLICATION_BASELINE_INPUT="$BASELINE_INPUT" \
    EVENT_NAME=workflow_dispatch INPUT_SCOPE=custom CURRENT_SHA=HEAD \
    "$SCRIPT" 2>&1
)"
manual_cumulative_status=$?
set -e
[ "$manual_cumulative_status" -ne 0 ]
grep -F "manual custom scope refused: delta contains non-custom paths" <<< "$manual_cumulative_output" >/dev/null

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

ROOT_COMMIT_REPO="$TEST_TMP/root-commit"
mkdir -p "$ROOT_COMMIT_REPO"
git -C "$ROOT_COMMIT_REPO" init -q
git -C "$ROOT_COMMIT_REPO" config user.name test
git -C "$ROOT_COMMIT_REPO" config user.email test@example.com
printf 'root\n' > "$ROOT_COMMIT_REPO/root.txt"
git -C "$ROOT_COMMIT_REPO" add root.txt
git -C "$ROOT_COMMIT_REPO" commit -m root >/dev/null
pr_no_remote_output="$(cd "$ROOT_COMMIT_REPO" && env EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA=base CHANGED_FILES=README.md "$SCRIPT")"
grep -Fx "scope=none" <<< "$pr_no_remote_output" >/dev/null
grep -Fx "reason=pull_request has no build-relevant changes" <<< "$pr_no_remote_output" >/dev/null
set +e
root_output="$(cd "$ROOT_COMMIT_REPO" && env EVENT_NAME=push CURRENT_SHA=HEAD BEFORE_SHA=0000000000000000000000000000000000000000 "$SCRIPT" 2>&1)"
root_status=$?
set -e
[ "$root_status" -ne 0 ]
grep -F "required remote publication branch origin/surge is unavailable" <<< "$root_output" >/dev/null

RENAME_REPO="$TEST_TMP/rename"
mkdir -p "$RENAME_REPO/sources/custom/domain"
git -C "$RENAME_REPO" init -q
git -C "$RENAME_REPO" config user.name test
git -C "$RENAME_REPO" config user.email test@example.com
printf 'DOMAIN,old.example\n' > "$RENAME_REPO/sources/custom/domain/old.list"
git -C "$RENAME_REPO" add sources/custom/domain/old.list
git -C "$RENAME_REPO" commit -m base >/dev/null
rename_base="$(git -C "$RENAME_REPO" rev-parse HEAD)"
RENAME_BASELINE_INPUT="$TEST_TMP/rename-publication-baseline.json"
write_baseline "$RENAME_BASELINE_INPUT" "$rename_base"
git -C "$RENAME_REPO" mv sources/custom/domain/old.list sources/custom/domain/new.list
git -C "$RENAME_REPO" commit -m rename >/dev/null
rename_output="$(cd "$RENAME_REPO" && env ARTIFACT_BASELINE_FILE="$BASELINE_OUTPUT" RULES_PUBLICATION_BASELINE_INPUT="$RENAME_BASELINE_INPUT" EVENT_NAME=pull_request CURRENT_SHA=HEAD BEFORE_SHA="$rename_base" "$SCRIPT")"
grep -Fx "scope=full" <<< "$rename_output" >/dev/null
grep -Fx "reason=custom deletions require full sync" <<< "$rename_output" >/dev/null

echo "build scope tests passed"
