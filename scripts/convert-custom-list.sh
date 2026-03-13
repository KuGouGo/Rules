#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p domain/surge

convert_list_to_domain_set() {
  local input="$1"
  local output="$2"
  
  if [ ! -f "$input" ]; then
    return
  fi
  
  awk -F, '
    NF >= 3 {
      type = $1
      domain = $2
      if (type == "DOMAIN") {
        print domain
      } else if (type == "DOMAIN-SUFFIX") {
        print "." domain
      }
    }
  ' "$input" > "$output"
}

for f in sources/domain/custom/*.list; do
  [ -f "$f" ] || continue
  base="$(basename "$f" .list)"
  convert_list_to_domain_set "$f" "$ROOT/domain/surge/$base.txt"
done

echo "custom list files converted to DOMAIN-SET format"