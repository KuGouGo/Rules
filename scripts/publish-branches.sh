#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

publish_branch() {
  local branch="$1"
  local domain_dir="$2"
  local ip_dir="$3"
  local tmpdir

  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null

  git init -q
  git checkout --orphan "$branch" >/dev/null 2>&1

  mkdir -p domain ip
  cp -R "$ROOT/$domain_dir"/. domain/
  cp -R "$ROOT/$ip_dir"/. ip/

  git add domain ip
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git commit -m "chore: publish ${branch} artifacts" >/dev/null
  git remote add origin "$(git -C "$ROOT" remote get-url origin)"
  git push -f origin HEAD:"$branch"

  popd >/dev/null
  rm -rf "$tmpdir"
}

publish_branch surge domain/surge ip/surge
publish_branch sing-box domain/sing-box ip/sing-box
publish_branch mihomo domain/mihomo ip/mihomo
