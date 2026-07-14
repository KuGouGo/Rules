#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

: "${ARTIFACT_GENERATION_ID:=${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}}"
: "${ARTIFACT_BUILD_ID:=$ARTIFACT_GENERATION_ID}"
: "${ARTIFACT_BUILD_SCOPE:=full}"

args=(generate --generation-id "$ARTIFACT_GENERATION_ID" --build-id "$ARTIFACT_BUILD_ID" --build-scope "$ARTIFACT_BUILD_SCOPE")
if [ -n "${ARTIFACT_SOURCE_SHA:-}" ]; then
  args+=(--source-sha "$ARTIFACT_SOURCE_SHA")
fi
python3 "$ROOT/scripts/tools/artifact_manifest.py" --root "$ROOT" "${args[@]}"
