#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
setup_tool_cache

# tool_lock_value already fails loudly on a missing/empty locked value.
sing_box_version="$(resolve_sing_box_version)"
mihomo_version="$(resolve_mihomo_version)"

echo "sing-box locked: ${sing_box_version}"
echo "mihomo locked: ${mihomo_version}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "sing_box_version=${sing_box_version}"
    echo "mihomo_version=${mihomo_version}"
  } >> "$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "SING_BOX_VERSION=${sing_box_version}"
    echo "MIHOMO_VERSION=${mihomo_version}"
  } >> "$GITHUB_ENV"
fi
