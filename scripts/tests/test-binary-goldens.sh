#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
setup_tool_cache

if ! ensure_sing_box >/dev/null 2>&1 || ! ensure_mihomo >/dev/null 2>&1; then
  echo "binary golden fixture check skipped: locked compilers are unavailable on this platform"
  exit 0
fi

bash "$ROOT/scripts/commands/update-binary-goldens.sh" --check

echo "binary golden fixture tests passed"
