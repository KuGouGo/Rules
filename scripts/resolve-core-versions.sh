#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/lib/common.sh"

sing_box_version="$(resolve_sing_box_version)"
mihomo_version="$(resolve_mihomo_version)"

[ -n "$sing_box_version" ] || {
  echo "failed to resolve sing-box version" >&2
  exit 1
}

[ -n "$mihomo_version" ] || {
  echo "failed to resolve mihomo version" >&2
  exit 1
}

echo "sing-box latest: ${sing_box_version}"
echo "mihomo latest: ${mihomo_version}"

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
