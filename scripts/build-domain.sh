#!/usr/bin/env bash
# Build domain rules from nekolsd/domain-list-community dlc.dat
# Uses sing-box geosite compiler

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf domain
mkdir -p domain/surge domain/sing-box domain/mihomo input

# Download latest dlc.dat
echo "Downloading dlc.dat..."
curl -L "https://github.com/nekolsd/domain-list-community/releases/latest/download/dlc.dat" -o input/dlc.dat

# Setup sing-box
mkdir -p "$ROOT/.bin"
if ! command -v sing-box >/dev/null 2>&1; then
  if [ ! -x "$ROOT/.bin/sing-box" ]; then
    SINGBOX_VERSION="1.13.2"
    echo "Downloading sing-box $SINGBOX_VERSION..."
    curl -Lo "$ROOT/.bin/sing-box.tar.gz" \
      "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz"
    tar -xzf "$ROOT/.bin/sing-box.tar.gz" -C "$ROOT/.bin" --strip-components=1
    chmod +x "$ROOT/.bin/sing-box"
    rm -f "$ROOT/.bin/sing-box.tar.gz"
  fi
  export PATH="$ROOT/.bin:$PATH"
fi

# Setup mihomo
if ! command -v mihomo >/dev/null 2>&1; then
  if [ ! -x "$ROOT/.bin/mihomo" ]; then
    echo "Downloading mihomo..."
    curl -L "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-compatible-v1.19.21.gz" -o "$ROOT/.bin/mihomo.gz"
    gzip -df "$ROOT/.bin/mihomo.gz"
    chmod +x "$ROOT/.bin/mihomo"
  fi
  export PATH="$ROOT/.bin:$PATH"
fi

# Use sing-box to parse dlc.dat and generate rule-set
echo "Parsing dlc.dat with sing-box..."

# Build temp Go program to extract categories and generate plain text
BUILD_DIR="$ROOT/.tmp/domain-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/main.go" <<'GOEOF'
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"google.golang.org/protobuf/proto"
	"github.com/v2fly/v2ray-core/v5/app/router/routercommon"
)

func main() {
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}

	vList := routercommon.GeoSiteList{}
	if err := proto.Unmarshal(data, &vList); err != nil {
		panic(err)
	}

	outDir := os.Args[2]
	surgeDir := filepath.Join(outDir, "surge")

	for _, entry := range vList.Entry {
		code := strings.ToLower(entry.CountryCode)
		if code == "" {
			continue
		}

		surgeFile, err := os.Create(filepath.Join(surgeDir, code+".txt"))
		if err != nil {
			panic(err)
		}

		for _, d := range entry.Domain {
			switch d.Type {
			case routercommon.Domain_Full:
				fmt.Fprintln(surgeFile, d.Value)
			case routercommon.Domain_Domain:
				fmt.Fprintln(surgeFile, "."+d.Value)
			case routercommon.Domain_Plain:
				fmt.Fprintln(surgeFile, d.Value)
			}
		}
		surgeFile.Close()
	}
}
GOEOF

cat > "$BUILD_DIR/go.mod" <<'EOF'
module dlcpass

go 1.24

require (
	github.com/v2fly/v2ray-core/v5 v5.22.0
	google.golang.org/protobuf v1.36.5
)
EOF

cd "$BUILD_DIR"
go mod tidy
go run . "$ROOT/input/dlc.dat" "$ROOT/domain"
cd "$ROOT"

# Generate sing-box .srs from surge files
echo "Generating sing-box .srs..."
for txtFile in "$ROOT/domain/surge"/*.txt; do
  [ -f "$txtFile" ] || continue
  base=$(basename "$txtFile" .txt)
  
  # Build JSON source
  jsonFile="$ROOT/.tmp/$base.json"
  domains=$(awk 'NF {gsub(/"/, "\\\""); printf "\"%s\",", $0}' "$txtFile" | sed 's/,$//')
  cat > "$jsonFile" <<EOF
{"version":3,"rules":[{"domain_suffix":[$domains]}]}
EOF
  
  sing-box rule-set compile "$jsonFile" --output "$ROOT/domain/sing-box/$base.srs"
  rm -f "$jsonFile"
done

# Generate mihomo .mrs from surge files
echo "Generating mihomo .mrs..."
for txtFile in "$ROOT/domain/surge"/*.txt; do
  [ -f "$txtFile" ] || continue
  base=$(basename "$txtFile" .txt)
  mihomo convert-ruleset domain text "$txtFile" "$ROOT/domain/mihomo/$base.mrs" 2>/dev/null || \
    cp "$txtFile" "$ROOT/domain/mihomo/$base.txt"
done

# Append custom rules
echo "Appending custom rules..."
if [ -d "$ROOT/sources/domain/custom" ]; then
  CUSTOM_PLAIN="$ROOT/.tmp/custom-plain"
  mkdir -p "$CUSTOM_PLAIN"
  
  for listFile in "$ROOT/sources/domain/custom"/*.list; do
    [ -f "$listFile" ] || continue
    base=$(basename "$listFile" .list)
    
    # Extract domains
    surgeOut="$ROOT/domain/surge/$base.txt"
    plainOut="$CUSTOM_PLAIN/$base.txt"
    
    awk -F, 'NF >= 2 {
      type = $1
      domain = $2
      if (type == "DOMAIN") {
        print domain >> surge
        print domain >> plain
      } else if (type == "DOMAIN-SUFFIX") {
        print "." domain >> surge
        print domain >> plain
      }
    }' surge="$surgeOut" plain="$plainOut" "$listFile"
    
    # Generate .srs for custom
    if [ -f "$plainOut" ]; then
      jsonFile="$ROOT/.tmp/$base.json"
      domains=$(awk 'NF {gsub(/"/, "\\\""); printf "\"%s\",", $0}' "$plainOut" | sed 's/,$//')
      cat > "$jsonFile" <<EOF
{"version":3,"rules":[{"domain_suffix":[$domains]}]}
EOF
      sing-box rule-set compile "$jsonFile" --output "$ROOT/domain/sing-box/$base.srs"
      
      # Generate .mrs
      mihomo convert-ruleset domain text "$plainOut" "$ROOT/domain/mihomo/$base.mrs" 2>/dev/null || true
    fi
  done
fi

echo "domain build done"