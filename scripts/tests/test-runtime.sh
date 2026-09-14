#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
CHECK_RUNTIME="$ROOT/scripts/commands/check-runtime.sh"

make -s -C "$ROOT" check-runtime

if RULES_RUNTIME_TEST_BASH_MIN_MAJOR=999 "$CHECK_RUNTIME" \
  >"$TMP_DIR/unsupported.stdout" 2>"$TMP_DIR/unsupported.stderr"; then
  echo "test failed: unsupported Bash runtime was accepted" >&2
  exit 1
fi
grep -F 'Bash 999+ is required' "$TMP_DIR/unsupported.stderr" >/dev/null

if RULES_RUNTIME_TEST_PYTHON_MIN_MAJOR=999 "$CHECK_RUNTIME" \
  >"$TMP_DIR/unsupported-python.stdout" 2>"$TMP_DIR/unsupported-python.stderr"; then
  echo "test failed: unsupported Python runtime was accepted" >&2
  exit 1
fi
grep -F 'Python 999.11+ is required' "$TMP_DIR/unsupported-python.stderr" >/dev/null

mkdir -p "$TMP_DIR/no-python"
if PATH="$TMP_DIR/no-python" "$(command -v bash)" "$CHECK_RUNTIME" \
  >"$TMP_DIR/missing-python.stdout" 2>"$TMP_DIR/missing-python.stderr"; then
  echo "test failed: missing Python runtime was accepted" >&2
  exit 1
fi
grep -F 'Python 3.11+ is required (python3 not found in PATH)' "$TMP_DIR/missing-python.stderr" >/dev/null

ln -s "$(command -v bash)" "$TMP_DIR/no-python/bash"
ln -s "$(command -v dirname)" "$TMP_DIR/no-python/dirname"
for entrypoint in \
  build-custom-rules.sh \
  publish-branches.sh \
  sync-upstream.sh; do
  if PATH="$TMP_DIR/no-python" "$ROOT/scripts/commands/$entrypoint" \
    >"$TMP_DIR/$entrypoint.stdout" 2>"$TMP_DIR/$entrypoint.stderr"; then
    echo "test failed: $entrypoint accepted a missing Python runtime" >&2
    exit 1
  fi
  grep -F 'Python 3.11+ is required (python3 not found in PATH)' \
    "$TMP_DIR/$entrypoint.stderr" >/dev/null
done

action_python="$(sed -n "s/^[[:space:]]*python-version: '\([0-9][0-9]*\.[0-9][0-9]*\)'$/\1/p" "$ROOT/.github/actions/setup-tools/action.yml")"
runtime_major="$(sed -n 's/^required_python_major=\([0-9]*\)$/\1/p' "$CHECK_RUNTIME")"
runtime_minor="$(sed -n 's/^required_python_minor=\([0-9]*\)$/\1/p' "$CHECK_RUNTIME")"
if [ -z "$action_python" ] || [ -z "$runtime_major" ] || [ -z "$runtime_minor" ]; then
  echo "test failed: could not parse python-version from setup-tools or check-runtime" >&2
  exit 1
fi
action_major="${action_python%%.*}"
action_minor="${action_python#*.}"
if [ "$action_major" -ne "$runtime_major" ] || [ "$action_minor" -lt "$runtime_minor" ]; then
  echo "test failed: setup-tools python-version $action_python is below the check-runtime floor $runtime_major.$runtime_minor" >&2
  exit 1
fi

echo "runtime requirement tests passed"
