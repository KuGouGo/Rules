#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

make -s -C "$ROOT" check-runtime BASH_MIN_MAJOR=1

if make -s -C "$ROOT" check-runtime BASH_MIN_MAJOR=999 \
  >"$TMP_DIR/unsupported.stdout" 2>"$TMP_DIR/unsupported.stderr"; then
  echo "test failed: unsupported Bash runtime was accepted" >&2
  exit 1
fi
grep -F 'Bash 999+ is required' "$TMP_DIR/unsupported.stderr" >/dev/null

echo "runtime requirement tests passed"
