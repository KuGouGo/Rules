#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Fake-IP is a maintained custom source and must not regain an independent
# provider, download, wrapper, or workflow path.
if grep -RInE 'wwqgtxx|https?://[^[:space:]]*fakeip|sync-fakeip-filter|curl[^\n]*fakeip|wget[^\n]*fakeip' \
  "$ROOT/scripts/commands" "$ROOT/scripts/lib" "$ROOT/scripts/tools" \
  "$ROOT/config" "$ROOT/.github/workflows" "$ROOT/Makefile"; then
  echo "test failed: active Fake-IP third-party download or sync reference remains" >&2
  exit 1
fi

[ ! -e "$ROOT/scripts/commands/sync-fakeip-filter.sh" ] || {
  echo "test failed: unused Fake-IP sync wrapper still exists" >&2
  exit 1
}

grep -F 'KuGouGo-maintained' "$ROOT/sources/custom/domain/fakeip-filter.list" >/dev/null

RENDER_REPO="$TMP_DIR/render"
mkdir -p "$RENDER_REPO"
cp -R "$ROOT/scripts" "$ROOT/config" "$ROOT/sources" "$RENDER_REPO/"
git -C "$RENDER_REPO" init -q
git -C "$RENDER_REPO" config user.name test
git -C "$RENDER_REPO" config user.email test@example.com
git -C "$RENDER_REPO" add scripts config sources
git -C "$RENDER_REPO" commit -m base >/dev/null
RULES_BUILD_CUSTOM_TEXT_ONLY=1 "$RENDER_REPO/scripts/commands/build-custom.sh" >/dev/null
RULES_BUILD_CUSTOM_TEXT_ONLY=1 "$RENDER_REPO/scripts/commands/build-custom.sh" >/dev/null

if grep -Fx '*' "$ROOT/sources/custom/domain/fakeip-filter.list" >/dev/null; then
  echo "test failed: universal Fake-IP bypass must not be published" >&2
  exit 1
fi
grep -Fx 'DOMAIN-SUFFIX,lan' "$RENDER_REPO/.output/domain/surge/fakeip-filter.list" >/dev/null
grep -Fx 'DOMAIN,proxy.golang.org' "$RENDER_REPO/.output/domain/surge/fakeip-filter.list" >/dev/null
if grep -F 'DOMAIN-REGEX,' "$RENDER_REPO/.output/domain/surge/fakeip-filter.list" >/dev/null; then
  echo "test failed: Surge output retained unsupported regex rules" >&2
  exit 1
fi
grep -Fx 'HOST-SUFFIX,lan,fakeip-filter' "$RENDER_REPO/.output/domain/quanx/fakeip-filter.list" >/dev/null
grep -Fx 'HOST,proxy.golang.org,fakeip-filter' "$RENDER_REPO/.output/domain/quanx/fakeip-filter.list" >/dev/null
grep -Fx "  - 'lan'" "$RENDER_REPO/.output/domain/egern/fakeip-filter.yaml" >/dev/null
grep -Fx "  - 'proxy.golang.org'" "$RENDER_REPO/.output/domain/egern/fakeip-filter.yaml" >/dev/null
grep -Fx "  - '^time\.[^.]+\.com$'" "$RENDER_REPO/.output/domain/egern/fakeip-filter.yaml" >/dev/null

# A new custom source may not overwrite an existing published artifact with the
# same name. Fake-IP follows the same conflict rule as every other custom list.
COLLISION_REPO="$TMP_DIR/collision"
mkdir -p "$COLLISION_REPO"
cp -R "$ROOT/scripts" "$ROOT/config" "$ROOT/sources" "$COLLISION_REPO/"
rm "$COLLISION_REPO/sources/custom/domain/fakeip-filter.list"
git -C "$COLLISION_REPO" init -q
git -C "$COLLISION_REPO" config user.name test
git -C "$COLLISION_REPO" config user.email test@example.com
git -C "$COLLISION_REPO" add scripts config sources
git -C "$COLLISION_REPO" commit -m base >/dev/null
COLLISION_BASE="$(git -C "$COLLISION_REPO" rev-parse HEAD)"
mkdir -p "$COLLISION_REPO/.output/domain/mihomo"
printf 'existing output\n' > "$COLLISION_REPO/.output/domain/mihomo/fakeip-filter.mrs"
cp "$ROOT/sources/custom/domain/fakeip-filter.list" "$COLLISION_REPO/sources/custom/domain/"
if RULES_CONFLICT_BASE_SHA="$COLLISION_BASE" RULES_BUILD_CUSTOM_TEXT_ONLY=1 \
  "$COLLISION_REPO/scripts/commands/build-custom.sh" \
  >"$TMP_DIR/collision.stdout" 2>"$TMP_DIR/collision.stderr"; then
  echo "test failed: Fake-IP source overwrote an existing same-named artifact" >&2
  exit 1
fi
grep -F "custom rule name conflict detected for base 'fakeip-filter'" \
  "$TMP_DIR/collision.stderr" >/dev/null

echo "Fake-IP filter tests passed"
