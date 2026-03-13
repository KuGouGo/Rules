#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

check_min_files() {
  local label="$1"
  local glob="$2"
  local min_expected="$3"
  local count

  count=$(find ${glob%/*} -maxdepth 1 -type f -name "${glob##*/}" | wc -l | tr -d ' ')
  echo "$label: $count files (min expected: $min_expected)"

  if [ "$count" -lt "$min_expected" ]; then
    echo "artifact guard failed for $label: expected at least $min_expected files, got $count" >&2
    exit 1
  fi
}

check_min_files "domain/surge" "domain/surge/*.txt" 1000
check_min_files "domain/sing-box" "domain/sing-box/*.srs" 1000
check_min_files "domain/mihomo" "domain/mihomo/*.mrs" 1000

check_min_files "ip/surge" "ip/surge/*.txt" 8
check_min_files "ip/sing-box" "ip/sing-box/*.srs" 8
check_min_files "ip/mihomo" "ip/mihomo/*.mrs" 8

if compgen -G "sources/domain/custom/*.list" >/dev/null; then
  check_min_files "domain/custom-surge" "domain/custom-surge/*.txt" 1
  check_min_files "domain/custom-sing-box" "domain/custom-sing-box/*.srs" 1
  check_min_files "domain/custom-mihomo" "domain/custom-mihomo/*.mrs" 1
fi

echo "artifact guard passed"
