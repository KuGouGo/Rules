#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REMOTE="$TMP_DIR/remote.git"
REPO="$TMP_DIR/repo"
SEED="$TMP_DIR/seed"
REAL_GIT="$(command -v git)"
BRANCHES=(surge quanx egern sing-box mihomo)
TEMPLATE_DIR="$ROOT/templates/branch-readmes"
published_tree_description="仅保留 \`README.md\`、\`domain/\` 和 \`ip/\`"

grep -Fq -- "- 'templates/**'" "$ROOT/.github/workflows/build.yml" || {
  echo "test failed: build workflow push.paths must include templates/**" >&2
  exit 1
}

for branch in "${BRANCHES[@]}"; do
  template="$TEMPLATE_DIR/$branch.md"
  [ -f "$template" ] || {
    echo "test failed: missing README template for $branch" >&2
    exit 1
  }
  grep -F '滚动构建产物' "$template" >/dev/null
  grep -F "$published_tree_description" "$template" >/dev/null
  grep -F '## 产物格式与能力降级' "$template" >/dev/null
  grep -F '## 最小示例' "$template" >/dev/null
  case "$branch" in
    surge|quanx) extension=.list ;;
    egern) extension=.yaml ;;
    sing-box) extension=.srs ;;
    mihomo) extension=.mrs ;;
  esac
  grep -F "\`$extension\`" "$template" >/dev/null
  grep -F '[主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)' "$template" >/dev/null
  grep -F '[NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)' "$template" >/dev/null
  grep -F '[LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)' "$template" >/dev/null
  grep -F '[THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)' "$template" >/dev/null
  grep -F 'Copyright (c) 2018-2019 V2Ray' "$template" >/dev/null
  grep -F 'The above copyright notice and this permission notice shall be included in all' "$template" >/dev/null
  grep -F 'THE SOFTWARE IS PROVIDED "AS IS"' "$template" >/dev/null
done

grep -F '# Rules / Quantumult X' "$TEMPLATE_DIR/quanx.md" >/dev/null
if grep -F 'QuanX' "$TEMPLATE_DIR/quanx.md" >/dev/null; then
  echo 'test failed: Quantumult X template exposes the QuanX abbreviation' >&2
  exit 1
fi

git init --bare "$REMOTE" >/dev/null
git init -q "$SEED"
git -C "$SEED" config user.name test
git -C "$SEED" config user.email test@example.com
printf 'seed\n' > "$SEED/README.md"
git -C "$SEED" add README.md
git -C "$SEED" commit -m seed >/dev/null
git -C "$SEED" branch -M main
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push origin main >/dev/null 2>&1
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/main

mkdir -p "$REPO"
cp -R scripts templates config "$REPO/"
mkdir -p "$REPO/.bin"
mkdir -p \
  "$REPO/.output/domain/surge" "$REPO/.output/ip/surge" \
  "$REPO/.output/domain/quanx" "$REPO/.output/ip/quanx" \
  "$REPO/.output/domain/egern" "$REPO/.output/ip/egern" \
  "$REPO/.output/domain/sing-box" "$REPO/.output/ip/sing-box" \
  "$REPO/.output/domain/mihomo" "$REPO/.output/ip/mihomo"

printf 'DOMAIN-SUFFIX,example.com\n' > "$REPO/.output/domain/surge/test.list"
printf 'IP-CIDR,192.0.2.0/24,no-resolve\n' > "$REPO/.output/ip/surge/test.list"
printf 'HOST-SUFFIX,example.com,direct\n' > "$REPO/.output/domain/quanx/test.list"
printf 'IP-CIDR,192.0.2.0/24,direct\n' > "$REPO/.output/ip/quanx/test.list"
printf "domain_suffix_set:\n  - 'example.com'\n" > "$REPO/.output/domain/egern/test.yaml"
printf "no_resolve: true\nip_cidr_set:\n  - '192.0.2.0/24'\n" > "$REPO/.output/ip/egern/test.yaml"
printf 'srs-domain\n' > "$REPO/.output/domain/sing-box/test.srs"
printf 'srs-ip\n' > "$REPO/.output/ip/sing-box/test.srs"
printf 'mrs-domain\n' > "$REPO/.output/domain/mihomo/test.mrs"
printf 'mrs-ip\n' > "$REPO/.output/ip/mihomo/test.mrs"

