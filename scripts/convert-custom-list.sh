#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLAIN_OUT_DIR="${1:-$ROOT/.tmp/domain-custom-plain}"
mkdir -p domain/surge "$PLAIN_OUT_DIR"

convert_list() {
  local input="$1"
  local surge_output="$2"
  local plain_output="$3"

  [ -f "$input" ] || return 0

  awk -F, '
    NF >= 3 {
      type = $1
      domain = $2
      if (type == "DOMAIN") {
        print domain > plain
        print domain > surge
      } else if (type == "DOMAIN-SUFFIX") {
        print "." domain > surge
        print domain > plain
      }
    }
  ' surge="$surge_output" plain="$plain_output" "$input"
}

for f in sources/domain/custom/*.list; do
  [ -f "$f" ] || continue
  base="$(basename "$f" .list)"
  convert_list "$f" "$ROOT/domain/surge/$base.txt" "$PLAIN_OUT_DIR/$base.txt"
done

echo "custom list files converted to Surge DOMAIN-SET and plain domain lists"
