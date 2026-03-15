#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CUSTOM_DIR="$ROOT/sources/custom/domain"

if [ ! -d "$CUSTOM_DIR" ]; then
  echo "no custom rule directory, skip"
  exit 0
fi

shopt -s nullglob
lists=("$CUSTOM_DIR"/*.list)
if [ ${#lists[@]} -eq 0 ]; then
  echo "no custom rule lists, skip"
  exit 0
fi

check_name() {
  local base="$1"
  if [[ ! "$base" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "invalid custom rule filename: $base.list" >&2
    echo "use lowercase letters, digits, and hyphens only" >&2
    return 1
  fi
}

check_file() {
  local file="$1"
  local line_no=0
  local seen_non_comment=0
  local has_error=0

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"

    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    seen_non_comment=1

    if [[ ! "$line" =~ ^(DOMAIN|DOMAIN-SUFFIX),[^[:space:],]+$ ]]; then
      echo "$file:$line_no invalid rule syntax: $line" >&2
      echo "expected DOMAIN,example.com or DOMAIN-SUFFIX,example.com" >&2
      has_error=1
      continue
    fi

    if [[ "$line" =~ ,\. ]]; then
      echo "$file:$line_no domain should not start with dot: $line" >&2
      has_error=1
    fi
  done < "$file"

  if [ "$seen_non_comment" -eq 0 ]; then
    echo "$file has no effective rules" >&2
    has_error=1
  fi

  return "$has_error"
}

for file in "${lists[@]}"; do
  base="$(basename "$file" .list)"
  check_name "$base"
  check_file "$file"
done

echo "custom rule lint passed"
