#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REMOTE="$TMP_DIR/remote.git"
REPO="$TMP_DIR/repo"
SEED="$TMP_DIR/seed"
BRANCHES=(surge quanx egern sing-box mihomo)
TEMPLATE_DIR="$ROOT/templates/branch-readmes"
published_tree_description="分支仅包含 \`README.md\`、\`domain/\` 与 \`ip/\`"

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
  grep -F '自动构建产物' "$template" >/dev/null
  grep -F "$published_tree_description" "$template" >/dev/null
  grep -F '## 文件里有什么' "$template" >/dev/null
  grep -F '## 最小示例' "$template" >/dev/null
  case "$branch" in
    surge|quanx) extension=.list ;;
    egern) extension=.yaml ;;
    sing-box) extension=.srs ;;
    mihomo) extension=.mrs ;;
  esac
  grep -F "\`$extension\`" "$template" >/dev/null
  grep -F '[主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)' "$template" >/dev/null
  grep -F '[LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)' "$template" >/dev/null
  grep -F '[THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)' "$template" >/dev/null
  grep -F '域名数据 MIT 通知' "$template" >/dev/null
  grep -F 'v2fly/domain-list-community' "$template" >/dev/null
  grep -F 'https://github.com/v2fly/domain-list-community/blob/master/LICENSE' "$template" >/dev/null
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
SOURCE_SHA="$(git -C "$SEED" rev-parse HEAD)"

mkdir -p "$REPO"
cp -R scripts templates config "$REPO/"
mkdir -p \
  "$REPO/.output/domain/surge" "$REPO/.output/ip/surge" \
  "$REPO/.output/domain/quanx" "$REPO/.output/ip/quanx" \
  "$REPO/.output/domain/egern" "$REPO/.output/ip/egern" \
  "$REPO/.output/domain/sing-box" "$REPO/.output/ip/sing-box" \
  "$REPO/.output/domain/mihomo" "$REPO/.output/ip/mihomo"

printf 'DOMAIN-SUFFIX,example.com\n' > "$REPO/.output/domain/surge/test.list"
printf 'IP-CIDR,192.0.2.0/24,no-resolve\n' > "$REPO/.output/ip/surge/test.list"
printf 'HOST-SUFFIX,example.com,test\n' > "$REPO/.output/domain/quanx/test.list"
printf 'IP-CIDR,192.0.2.0/24,test\n' > "$REPO/.output/ip/quanx/test.list"
printf "domain_suffix_set:\n  - 'example.com'\n" > "$REPO/.output/domain/egern/test.yaml"
printf "no_resolve: true\nip_cidr_set:\n  - '192.0.2.0/24'\n" > "$REPO/.output/ip/egern/test.yaml"
printf 'srs-domain\n' > "$REPO/.output/domain/sing-box/test.srs"
printf 'srs-ip\n' > "$REPO/.output/ip/sing-box/test.srs"
printf 'mrs-domain\n' > "$REPO/.output/domain/mihomo/test.mrs"
printf 'mrs-ip\n' > "$REPO/.output/ip/mihomo/test.mrs"
mkdir -p "$REPO/.output/.canonical/domain" "$REPO/.output/.canonical/ip"
printf 'DOMAIN-SUFFIX,example.com\n' > "$REPO/.output/.canonical/domain/test.list"
printf 'IP-CIDR,192.0.2.0/24,no-resolve\n' > "$REPO/.output/.canonical/ip/test.list"

git -C "$REPO" init -q
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" fetch origin '+refs/heads/*:refs/remotes/origin/*' >/dev/null 2>&1

PUBLISH_DRY_RUN=1 ARTIFACT_SOURCE_SHA="$SOURCE_SHA" \
  "$REPO/scripts/commands/publish-branches.sh" >"$TMP_DIR/dry-run.log" 2>&1 || {
    echo "test failed: publish dry-run failed" >&2
    cat "$TMP_DIR/dry-run.log" >&2
    exit 1
  }
for branch in "${BRANCHES[@]}"; do
  if git --git-dir="$REMOTE" rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1; then
    echo "test failed: dry-run must not create remote branch $branch" >&2
    exit 1
  fi
done

ARTIFACT_SOURCE_SHA="$SOURCE_SHA" \
  "$REPO/scripts/commands/publish-branches.sh" >"$TMP_DIR/publish.log" 2>&1 || {
    echo "test failed: first publish failed" >&2
    cat "$TMP_DIR/publish.log" >&2
    exit 1
  }
grep -F 'publishing branches atomically: surge quanx egern sing-box mihomo' "$TMP_DIR/publish.log" >/dev/null

for branch in "${BRANCHES[@]}"; do
  case "$branch" in
    surge|quanx) extension=list ;;
    egern) extension=yaml ;;
    sing-box) extension=srs ;;
    mihomo) extension=mrs ;;
  esac
  git --git-dir="$REMOTE" cat-file -e "refs/heads/$branch:README.md" || {
    echo "test failed: $branch missing README.md" >&2
    exit 1
  }
  git --git-dir="$REMOTE" cat-file -e "refs/heads/$branch:domain/test.$extension" || {
    echo "test failed: $branch missing domain/test.$extension" >&2
    exit 1
  }
  git --git-dir="$REMOTE" cat-file -e "refs/heads/$branch:ip/test.$extension" || {
    echo "test failed: $branch missing ip/test.$extension" >&2
    exit 1
  }
  tree_files="$(git --git-dir="$REMOTE" ls-tree -r --name-only "$branch")"
  if grep -v -E '^(README\.md|domain/|ip/)' <<<"$tree_files" | grep -q .; then
    echo "test failed: $branch publish tree contains unexpected files" >&2
    exit 1
  fi
done

ARTIFACT_SOURCE_SHA="$SOURCE_SHA" \
  "$REPO/scripts/commands/publish-branches.sh" >"$TMP_DIR/skip.log" 2>&1 || {
    echo "test failed: unchanged publish run failed" >&2
    cat "$TMP_DIR/skip.log" >&2
    exit 1
  }
grep -F 'all publish branches unchanged, skip push' "$TMP_DIR/skip.log" >/dev/null

printf 'DOMAIN-SUFFIX,updated.example\n' >> "$REPO/.output/domain/surge/test.list"
ARTIFACT_SOURCE_SHA="$SOURCE_SHA" \
  "$REPO/scripts/commands/publish-branches.sh" >"$TMP_DIR/republish.log" 2>&1 || {
    echo "test failed: republish failed" >&2
    cat "$TMP_DIR/republish.log" >&2
    exit 1
  }
grep -F 'publishing branches atomically' "$TMP_DIR/republish.log" >/dev/null

rm "$REPO/.output/domain/sing-box/test.srs"
if ARTIFACT_SOURCE_SHA="$SOURCE_SHA" \
  "$REPO/scripts/commands/publish-branches.sh" >"$TMP_DIR/missing.log" 2>&1; then
  echo "test failed: publish accepted missing sing-box domain artifacts" >&2
  exit 1
fi
grep -F 'no supported artifacts found in domain/sing-box' "$TMP_DIR/missing.log" >/dev/null

echo "publish branches tests passed"
