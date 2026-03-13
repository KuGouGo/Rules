#!/usr/bin/env bash
# Build domain rules from v2fly/domain-list-community dlc.dat
# Outputs: surge DOMAIN-SET, sing-box .srs, mihomo .mrs

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf domain
mkdir -p domain/surge domain/sing-box domain/mihomo input

# Download latest dlc.dat from nekolsd/domain-list-community
echo "Downloading dlc.dat..."
curl -L "https://github.com/nekolsd/domain-list-community/releases/latest/download/dlc.dat" -o input/dlc.dat

# Setup build directory
BUILD_DIR="$ROOT/.tmp/domain-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create Go program to parse dlc.dat and generate outputs
cat > "$BUILD_DIR/main.go" <<'GOEOF'
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/sagernet/sing-box/common/geosite"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
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
	singboxDir := filepath.Join(outDir, "sing-box")

	for _, entry := range vList.Entry {
		code := strings.ToLower(entry.CountryCode)
		if code == "" {
			continue
		}

		// Collect domains
		var domains, suffixes []string
		for _, d := range entry.Domain {
			switch d.Type {
			case routercommon.Domain_Plain:
				domains = append(domains, d.Value)
			case routercommon.Domain_Domain:
				suffixes = append(suffixes, d.Value)
			case routercommon.Domain_Full:
				domains = append(domains, d.Value)
			}
		}

		// Write Surge DOMAIN-SET
		surgeFile, err := os.Create(filepath.Join(surgeDir, code+".txt"))
		if err != nil {
			panic(err)
		}
		for _, d := range domains {
			fmt.Fprintln(surgeFile, d)
		}
		for _, s := range suffixes {
			fmt.Fprintln(surgeFile, "."+s)
		}
		surgeFile.Close()

		// Write sing-box JSON source
		jsonFile, err := os.Create(filepath.Join(singboxDir, code+".json"))
		if err != nil {
			panic(err)
		}
		fmt.Fprintf(jsonFile, `{"version":3,"rules":[{"domain":`)
		writeJSONArray(jsonFile, domains)
		fmt.Fprintf(jsonFile, `,"domain_suffix":`)
		writeJSONArray(jsonFile, suffixes)
		fmt.Fprintln(jsonFile, `}]}`)
		jsonFile.Close()
	}
}

func writeJSONArray(f *os.File, items []string) {
	f.WriteString("[")
	for i, item := range items {
		if i > 0 {
			f.WriteString(",")
		}
		fmt.Fprintf(f, `"%s"`, item)
	}
	f.WriteString("]")
}
GOEOF

cat > "$BUILD_DIR/go.mod" <<'EOF'
module domainbuild

go 1.24

require (
	github.com/sagernet/sing-box v1.12.22
	github.com/v2fly/v2ray-core/v5 v5.22.0
	google.golang.org/protobuf v1.36.5
)
EOF

# Build and run
echo "Building domain rules from dlc.dat..."
cd "$BUILD_DIR"
go mod tidy
go run . "$ROOT/input/dlc.dat" "$ROOT/domain"

# Compile sing-box .srs
echo "Compiling sing-box .srs files..."
mkdir -p "$ROOT/.bin"
if ! command -v sing-box >/dev/null 2>&1; then
	curl -Lo "$ROOT/.bin/sing-box.tar.gz" \
		"https://github.com/SagerNet/sing-box/releases/download/v1.13.2/sing-box-1.13.2-linux-amd64.tar.gz"
	tar -xzf "$ROOT/.bin/sing-box.tar.gz" -C "$ROOT/.bin" --strip-components=1
	chmod +x "$ROOT/.bin/sing-box"
	rm -f "$ROOT/.bin/sing-box.tar.gz"
	export PATH="$ROOT/.bin:$PATH"
fi

for jsonFile in "$ROOT/domain/sing-box"/*.json; do
	[ -f "$jsonFile" ] || continue
	base=$(basename "$jsonFile" .json)
	sing-box rule-set compile "$jsonFile" --output "$ROOT/domain/sing-box/$base.srs"
	rm "$jsonFile"
done

# Generate mihomo .mrs from surge files
echo "Generating mihomo .mrs files..."
for txtFile in "$ROOT/domain/surge"/*.txt; do
	[ -f "$txtFile" ] || continue
	base=$(basename "$txtFile" .txt)
	"$ROOT/.bin/mihomo" convert-ruleset domain text "$txtFile" "$ROOT/domain/mihomo/$base.mrs" 2>/dev/null || \
		cp "$txtFile" "$ROOT/domain/mihomo/$base.txt"
done

# Append custom rules
echo "Appending custom rules..."
chmod +x "$ROOT/scripts/convert-custom-list.sh"
"$ROOT/scripts/convert-custom-list.sh" "$BUILD_DIR/custom-plain"

# Copy custom plain to mihomo input and build
for txtFile in "$BUILD_DIR/custom-plain"/*.txt; do
	[ -f "$txtFile" ] || continue
	base=$(basename "$txtFile" .txt)
	# Add to sing-box
	jsonFile="$ROOT/domain/sing-box/$base.json"
	domains=$(awk 'NF {printf "\"%s\",", $0}' "$txtFile" | sed 's/,$//')
	cat > "$jsonFile" <<EOF
{"version":3,"rules":[{"domain_suffix":[$domains]}]}
EOF
	sing-box rule-set compile "$jsonFile" --output "$ROOT/domain/sing-box/$base.srs"
	rm "$jsonFile"
	# Add to mihomo
	"$ROOT/.bin/mihomo" convert-ruleset domain text "$txtFile" "$ROOT/domain/mihomo/$base.mrs" 2>/dev/null || true
done

echo "domain build done"