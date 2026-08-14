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
cp -R scripts config "$REPO/"
git -C "$REPO" init -q
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" fetch origin '+refs/heads/*:refs/remotes/origin/*' >/dev/null 2>&1

publish_seed() {
  local generation="$1"
  local branch_seed="$TMP_DIR/branch-seed"
  git clone -q "$REMOTE" "$branch_seed" 2>/dev/null || true
  git -C "$branch_seed" config user.name test
  git -C "$branch_seed" config user.email test@example.com

  for branch in "${BRANCHES[@]}"; do
    git -C "$branch_seed" checkout --orphan "$branch" >/dev/null 2>&1
    git -C "$branch_seed" rm -rf . >/dev/null 2>&1 || true
    find "$branch_seed" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    mkdir -p "$branch_seed/domain" "$branch_seed/ip"
    printf 'DOMAIN-SUFFIX,%s.example\n' "$branch" > "$branch_seed/domain/test.list"
    printf 'IP-CIDR,192.0.2.0/24,no-resolve\n' > "$branch_seed/ip/test.list"
    printf 'seed %s\n' "$branch" > "$branch_seed/README.md"
    git -C "$branch_seed" add README.md domain ip
    git -C "$branch_seed" commit -m "chore: publish ${branch} artifacts [generation ${generation} source ${SOURCE_SHA}]" >/dev/null
    git -C "$branch_seed" push origin "$branch" >/dev/null 2>&1
  done
}

run_restore() {
  local artifact_root="$1"
  local baseline_file="$2"
  RULES_ARTIFACT_ROOT="$artifact_root" \
    ARTIFACT_BASELINE_FILE="$baseline_file" \
    "$REPO/scripts/commands/restore-artifacts.sh"
}

# Happy path: all five branches share one generation/source cohort.
publish_seed 200-1
ARTIFACT_ROOT="$TMP_DIR/restored"
BASELINE_FILE="$TMP_DIR/baseline.json"
run_restore "$ARTIFACT_ROOT" "$BASELINE_FILE" >/dev/null

for branch in "${BRANCHES[@]}"; do
  grep -Fx "DOMAIN-SUFFIX,${branch}.example" "$ARTIFACT_ROOT/domain/$branch/test.list" >/dev/null
  grep -Fx 'IP-CIDR,192.0.2.0/24,no-resolve' "$ARTIFACT_ROOT/ip/$branch/test.list" >/dev/null
done
[ -f "$ARTIFACT_ROOT/restoration-metadata.json" ] || {
  echo "test failed: missing restoration-metadata.json" >&2
  exit 1
}
cmp "$BASELINE_FILE" "$ARTIFACT_ROOT/restoration-metadata.json" >/dev/null || {
  echo "test failed: baseline was not seeded from restoration metadata" >&2
  exit 1
}
python3 - "$ARTIFACT_ROOT/restoration-metadata.json" "$SOURCE_SHA" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
source = sys.argv[2]
assert metadata["status"] == "consistent"
assert metadata["generation_id"] == "200-1"
assert metadata["source_commit"] == source
assert set(metadata["branches"]) == {"surge", "quanx", "egern", "sing-box", "mihomo"}
for item in metadata["branches"].values():
    assert item["generation_id"] == "200-1"
    assert item["source_commit"] == source
PY

# A second restore against the same baseline must keep comparing equal.
run_restore "$TMP_DIR/restored-again" "$BASELINE_FILE" >/dev/null
cmp "$BASELINE_FILE" "$TMP_DIR/restored-again/restoration-metadata.json" >/dev/null

# Inconsistent cohort: branches advertise different generations. Replace the
# fixture surge branch with one carrying a different cohort identity.
git clone -q "$REMOTE" "$TMP_DIR/mixed-seed"
git -C "$TMP_DIR/mixed-seed" config user.name test
git -C "$TMP_DIR/mixed-seed" config user.email test@example.com
git -C "$TMP_DIR/mixed-seed" checkout --orphan surge >/dev/null 2>&1
git -C "$TMP_DIR/mixed-seed" rm -rf . >/dev/null 2>&1 || true
mkdir -p "$TMP_DIR/mixed-seed/domain" "$TMP_DIR/mixed-seed/ip"
printf 'DOMAIN-SUFFIX,surge.example\n' > "$TMP_DIR/mixed-seed/domain/test.list"
printf 'IP-CIDR,198.51.100.0/24,no-resolve\n' > "$TMP_DIR/mixed-seed/ip/test.list"
printf 'mixed\n' > "$TMP_DIR/mixed-seed/README.md"
git -C "$TMP_DIR/mixed-seed" add README.md domain ip
git -C "$TMP_DIR/mixed-seed" commit -m "chore: publish surge artifacts [generation 999-9 source ${SOURCE_SHA}]" >/dev/null
git -C "$TMP_DIR/mixed-seed" push --force origin surge >/dev/null 2>&1

set +e
mixed_output="$(run_restore "$TMP_DIR/restored-mixed" "$TMP_DIR/baseline-mixed.json" 2>&1)"
mixed_status=$?
set -e
[ "$mixed_status" -ne 0 ] || {
  echo "test failed: inconsistent cohort was accepted" >&2
  exit 1
}
grep -F "restored branches are from inconsistent publications" <<< "$mixed_output" >/dev/null

# Invalid metadata: a branch subject that does not match the publication
# pattern must be refused by the restore step.
git clone -q "$REMOTE" "$TMP_DIR/bad-seed"
git -C "$TMP_DIR/bad-seed" config user.name test
git -C "$TMP_DIR/bad-seed" config user.email test@example.com
git -C "$TMP_DIR/bad-seed" checkout --orphan surge >/dev/null 2>&1
git -C "$TMP_DIR/bad-seed" rm -rf . >/dev/null 2>&1 || true
mkdir -p "$TMP_DIR/bad-seed/domain" "$TMP_DIR/bad-seed/ip"
printf 'DOMAIN-SUFFIX,surge.example\n' > "$TMP_DIR/bad-seed/domain/test.list"
printf 'IP-CIDR,198.51.100.0/24,no-resolve\n' > "$TMP_DIR/bad-seed/ip/test.list"
printf 'bad\n' > "$TMP_DIR/bad-seed/README.md"
git -C "$TMP_DIR/bad-seed" add README.md domain ip
git -C "$TMP_DIR/bad-seed" commit -m "not a publication commit" >/dev/null
git -C "$TMP_DIR/bad-seed" push --force origin surge >/dev/null 2>&1

set +e
bad_output="$(run_restore "$TMP_DIR/restored-bad" "$TMP_DIR/baseline-bad.json" 2>&1)"
bad_status=$?
set -e
[ "$bad_status" -ne 0 ] || {
  echo "test failed: branch without publication metadata was accepted" >&2
  exit 1
}
grep -F "origin/surge lacks valid generation/source publication metadata" <<< "$bad_output" >/dev/null

echo "published artifact restore tests passed"