cat > "$REPO/.bin/sing-box" <<'EOF'
#!/usr/bin/env bash
set -eu
input="$3"
output="$5"
if [[ "$input" == */ip/* ]]; then
  printf '{"version":4,"rules":[{"ip_cidr":["192.0.2.0/24"]}]}\n' > "$output"
else
  printf '{"version":4,"rules":[{"domain_suffix":["example.com"]}]}\n' > "$output"
fi
EOF
cat > "$REPO/.bin/mihomo" <<'EOF'
#!/usr/bin/env bash
set -eu
input="$4"
output="$5"
if [[ "$input" == */ip/* ]]; then
  printf '192.0.2.0/24\n' > "$output"
else
  printf '+.example.com\n' > "$output"
fi
EOF
chmod +x "$REPO/.bin/sing-box" "$REPO/.bin/mihomo"

python3 - "$REPO" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
lock_path = root / "config/tools-lock.json"
lock = json.loads(lock_path.read_text(encoding="utf-8"))
for tool in ("sing-box", "mihomo"):
    binary = root / ".bin" / tool
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    item = lock["tools"][tool]
    platform = "linux-amd64"
    item["platforms"][platform]["binary_sha256"] = digest
    sidecar = {
        "schema_version": 1,
        "tool": tool,
        "version": item["version"],
        "tag_commit": item["tag_commit"],
        "platform": platform,
        "asset": item["platforms"][platform]["asset"],
        "archive_sha256": item["platforms"][platform]["sha256"],
        "binary_sha256": digest,
        "version_probe": "fixture",
    }
    (root / ".bin" / f"{tool}.provenance.json").write_text(
        json.dumps(sidecar, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
lock_path.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8")

origins = {}
for path in (root / ".output").glob("*/*/*"):
    if path.is_file():
        origins[path.relative_to(root / ".output").as_posix()] = "generated-upstream"
(root / ".output/artifact-origins.json").write_text(
    json.dumps(origins, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
(root / ".output/build-summary.json").write_text("{}\n", encoding="utf-8")
PY

git -C "$REPO" init -q
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" fetch origin '+refs/heads/*:refs/remotes/origin/*' >/dev/null 2>&1
SOURCE_SHA="$(git -C "$SEED" rev-parse HEAD)"
ARTIFACT_GENERATION_ID=test-generation ARTIFACT_BUILD_SCOPE=full ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/generate-artifact-manifest.sh" >/dev/null

first_output="$(ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/publish-branches.sh" 2>&1)"
grep -F "publishing branches atomically: surge quanx egern sing-box mihomo" <<< "$first_output" >/dev/null

for branch in "${BRANCHES[@]}"; do
  git --git-dir="$REMOTE" rev-parse --verify "refs/heads/$branch" >/dev/null
  actual_files="$(git --git-dir="$REMOTE" ls-tree -r --name-only "$branch")"
  case "$branch" in
    surge|quanx) extension=list ;;
    egern) extension=yaml ;;
    sing-box) extension=srs ;;
    mihomo) extension=mrs ;;
  esac
  expected_files="README.md
domain/test.$extension
ip/test.$extension"
  if [ "$actual_files" != "$expected_files" ]; then
    echo "test failed: unexpected tree on $branch" >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected_files" "$actual_files" >&2
    exit 1
  fi
  generated_readme="$TMP_DIR/$branch.README.md"
  git --git-dir="$REMOTE" show "$branch:README.md" > "$generated_readme"
  cmp "$TEMPLATE_DIR/$branch.md" "$generated_readme" >/dev/null || {
    echo "test failed: generated README does not match template for $branch" >&2
    exit 1
  }
done

git --git-dir="$REMOTE" show quanx:README.md | grep -F '# Rules / Quantumult X' >/dev/null
if git --git-dir="$REMOTE" show quanx:README.md | grep -F 'QuanX' >/dev/null; then
  echo 'test failed: generated Quantumult X README exposes the QuanX abbreviation' >&2
  exit 1
fi

git --git-dir="$REMOTE" show surge:domain/test.list | grep -Fx 'DOMAIN-SUFFIX,example.com' >/dev/null
git --git-dir="$REMOTE" show quanx:ip/test.list | grep -Fx 'IP-CIDR,192.0.2.0/24,direct' >/dev/null

before_idempotent="$(for branch in "${BRANCHES[@]}"; do git --git-dir="$REMOTE" rev-parse "$branch"; done)"
git -C "$REPO" fetch origin '+refs/heads/*:refs/remotes/origin/*' >/dev/null 2>&1
second_output="$(ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/publish-branches.sh" 2>&1)"
after_idempotent="$(for branch in "${BRANCHES[@]}"; do git --git-dir="$REMOTE" rev-parse "$branch"; done)"
[ "$before_idempotent" = "$after_idempotent" ]
grep -F "all publish branches unchanged, skip push" <<< "$second_output" >/dev/null

# A missing template must fail before the queued batch is pushed.
before_missing_template="$(for branch in "${BRANCHES[@]}"; do git --git-dir="$REMOTE" rev-parse "$branch"; done)"
cp "$REPO/templates/branch-readmes/surge.md" "$REPO/templates/branch-readmes/surge.md.original"
printf '\nqueued template change\n' >> "$REPO/templates/branch-readmes/surge.md"
mv "$REPO/templates/branch-readmes/mihomo.md" "$REPO/templates/branch-readmes/mihomo.md.missing"
set +e
missing_template_output="$(ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/publish-branches.sh" 2>&1)"
missing_template_status=$?
set -e
mv "$REPO/templates/branch-readmes/surge.md.original" "$REPO/templates/branch-readmes/surge.md"
mv "$REPO/templates/branch-readmes/mihomo.md.missing" "$REPO/templates/branch-readmes/mihomo.md"
[ "$missing_template_status" -ne 0 ] || {
  echo "test failed: missing README template should reject publish" >&2
  exit 1
}
grep -F 'missing publish README template:' <<< "$missing_template_output" >/dev/null
after_missing_template="$(for branch in "${BRANCHES[@]}"; do git --git-dir="$REMOTE" rev-parse "$branch"; done)"
[ "$before_missing_template" = "$after_missing_template" ] || {
  echo "test failed: missing template partially updated publish branches" >&2
  exit 1
}

# Force a lease race immediately before the atomic push. The competing surge
# update must reject the complete batch, leaving every other branch untouched.
for branch in "${BRANCHES[@]}"; do
  case "$branch" in
    surge)
      extension=list
      printf 'DOMAIN-SUFFIX,updated.example\n' > "$REPO/.output/domain/$branch/test.$extension"
      ;;
    quanx)
      extension=list
      printf 'HOST-SUFFIX,updated.example,direct\n' > "$REPO/.output/domain/$branch/test.$extension"
      ;;
    egern)
      extension=yaml
      printf "domain_suffix_set:\n  - 'updated.example'\n" > "$REPO/.output/domain/$branch/test.$extension"
      ;;
    sing-box)
      extension=srs
      printf 'updated-%s\n' "$branch" > "$REPO/.output/domain/$branch/test.$extension"
      ;;
    mihomo)
      extension=mrs
      printf 'updated-%s\n' "$branch" > "$REPO/.output/domain/$branch/test.$extension"
      ;;
  esac
done

set +e
unverified_publish_output="$(ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/publish-branches.sh" 2>&1)"
unverified_publish_status=$?
set -e
[ "$unverified_publish_status" -ne 0 ] || {
  echo "test failed: modified artifacts should reject publish" >&2
  exit 1
}
grep -F 'artifact hash mismatch' <<< "$unverified_publish_output" >/dev/null

git -C "$REPO" fetch origin '+refs/heads/*:refs/remotes/origin/*' >/dev/null 2>&1
ARTIFACT_GENERATION_ID=test-generation-2 ARTIFACT_BUILD_SCOPE=full ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/generate-artifact-manifest.sh" >/dev/null
before_race="$(for branch in "${BRANCHES[@]}"; do git --git-dir="$REMOTE" rev-parse "$branch"; done)"
mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/git" <<'EOF'
#!/usr/bin/env bash
set -e
if [ "${1:-}" = push ] && [ "${2:-}" = --atomic ] && [ ! -e "$RACE_MARKER" ]; then
  : > "$RACE_MARKER"
  "$REAL_GIT" clone -q --branch surge "$RACE_REMOTE" "$RACE_REPO"
  "$REAL_GIT" -C "$RACE_REPO" config user.name racer
  "$REAL_GIT" -C "$RACE_REPO" config user.email racer@example.com
  printf '\nracing update\n' >> "$RACE_REPO/README.md"
  "$REAL_GIT" -C "$RACE_REPO" add README.md
  "$REAL_GIT" -C "$RACE_REPO" commit -m race >/dev/null
  "$REAL_GIT" -C "$RACE_REPO" push origin surge >/dev/null 2>&1
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$TMP_DIR/bin/git"

set +e
race_output="$(PATH="$TMP_DIR/bin:$PATH" REAL_GIT="$REAL_GIT" RACE_MARKER="$TMP_DIR/raced" RACE_REMOTE="$REMOTE" RACE_REPO="$TMP_DIR/racer" ARTIFACT_SOURCE_SHA="$SOURCE_SHA" "$REPO/scripts/commands/publish-branches.sh" 2>&1)"
race_status=$?
set -e
[ "$race_status" -ne 0 ] || {
  echo "test failed: stale lease should reject atomic publish" >&2
  exit 1
}
[ -e "$TMP_DIR/raced" ]
after_race="$(for branch in "${BRANCHES[@]}"; do git --git-dir="$REMOTE" rev-parse "$branch"; done)"
before_race_without_surge="$(printf '%s\n' "$before_race" | tail -n +2)"
after_race_without_surge="$(printf '%s\n' "$after_race" | tail -n +2)"
[ "$after_race_without_surge" = "$before_race_without_surge" ] || {
  echo "test failed: atomic rejection partially updated another branch" >&2
  echo "$race_output" >&2
  exit 1
}
[ "$(printf '%s\n' "$after_race" | head -n 1)" != "$(printf '%s\n' "$before_race" | head -n 1)" ]
git --git-dir="$REMOTE" show surge:README.md | grep -F 'racing update' >/dev/null

printf 'publish branch tests passed\n'
