#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Active build/configuration paths must not retain the historical provider,
# a Fake-IP URL, a download command, or an independent workflow sync step.
if grep -RInE 'wwqgtxx|https?://[^[:space:]]*fakeip|sync-fakeip-filter|curl[^\n]*fakeip|wget[^\n]*fakeip' \
  "$ROOT/scripts/commands" "$ROOT/scripts/lib" "$ROOT/scripts/tools" \
  "$ROOT/config" "$ROOT/.github/workflows" "$ROOT/Makefile"; then
  echo "test failed: active Fake-IP third-party download or sync reference remains" >&2
  exit 1
fi

[ ! -e "$ROOT/scripts/commands/sync-fakeip-filter.sh" ] || {
  echo "test failed: unused legacy Fake-IP sync wrapper still exists" >&2
  exit 1
}

grep -F 'KuGouGo-maintained' "$ROOT/sources/custom/domain/fakeip-filter.list" >/dev/null

RENDER_REPO="$TMP_DIR/render"
FAKEIP_SOURCE="$TMP_DIR/fakeip-filter.list"
cp "$ROOT/sources/custom/domain/fakeip-filter.list" "$FAKEIP_SOURCE"
mkdir -p "$RENDER_REPO"
cp -R "$ROOT/scripts" "$ROOT/config" "$ROOT/sources" "$RENDER_REPO/"
rm "$RENDER_REPO/sources/custom/domain/fakeip-filter.list"
git -C "$RENDER_REPO" init -q
git -C "$RENDER_REPO" config user.name test
git -C "$RENDER_REPO" config user.email test@example.com
git -C "$RENDER_REPO" add scripts config sources
git -C "$RENDER_REPO" commit -m base >/dev/null
cp "$FAKEIP_SOURCE" "$RENDER_REPO/sources/custom/domain/fakeip-filter.list"
git -C "$RENDER_REPO" add sources/custom/domain/fakeip-filter.list
git -C "$RENDER_REPO" commit -m add-fakeip >/dev/null
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
grep -Fx "  - '^time\\.[^.]+\\.com$'" "$RENDER_REPO/.output/domain/egern/fakeip-filter.yaml" >/dev/null

prepare_collision_repo() {
  local repo="$1"
  mkdir -p "$repo"
  cp -R "$ROOT/scripts" "$ROOT/config" "$ROOT/sources" "$repo/"
  rm "$repo/sources/custom/domain/fakeip-filter.list"
  git -C "$repo" init -q
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" add scripts config sources
}

# The one-time exception is valid only when the selected base really contains
# the historical artifact and lacks the maintained source.
MIGRATION_REPO="$TMP_DIR/migration"
prepare_collision_repo "$MIGRATION_REPO"
mkdir -p "$MIGRATION_REPO/.output/domain/mihomo"
printf 'historical binary\n' > "$MIGRATION_REPO/.output/domain/mihomo/fakeip-filter.mrs"
git -C "$MIGRATION_REPO" add -f .output/domain/mihomo/fakeip-filter.mrs
git -C "$MIGRATION_REPO" commit -m historical >/dev/null
MIGRATION_BASE="$(git -C "$MIGRATION_REPO" rev-parse HEAD)"
cp "$ROOT/sources/custom/domain/fakeip-filter.list" "$MIGRATION_REPO/sources/custom/domain/"
RULES_CONFLICT_BASE_SHA="$MIGRATION_BASE" RULES_BUILD_CUSTOM_TEXT_ONLY=1 \
  "$MIGRATION_REPO/scripts/commands/build-custom.sh" >/dev/null

# Merely placing a same-named output in the working tree must not activate a
# permanent broad bypass when the base never tracked that historical binary.
COLLISION_REPO="$TMP_DIR/collision"
prepare_collision_repo "$COLLISION_REPO"
git -C "$COLLISION_REPO" commit -m base >/dev/null
COLLISION_BASE="$(git -C "$COLLISION_REPO" rev-parse HEAD)"
mkdir -p "$COLLISION_REPO/.output/domain/mihomo"
printf 'unrelated existing output\n' > "$COLLISION_REPO/.output/domain/mihomo/fakeip-filter.mrs"
cp "$ROOT/sources/custom/domain/fakeip-filter.list" "$COLLISION_REPO/sources/custom/domain/"
if RULES_CONFLICT_BASE_SHA="$COLLISION_BASE" RULES_BUILD_CUSTOM_TEXT_ONLY=1 \
  "$COLLISION_REPO/scripts/commands/build-custom.sh" \
  >"$TMP_DIR/collision.stdout" 2>"$TMP_DIR/collision.stderr"; then
  echo "test failed: Fake-IP collision bypass applied without historical base artifact" >&2
  exit 1
fi
grep -F "custom rule name conflict detected for base 'fakeip-filter'" \
  "$TMP_DIR/collision.stderr" >/dev/null

echo "Fake-IP migration tests passed"
