#!/usr/bin/env bash
# Check out the pinned commit for a cloned upstream source tree.
#
# Usage: apply-upstream-pins.sh <pins-file> <repo-dir> <pin-key>
#
# The clone itself fetches the remote default branch; this script rewrites the
# worktree to the audited commit recorded in the pins file so scheduled builds
# consume reviewed data instead of whatever the upstream pushed most recently.
# Set RULES_UPSTREAM_FLOAT=1 to deliberately build from remote HEAD (used when
# auditing a new upstream revision or diagnosing pin mismatches).
set -euo pipefail

PINS_FILE="$1"
REPO_DIR="$2"
PIN_KEY="$3"

if [ ! -f "$PINS_FILE" ]; then
  echo "upstream pins file is missing: $PINS_FILE" >&2
  exit 1
fi

pinned_commit="$(python3 - "$PINS_FILE" "$PIN_KEY" <<'PY'
import json
import sys

path, key = sys.argv[1:]
data = json.loads(open(path, encoding="utf-8").read())
pin = data.get("pins", {}).get(key)
if not pin:
    raise SystemExit()
commit = pin.get("commit", "")
if len(commit) != 40 or any(char not in "0123456789abcdef" for char in commit):
    raise SystemExit(f"invalid pinned commit for {key}: {commit!r}")
print(commit)
PY
)"

if [ -z "$pinned_commit" ]; then
  echo "no upstream pin for $PIN_KEY in $PINS_FILE; building from remote HEAD"
  exit 0
fi

if [ "${RULES_UPSTREAM_FLOAT:-0}" = "1" ]; then
  echo "RULES_UPSTREAM_FLOAT=1: floating to remote HEAD for $PIN_KEY instead of pin $pinned_commit"
  exit 0
fi

current_commit="$(git -C "$REPO_DIR" rev-parse HEAD)"
if [ "$current_commit" = "$pinned_commit" ]; then
  echo "$PIN_KEY already at pinned commit $pinned_commit"
  exit 0
fi

echo "$PIN_KEY pinned to $pinned_commit (clone HEAD was $current_commit); fetching pinned commit"
git -C "$REPO_DIR" fetch --quiet --depth=1 origin "$pinned_commit"
git -C "$REPO_DIR" checkout --quiet --detach "$pinned_commit"
test "$(git -C "$REPO_DIR" rev-parse HEAD)" = "$pinned_commit"
