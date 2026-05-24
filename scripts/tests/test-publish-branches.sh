#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REMOTE="$TMP_DIR/remote.git"
REPO="$TMP_DIR/repo"
SEED="$TMP_DIR/seed"

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
cp -R scripts "$REPO/"
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
printf 'domain_suffix_set:\n  - example.com\n' > "$REPO/.output/domain/egern/test.yaml"
printf 'ip_cidr_set:\n  - 192.0.2.0/24\n' > "$REPO/.output/ip/egern/test.yaml"
printf 'srs-domain\n' > "$REPO/.output/domain/sing-box/test.srs"
printf 'srs-ip\n' > "$REPO/.output/ip/sing-box/test.srs"
printf 'mrs-domain\n' > "$REPO/.output/domain/mihomo/test.mrs"
printf 'mrs-ip\n' > "$REPO/.output/ip/mihomo/test.mrs"

git -C "$REPO" init -q
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" fetch origin '+refs/heads/*:refs/remotes/origin/*' >/dev/null 2>&1

"$REPO/scripts/commands/publish-branches.sh" >/dev/null 2>&1

for branch in surge quanx egern sing-box mihomo; do
  git --git-dir="$REMOTE" rev-parse --verify "refs/heads/$branch" >/dev/null
  file_count="$(git --git-dir="$REMOTE" ls-tree -r --name-only "$branch" | wc -l | tr -d ' ')"
  if [ "$file_count" -ne 3 ]; then
    echo "test failed: expected 3 files on $branch, got $file_count" >&2
    exit 1
  fi
done

echo "publish branch tests passed"
