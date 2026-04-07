#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARTIFACT_ROOT="$ROOT/.output"
TMP_ROOT="$ROOT/.tmp/restore-published"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

fetch_branch_ref() {
  local branch="$1"
  git fetch --depth=1 origin "${branch}:refs/remotes/origin/${branch}" >/dev/null 2>&1
}

restore_branch_artifacts() {
  local branch="$1"
  local tmpdir="$TMP_ROOT/$branch"

  mkdir -p "$tmpdir"
  fetch_branch_ref "$branch"
  git archive "origin/$branch" domain ip README.md | tar -xf - -C "$tmpdir"

  rm -rf "$ARTIFACT_ROOT/domain/$branch" "$ARTIFACT_ROOT/ip/$branch"
  mkdir -p "$ARTIFACT_ROOT/domain/$branch" "$ARTIFACT_ROOT/ip/$branch"

  cp -R "$tmpdir/domain/." "$ARTIFACT_ROOT/domain/$branch/"
  cp -R "$tmpdir/ip/." "$ARTIFACT_ROOT/ip/$branch/"

  echo "restored $branch artifacts"
}

mkdir -p "$ARTIFACT_ROOT"

restore_branch_artifacts surge
restore_branch_artifacts sing-box
restore_branch_artifacts mihomo

echo "published artifact restore done"
