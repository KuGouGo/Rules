#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/scripts/tools" "$REPO/scripts/commands" "$REPO/config" "$REPO/sources/custom/domain" "$REPO/.bin"
cp "$ROOT/scripts/tools/artifact_manifest.py" "$ROOT/scripts/tools/artifact_verifier.py" "$ROOT/scripts/tools/platform_capabilities.py" "$REPO/scripts/tools/"
cat > "$REPO/.bin/sing-box" <<'EOF'
#!/usr/bin/env bash
set -eu
input="$3"; output="$5"
grep -q CORRUPT "$input" && exit 1
if [[ "$input" == */ip/* ]]; then printf '{"version":4,"rules":[{"ip_cidr":["192.0.2.0/24"]}]}\n' > "$output"
else printf '{"version":4,"rules":[{"domain_suffix":["custom.example"]}]}\n' > "$output"; fi
EOF
cat > "$REPO/.bin/mihomo" <<'EOF'
#!/usr/bin/env bash
set -eu
input="$4"; output="$5"
grep -q CORRUPT "$input" && exit 1
if [[ "$input" == */ip/* ]]; then printf '192.0.2.0/24\n' > "$output"; else printf '+.custom.example\n' > "$output"; fi
EOF
chmod +x "$REPO/.bin/sing-box" "$REPO/.bin/mihomo"
cp "$ROOT/scripts/commands/generate-artifact-manifest.sh" "$ROOT/scripts/commands/verify-artifact-manifest.sh" "$REPO/scripts/commands/"
cp "$ROOT/config/domain-platform-capabilities.json" "$ROOT/config/tools-lock.json" "$REPO/config/"
printf 'DOMAIN-SUFFIX,custom.example\n' > "$REPO/sources/custom/domain/custom.list"
git -C "$REPO" init -q
git -C "$REPO" config user.name test
git -C "$REPO" config user.email test@example.com
git -C "$REPO" add .
git -C "$REPO" commit -m fixture >/dev/null
SOURCE_SHA="$(git -C "$REPO" rev-parse HEAD)"
python3 - "$REPO" <<'PY'
import hashlib, json, sys
from pathlib import Path
root=Path(sys.argv[1]); lock_path=root/'config/tools-lock.json'; lock=json.loads(lock_path.read_text())
for tool in ('sing-box','mihomo'):
    binary=root/'.bin'/tool; sha=hashlib.sha256(binary.read_bytes()).hexdigest(); platform='linux-amd64'
    item=lock['tools'][tool]; item['platforms'][platform]['binary_sha256']=sha
    sidecar={'schema_version':1,'tool':tool,'version':item['version'],'tag_commit':item['tag_commit'],'platform':platform,
             'asset':item['platforms'][platform]['asset'],'archive_sha256':item['platforms'][platform]['sha256'],
             'binary_sha256':sha,'version_probe':'fixture'}
    (root/'.bin'/f'{tool}.provenance.json').write_text(json.dumps(sidecar,indent=2,sort_keys=True)+'\n')
lock_path.write_text(json.dumps(lock,indent=2,sort_keys=True)+'\n')
PY

make_files() {
  rm -rf "$REPO/.output"
  while read -r platform extension; do
    mkdir -p "$REPO/.output/domain/$platform" "$REPO/.output/ip/$platform"
    printf 'domain-%s\n' "$platform" > "$REPO/.output/domain/$platform/custom.$extension"
    printf 'ip-%s\n' "$platform" > "$REPO/.output/ip/$platform/base.$extension"
  done <<'EOF'
surge list
quanx list
egern yaml
sing-box srs
mihomo mrs
EOF
  python3 - "$REPO/.output" <<'PY'
import json, sys
from pathlib import Path
root=Path(sys.argv[1]); origins={}
for path in root.glob('*/*/*'):
    if path.is_file():
        rel=path.relative_to(root).as_posix()
        origins[rel]='generated-custom' if path.stem == 'custom' else 'restored-published-branch'
(root/'artifact-origins.json').write_text(json.dumps(origins,indent=2,sort_keys=True)+'\n')
(root/'build-summary.json').write_text('{}\n')
restoration={'generation_id':'restored-1','source_commit':'0'*40,'branches':{b:{'commit':'1'*40} for b in ('surge','quanx','egern','sing-box','mihomo')}}
(root/'restoration-metadata.json').write_text(json.dumps(restoration,indent=2,sort_keys=True)+'\n')
PY
}

generate() {
  ARTIFACT_GENERATION_ID=offline-1 ARTIFACT_BUILD_ID=build-1 ARTIFACT_BUILD_SCOPE="${1:-custom}" ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/generate-artifact-manifest.sh" >/dev/null
}
verify() { ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/verify-artifact-manifest.sh" >/dev/null; }
rejects() {
  local expected="$1"; shift
  set +e
  output="$("$@" 2>&1)"; status=$?
  set -e
  [ "$status" -ne 0 ] || { echo "expected rejection: $expected" >&2; exit 1; }
  grep -F "$expected" <<< "$output" >/dev/null || { echo "$output" >&2; exit 1; }
}

make_files
generate
verify
cp "$REPO/.output/artifact-manifest.json" "$TMP/first.json"
generate
cmp "$TMP/first.json" "$REPO/.output/artifact-manifest.json"
python3 - "$REPO/.output/artifact-manifest.json" <<'PY'
import json, sys
m=json.load(open(sys.argv[1], encoding='utf-8'))
origins={a['path']:a['origin'] for a in m['artifacts']}
assert origins['domain/surge/custom.list']=='generated-custom'
assert origins['domain/quanx/custom.list']=='generated-custom'
assert origins['ip/surge/base.list']=='restored-published-branch'
PY

printf tampered >> "$REPO/.output/domain/surge/custom.list"
rejects 'artifact hash mismatch' verify
make_files; generate
printf extra > "$REPO/.output/domain/surge/extra.list"
rejects 'unmanifested artifact' verify
make_files; generate
rm "$REPO/.output/ip/egern/base.yaml"
rejects 'manifest artifact missing' verify
make_files; generate
mkdir -p "$REPO/.output/domain/surge/nested"
printf nested > "$REPO/.output/domain/surge/nested/file.list"
rejects 'unexpected nested publishable file' verify
make_files; generate
: > "$REPO/.output/ip/mihomo/base.mrs"
rejects 'zero-byte artifact' verify
make_files; printf CORRUPT > "$REPO/.output/domain/sing-box/custom.srs"
rejects 'refusing to manifest unverified artifact' generate
make_files; generate
printf CORRUPT > "$REPO/.output/ip/mihomo/base.mrs"
python3 - "$REPO/.output/artifact-manifest.json" "$REPO/.output/ip/mihomo/base.mrs" <<'PY'
import hashlib, json, sys
manifest_path, artifact_path = sys.argv[1:]
data=json.load(open(manifest_path, encoding='utf-8'))
entry=next(item for item in data['artifacts'] if item['path']=='ip/mihomo/base.mrs')
entry['bytes']=len(b'CORRUPT')
entry['sha256']=hashlib.sha256(b'CORRUPT').hexdigest()
json.dump(data, open(manifest_path, 'w', encoding='utf-8'), indent=2, sort_keys=True)
PY
rejects 'artifact binary/readability verification failed' verify
make_files; generate
rejects 'source commit mismatch' env ARTIFACT_SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$REPO/scripts/commands/verify-artifact-manifest.sh"

printf 'artifact manifest tests passed\n'
