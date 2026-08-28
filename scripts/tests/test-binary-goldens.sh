#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
setup_tool_cache

# The golden bytes are produced by the locked compiler versions, which can
# only be fetched for Linux; skip gracefully where the locked assets do not
# apply (local development on other platforms).
if ! ensure_sing_box >/dev/null 2>&1 || ! ensure_mihomo >/dev/null 2>&1; then
  echo "binary golden fixture check skipped: locked compilers are unavailable on this platform"
  exit 0
fi

bash "$ROOT/scripts/commands/update-binary-goldens.sh" --check

echo "binary golden fixture tests passed"
