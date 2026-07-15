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
printf 'HOST-SUFFIX,example.com,quanx\n' > "$TMP/quanx.list"
printf 'HOST-SUFFIX,example.com,reject\n' > "$TMP/quanx-bad.list"
printf 'IP-CIDR,192.0.2.0/24,quanx-ip\n' > "$TMP/quanx-ip.list"
printf 'IP-CIDR,192.0.2.0/24,reject\n' > "$TMP/quanx-ip-bad.list"
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/good.yaml" --type domain --platform egern >/dev/null
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/quanx.list" --type domain --platform quanx >/dev/null
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/quanx-ip.list" --type ip --platform quanx >/dev/null
for fixture in bad-kind.list bad-shape.list; do
  if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/$fixture" --type domain --platform surge >/dev/null 2>&1; then
    echo "text verifier accepted $fixture" >&2; exit 1
  fi
done
if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" --root "$TMP/text-repo" --path "$TMP/bad.yaml" --type domain --platform egern >/dev/null 2>&1; then
  echo "Egern verifier accepted unknown YAML field" >&2; exit 1
fi
for fixture in quanx-bad.list quanx-ip-bad.list; do
  artifact_type=domain
  [[ "$fixture" == quanx-ip-* ]] && artifact_type=ip
  if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" \
    --root "$TMP/text-repo" --path "$TMP/$fixture" --type "$artifact_type" --platform quanx >/dev/null 2>&1; then
    echo "Quantumult X verifier accepted wrong policy in $fixture" >&2
    exit 1
  fi
done

PYTHONPATH="$ROOT/scripts/tools" python3 - <<'PY'
from collections import Counter
from artifact_verifier import semantic_digest, singbox_counts, singbox_entries

domain = {"rules": [{"domain": "one.example", "domain_suffix": ["a.example", "b.example"], "domain_keyword": "emby"}]}
assert singbox_counts(domain, "domain") == Counter({"DOMAIN-SUFFIX": 2, "DOMAIN": 1, "DOMAIN-KEYWORD": 1})
assert singbox_entries(domain, "domain") == Counter({
    ("DOMAIN", "one.example"): 1,
    ("DOMAIN-SUFFIX", "a.example"): 1,
    ("DOMAIN-SUFFIX", "b.example"): 1,
    ("DOMAIN-KEYWORD", "emby"): 1,
})
ip = {"rules": [{"ip_cidr": "192.0.2.0/24"}, {"ip_cidr": ["2001:db8::/32"]}]}
assert singbox_counts(ip, "ip") == Counter({"IP-CIDR": 1, "IP-CIDR6": 1})
assert semantic_digest(Counter({("DOMAIN", "one.example"): 1})) != semantic_digest(
    Counter({("DOMAIN", "two.example"): 1})
)
for invalid in (
    {"rules": [{"domain": ["one.example"], "port": [443]}]},
    {"rules": [{"ip_cidr": ["192.0.2.0/24"]}]},
    {"rules": [{}]},
):
    try:
        singbox_entries(invalid, "domain")
    except ValueError:
        pass
    else:
        raise AssertionError(f"sing-box verifier accepted unsupported rule object: {invalid!r}")
PY

mkdir -p \
  "$TMP/exact-repo/config" \
  "$TMP/exact-repo/.bin" \
  "$TMP/exact-repo/.output/domain/sing-box" \
  "$TMP/exact-repo/.output/domain/mihomo" \
  "$TMP/exact-repo/sources/custom/domain"
cp "$ROOT/config/domain-platform-capabilities.json" "$TMP/exact-repo/config/"
printf 'DOMAIN,fixture.example\nDOMAIN-SUFFIX,example.org\n' > "$TMP/exact-repo/sources/custom/domain/fixture.list"
printf 'fixture\n' > "$TMP/exact-repo/.output/domain/sing-box/fixture.srs"
printf 'fixture\n' > "$TMP/exact-repo/.output/domain/mihomo/fixture.mrs"
cat > "$TMP/exact-repo/.bin/sing-box" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cp "${3}.json" "$5"
EOF
cat > "$TMP/exact-repo/.bin/mihomo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cp "${4}.txt" "$5"
EOF
chmod +x "$TMP/exact-repo/.bin/sing-box" "$TMP/exact-repo/.bin/mihomo"
cat > "$TMP/exact-repo/.output/domain/sing-box/fixture.srs.json" <<'EOF'
{"rules":[{"domain":["fixture.example"],"domain_suffix":["example.org"]}]}
EOF
printf 'fixture.example\n+.example.org\n' > "$TMP/exact-repo/.output/domain/mihomo/fixture.mrs.txt"
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" \
  --root "$TMP/exact-repo" \
  --path "$TMP/exact-repo/.output/domain/sing-box/fixture.srs" \
  --type domain \
  --platform sing-box | grep -F '"canonical_linkage": {"counts"' >/dev/null
PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" \
  --root "$TMP/exact-repo" \
  --path "$TMP/exact-repo/.output/domain/mihomo/fixture.mrs" \
  --type domain \
  --platform mihomo | grep -F '"canonical_linkage": {"counts"' >/dev/null

cat > "$TMP/exact-repo/.output/domain/sing-box/fixture.srs.json" <<'EOF'
{"rules":[{"domain":["replaced.example"],"domain_suffix":["example.org"]}]}
EOF
if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" \
  --root "$TMP/exact-repo" \
  --path "$TMP/exact-repo/.output/domain/sing-box/fixture.srs" \
  --type domain \
  --platform sing-box >/dev/null 2>&1; then
  echo "sing-box verifier accepted equal-count rule substitution" >&2
  exit 1
fi
printf 'replaced.example\n+.example.org\n' > "$TMP/exact-repo/.output/domain/mihomo/fixture.mrs.txt"
if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" \
  --root "$TMP/exact-repo" \
  --path "$TMP/exact-repo/.output/domain/mihomo/fixture.mrs" \
  --type domain \
  --platform mihomo >/dev/null 2>&1; then
  echo "mihomo verifier accepted equal-count rule substitution" >&2
  exit 1
fi

printf 'orphan\n' > "$TMP/exact-repo/.output/domain/sing-box/orphan.srs"
cat > "$TMP/exact-repo/.output/domain/sing-box/orphan.srs.json" <<'EOF'
{"rules":[{"domain":["orphan.example"]}]}
EOF
if PYTHONPATH="$ROOT/scripts/tools" python3 "$ROOT/scripts/tools/artifact_verifier.py" \
  --root "$TMP/exact-repo" \
  --path "$TMP/exact-repo/.output/domain/sing-box/orphan.srs" \
  --type domain \
  --platform sing-box >/dev/null 2>&1; then
  echo "binary verifier accepted artifact without canonical counterpart" >&2
  exit 1
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
