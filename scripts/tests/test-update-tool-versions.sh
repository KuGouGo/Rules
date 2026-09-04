#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_CWD="$ROOT/scripts/tests"
cd "$SOURCE_CWD"
# shellcheck source=scripts/commands/update-tool-versions.sh
source "$ROOT/scripts/commands/update-tool-versions.sh"
[ "$PWD" = "$SOURCE_CWD" ] || {
  echo "test failed: sourcing the updater changed the working directory" >&2
  exit 1
}

python3 - "$ROOT/Makefile" "$ROOT/scripts/commands/update-tool-versions.sh" "$ROOT/scripts/lib/github-pr.sh" <<'PY'
import re
import sys
from pathlib import Path

makefile_path, updater_path, helpers_path = map(Path, sys.argv[1:])
makefile = makefile_path.read_text(encoding="utf-8")
updater = updater_path.read_text(encoding="utf-8")
helpers = helpers_path.read_text(encoding="utf-8")

target = re.search(
    r"^validate-tool-update:\s*\n(?P<body>(?:\t.*\n)+)",
    makefile,
    re.MULTILINE,
)
if target is None:
    raise SystemExit("test failed: validate-tool-update target is missing")
body = target.group("body")
validate = body.find("$(MAKE) validate")
compile_rules = body.find("$(MAKE) build-custom")
if validate < 0 or compile_rules < 0 or validate > compile_rules:
    raise SystemExit(
        "test failed: tool update validation must test before compiling custom artifacts"
    )
if "REQUIRE_SHELLCHECK=1 make validate-tool-update" not in updater:
    raise SystemExit("test failed: updater does not run the tool compatibility gate")
if 'BRANCH="automation/dependency-updates"' not in updater:
    raise SystemExit("test failed: updater does not use the fixed dependency branch")
if "update-tool-lock.py" not in updater or "update-action-pins.py" not in updater:
    raise SystemExit("test failed: updater does not combine tools and Actions")
for required in (
    "gh workflow run validate.yml",
    "gh run watch",
    "--event workflow_dispatch",
):
    if required not in helpers:
        raise SystemExit(
            f"test failed: updater does not verify its remote commit: {required}"
        )
PY

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
CALLS="$TMP_DIR/calls"

fail() {
  echo "test failed: $*" >&2
  exit 1
}

git() {
  printf 'git %s\n' "$*" >> "$CALLS"
  if [ "$1" = "ls-remote" ]; then
    if [ -n "${REMOTE_SHA:-}" ]; then
      printf '%s\trefs/heads/%s\n' "$REMOTE_SHA" "$BRANCH"
    fi
  fi
}

gh() {
  printf 'gh %s\n' "$*" >> "$CALLS"
  if [ "$1 $2" = "pr list" ]; then
    printf '%s\n' "${OPEN_PR:-}"
    return 0
  fi
  printf '%s\n' "${GH_CREATE_OUTPUT:-created}"
  return "${GH_CREATE_STATUS:-0}"
}

REMOTE_SHA="0123456789abcdef0123456789abcdef01234567"
push_update_branch
grep -Fq "git push -u --force-with-lease=refs/heads/${BRANCH}:${REMOTE_SHA} origin ${BRANCH}" "$CALLS" \
  || fail "existing branch was not updated with an explicit lease"

: > "$CALLS"
REMOTE_SHA=""
push_update_branch
grep -Fq "git push -u origin ${BRANCH}" "$CALLS" \
  || fail "new branch was not pushed normally"

: > "$CALLS"
OPEN_PR=42
ensure_update_pull_request "title" "body" >/dev/null
if grep -Fq "gh pr create" "$CALLS"; then
  fail "a duplicate pull request was attempted"
fi

: > "$CALLS"
OPEN_PR=""
GH_CREATE_STATUS=1
GH_CREATE_OUTPUT="GraphQL: GitHub Actions is not permitted to create or approve pull requests (createPullRequest)"
fallback_output="$(GITHUB_REPOSITORY=owner/repo ensure_update_pull_request "title" "body")"
[[ "$fallback_output" == *"owner/repo/compare/main...${BRANCH}?expand=1"* ]] \
  || fail "disabled Actions PR creation did not provide the manual URL"

GH_CREATE_OUTPUT="GraphQL: unexpected API failure"
if ensure_update_pull_request "title" "body" >/dev/null 2>&1; then
  fail "unexpected pull request failures were ignored"
fi

echo "tool update publication tests passed"
