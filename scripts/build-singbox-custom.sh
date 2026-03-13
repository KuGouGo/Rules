#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_BUILD_DIR="$ROOT/.tmp/custom-srs-builder"
PLAIN_INPUT_DIR="$ROOT/.tmp/domain-custom-plain"
mkdir -p "$TMP_BUILD_DIR" "$ROOT/domain/sing-box"
rm -f "$TMP_BUILD_DIR"/main.go "$TMP_BUILD_DIR"/go.mod "$TMP_BUILD_DIR"/go.sum

cat > "$TMP_BUILD_DIR/main.go" <<'EOF'
package main

import (
  "os"
  "strings"

  "github.com/sagernet/sing-box/common/srs"
  C "github.com/sagernet/sing-box/constant"
  "github.com/sagernet/sing-box/option"
)

func main() {
  if len(os.Args) != 3 {
    panic("usage: in.txt out.srs")
  }
  inPath, outPath := os.Args[1], os.Args[2]
  data, err := os.ReadFile(inPath)
  if err != nil {
    panic(err)
  }
  lines := strings.Split(string(data), "\n")
  var domains []string
  var suffixes []string
  for _, line := range lines {
    line = strings.TrimSpace(line)
    if line == "" {
      continue
    }
    if strings.HasPrefix(line, ".") {
      suffixes = append(suffixes, strings.TrimPrefix(line, "."))
    } else {
      domains = append(domains, line)
    }
  }
  rule := option.DefaultHeadlessRule{Domain: domains, DomainSuffix: suffixes}
  plain := option.PlainRuleSet{Rules: []option.HeadlessRule{{Type: C.RuleTypeDefault, DefaultOptions: rule}}}
  f, err := os.Create(outPath)
  if err != nil {
    panic(err)
  }
  defer f.Close()
  if err := srs.Write(f, plain, C.RuleSetVersionCurrent); err != nil {
    panic(err)
  }
}
EOF

cat > "$TMP_BUILD_DIR/go.mod" <<'EOF'
module customsrs

go 1.24

require github.com/sagernet/sing-box v1.12.22
EOF

for src in "$PLAIN_INPUT_DIR"/*.txt; do
  [ -f "$src" ] || continue
  base="$(basename "$src" .txt)"
  (cd "$TMP_BUILD_DIR" && go mod tidy && go run . "$src" "$ROOT/domain/sing-box/$base.srs")
done

echo "custom sing-box rule sets built"
