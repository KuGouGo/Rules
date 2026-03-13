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
  trap 'rm -rf "$tmpdir"' RETURN

  git worktree add --detach "$tmpdir" >/dev/null 2>&1
  pushd "$tmpdir" >/dev/null

  git checkout --orphan "$branch" 2>/dev/null || git checkout "$branch"

  find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  mkdir -p domain ip
  cp -R "$ROOT/$domain_dir"/. domain/
  cp -R "$ROOT/$ip_dir"/. ip/

  cat > README.md <<EOF
# ${branch}

Published artifacts for ${branch}.
EOF

  git add README.md domain ip
  if git diff --cached --quiet; then
    echo "no changes for $branch"
  else
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git commit -m "chore: publish ${branch} artifacts" >/dev/null
    git push -f origin HEAD:"$branch"
  fi

  popd >/dev/null
  git worktree remove "$tmpdir" --force >/dev/null 2>&1
}

publish_branch surge domain/surge ip/surge
publish_branch sing-box domain/sing-box ip/sing-box
publish_branch mihomo domain/mihomo ip/mihomo
