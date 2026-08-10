#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/scripts/commands/check-runtime.sh"

python3 "$ROOT/scripts/tools/artifact_verifier.py" \
  --root "$ROOT" \
  --verify-canonical-inventory "${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
args=(verify)
if [ -n "${ARTIFACT_SOURCE_SHA:-}" ]; then
  args+=(--source-sha "$ARTIFACT_SOURCE_SHA")
fi
python3 "$ROOT/scripts/tools/artifact_manifest.py" --root "$ROOT" "${args[@]}"
