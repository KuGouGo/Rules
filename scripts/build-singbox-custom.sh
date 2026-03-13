#!/usr/bin/env bash
# Build custom sing-box .srs rule sets from plain domain lists.
# Uses sing-box rule-set compile to convert JSON source to binary .srs format.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLAIN_INPUT_DIR="$ROOT/.tmp/domain-custom-plain"
mkdir -p "$ROOT/domain/sing-box" "$ROOT/.bin"

# Download sing-box if not present
if ! command -v sing-box >/dev/null 2>&1; then
  if [ ! -x "$ROOT/.bin/sing-box" ]; then
    SINGBOX_VERSION="1.13.2"
    curl -Lo "$ROOT/.bin/sing-box.tar.gz" \
      "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz"
    tar -xzf "$ROOT/.bin/sing-box.tar.gz" -C "$ROOT/.bin" --strip-components=1
    chmod +x "$ROOT/.bin/sing-box"
    rm -f "$ROOT/.bin/sing-box.tar.gz"
  fi
  export PATH="$ROOT/.bin:$PATH"
fi

for src in "$PLAIN_INPUT_DIR"/*.txt; do
  [ -f "$src" ] || continue
  base="$(basename "$src" .txt)"
  
  # Build JSON source file
  json_file="$PLAIN_INPUT_DIR/$base.json"
  
  # Read domains and format as JSON array for domain_suffix
  domains=$(awk 'NF {printf "\"%s\",", $0}' "$src" | sed 's/,$//')
  
  cat > "$json_file" <<EOF
{
  "version": 3,
  "rules": [
    {
      "domain_suffix": [$domains]
    }
  ]
}
EOF
  
  # Compile to .srs
  sing-box rule-set compile "$json_file" --output "$ROOT/domain/sing-box/$base.srs"
done

echo "custom sing-box rule sets built"