#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# For now, custom sing-box rule sets are derived from custom .list files by
# generating sing-box source inputs in .tmp/domain-custom-plain and then using
# simple JSON -> SRS generation via a tiny Go helper from upstream is skipped.
# As a practical compatibility step, we expose the plain files in tmp for the
# same source of truth and keep sing-box generation delegated to the main
# domain build pipeline when custom upstream integration is added.

echo "custom sing-box placeholder: custom inputs prepared in .tmp/domain-custom-plain"
