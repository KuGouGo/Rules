#!/usr/bin/env bash
# Build domain rules
# Uses sing-box from upstream rule-set, parses dlc.dat for surge

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

rm -rf domain
mkdir -p domain/surge domain/sing-box domain/mihomo input

# Download latest dlc.dat
echo "Downloading dlc.dat..."
curl -L "https://github.com/nekolsd/domain-list-community/releases/latest/download/dlc.dat" -o input/dlc.dat

# Setup build dir
BUILD_DIR="$ROOT/.tmp/domain-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Parse dlc.dat for surge files
echo "Parsing dlc.dat..."
cat > "$BUILD_DIR/main.go" <<'GOEOF'
package main
import ("fmt"; "os"; "path/filepath"; "strings"; "google.golang.org/protobuf/proto"; "github.com/v2fly/v2ray-core/v5/app/router/routercommon")
func main(){data,_:=os.ReadFile(os.Args[1]);vList:=routercommon.GeoSiteList{};proto.Unmarshal(data,&vList);outDir:=os.Args[2]
for _,e:=range vList.Entry{c:=strings.ToLower(e.CountryCode);if c==""{continue};f,_:=os.Create(filepath.Join(outDir,c+".txt"));for _,d:=range e.Domain{switch d.Type{case 0:fmt.Fprintln(f,d.Value);case 1:fmt.Fprintln(f,"."+d.Value);case 2:fmt.Fprintln(f,d.Value)}};f.Close()}}
GOEOF
cd "$BUILD_DIR";go mod init dlcpass;go get github.com/v2fly/v2ray-core/v5/app/router/routercommon google.golang.org/protobuf;go run . "$ROOT/input/dlc.dat" "$ROOT/domain/surge"

# Get sing-box .srs from upstream rule-set branch
echo "Getting sing-box .srs from upstream..."
TMP_RS="$ROOT/.tmp/sing-geosite-rs"
rm -rf "$TMP_RS"
git clone --depth=1 --branch rule-set https://github.com/nekolsd/sing-geosite.git "$TMP_RS"
cp -R "$TMP_RS/." "$ROOT/domain/sing-box/"
rm -rf "$TMP_RS"

# Setup mihomo
mkdir -p "$ROOT/.bin"
if ! command -v mihomo >/dev/null 2>&1; then curl -L "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-compatible-v1.19.21.gz" -o "$ROOT/.bin/mihomo.gz";gzip -df "$ROOT/.bin/mihomo.gz";chmod +x "$ROOT/.bin/mihomo";fi
export PATH="$ROOT/.bin:$PATH"

# Generate mihomo .mrs
echo "Generating mihomo .mrs..."
for f in "$ROOT/domain/surge"/*.txt;[ -f "$f" ]||continue;do base=$(basename "$f" .txt);mihomo convert-ruleset domain text "$f" "$ROOT/domain/mihomo/$base.mrs" 2>/dev/null||cp "$f" "$ROOT/domain/mihomo/$base.txt";done

# Custom rules
echo "Custom rules..."
for lf in "$ROOT/sources/domain/custom"/*.list;[ -f "$lf" ]||continue;do base=$(basename "$lf" .list);for t in surge mihomo;do awk -F, 'NF>=2{print $2}' "$lf">>"$ROOT/domain/$t/$base.txt";done;done

echo "Done"