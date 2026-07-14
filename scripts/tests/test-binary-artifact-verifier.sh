#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 -m py_compile "$ROOT/scripts/tools/artifact_verifier.py"
mkdir -p "$TMP/text-repo/config"
cp "$ROOT/config/domain-platform-capabilities.json" "$TMP/text-repo/config/"
printf 'DOMAIN,example.com\n' > "$TMP/good.list"
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/good.list" --type domain --platform surge >/dev/null
printf 'UNKNOWN,example.com\n' > "$TMP/bad-kind.list"
printf 'DOMAIN,example.com,extra\n' > "$TMP/bad-shape.list"
printf "domain_set:\n  - 'example.com'\n" > "$TMP/good.yaml"
printf "unknown_set:\n  - 'example.com'\n" > "$TMP/bad.yaml"
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/good.yaml" --type domain --platform egern >/dev/null
for fixture in bad-kind.list bad-shape.list; do
  if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/$fixture" --type domain --platform surge >/dev/null 2>&1; then
    echo "text verifier accepted $fixture" >&2; exit 1
  fi
done
if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/bad.yaml" --type domain --platform egern >/dev/null 2>&1; then
  echo "Egern verifier accepted unknown YAML field" >&2; exit 1
fi

if ! command -v sing-box >/dev/null 2>&1 || ! command -v mihomo >/dev/null 2>&1; then
  echo "binary verifier real-tool fixture skipped: sing-box and mihomo are not both available"
  exit 0
fi

printf 'DOMAIN,fixture.example\nDOMAIN-SUFFIX,example.org\n' > "$TMP/domain.list"
SINGBOX_RULE_SET_VERSION=4 python3 "$ROOT/scripts/tools/export-domain-rules.py" singbox-json "$TMP/domain.list" "$TMP/domain.json"
sing-box rule-set compile "$TMP/domain.json" --output "$TMP/domain.srs"
printf 'fixture.example\n+.example.org\n' > "$TMP/domain.txt"
mihomo convert-ruleset domain text "$TMP/domain.txt" "$TMP/domain.mrs" >/dev/null

mkdir -p "$TMP/repo/config" "$TMP/repo/.bin" "$TMP/repo/sources/custom/domain"
cp "$ROOT/config/domain-platform-capabilities.json" "$TMP/repo/config/"
cp "$TMP/domain.list" "$TMP/repo/sources/custom/domain/fixture.list"
ln -s "$(command -v sing-box)" "$TMP/repo/.bin/sing-box"
ln -s "$(command -v mihomo)" "$TMP/repo/.bin/mihomo"
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/repo" --path "$TMP/domain.srs" --type domain --platform sing-box | grep -F '"status": "verified"' >/dev/null
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/repo" --path "$TMP/domain.mrs" --type domain --platform mihomo | grep -F '"status": "verified"' >/dev/null

printf CORRUPT > "$TMP/corrupt.srs"
if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/repo" --path "$TMP/corrupt.srs" --type domain --platform sing-box >/dev/null 2>&1; then
  echo "sing-box accepted corrupted fixture" >&2; exit 1
fi
printf 'binary artifact verifier real-tool fixtures passed\n'
