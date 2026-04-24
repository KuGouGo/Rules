#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ARTIFACT_ROOT="$ROOT/.output"
TMP_ROOT="$ROOT/.tmp/restore-published"

source "$ROOT/scripts/lib/rules.sh"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

remote_branch_exists() {
  local branch="$1"
  git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
}

fetch_branch_ref() {
  local branch="$1"
  git fetch --depth=1 origin "+${branch}:refs/remotes/origin/${branch}" >/dev/null 2>&1
}

generate_quanx_from_restored_surge() {
  local domain_src="$ARTIFACT_ROOT/domain/surge"
  local ip_src="$ARTIFACT_ROOT/ip/surge"
  local domain_dst="$ARTIFACT_ROOT/domain/quanx"
  local ip_dst="$ARTIFACT_ROOT/ip/quanx"
  local tmpdir="$TMP_ROOT/quanx-fallback"
  local list base domain_tmp plain_tmp ip_tmp

  if [ ! -d "$domain_src" ] || [ ! -d "$ip_src" ]; then
    echo "cannot build quanx fallback without restored surge artifacts" >&2
    return 1
  fi

  rm -rf "$domain_dst" "$ip_dst" "$tmpdir"
  mkdir -p "$domain_dst" "$ip_dst" "$tmpdir"

  for list in "$domain_src"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    domain_tmp="$tmpdir/$base.domain.tmp"
    render_quanx_domain_ruleset_from_rules "$list" "$domain_tmp" "$base"
    mv "$domain_tmp" "$domain_dst/$base.list"
  done

  for list in "$ip_src"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    plain_tmp="$tmpdir/$base.ip.plain.tmp"
    ip_tmp="$tmpdir/$base.ip.tmp"
    normalize_ip_surge_list_to_plain "$list" "$plain_tmp"
    render_ip_plain_to_quanx_list "$plain_tmp" "$ip_tmp" "$base"
    mv "$ip_tmp" "$ip_dst/$base.list"
  done

  echo "generated quanx fallback artifacts from surge baseline"
}

generate_egern_from_restored_surge() {
  local domain_src="$ARTIFACT_ROOT/domain/surge"
  local ip_src="$ARTIFACT_ROOT/ip/surge"
  local domain_dst="$ARTIFACT_ROOT/domain/egern"
  local ip_dst="$ARTIFACT_ROOT/ip/egern"
  local tmpdir="$TMP_ROOT/egern-fallback"
  local list base domain_tmp plain_tmp ip_tmp

  if [ ! -d "$domain_src" ] || [ ! -d "$ip_src" ]; then
    echo "cannot build egern fallback without restored surge artifacts" >&2
    return 1
  fi

  rm -rf "$domain_dst" "$ip_dst" "$tmpdir"
  mkdir -p "$domain_dst" "$ip_dst" "$tmpdir"

  for list in "$domain_src"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    domain_tmp="$tmpdir/$base.domain.tmp"
    render_egern_domain_ruleset_from_rules "$list" "$domain_tmp"
    mv "$domain_tmp" "$domain_dst/$base.yaml"
  done

  for list in "$ip_src"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    plain_tmp="$tmpdir/$base.ip.plain.tmp"
    ip_tmp="$tmpdir/$base.ip.tmp"
    normalize_ip_surge_list_to_plain "$list" "$plain_tmp"
    render_ip_plain_to_egern_yaml "$plain_tmp" "$ip_tmp"
    mv "$ip_tmp" "$ip_dst/$base.yaml"
  done

  echo "generated egern fallback artifacts from surge baseline"
}

restore_branch_artifacts() {
  local branch="$1"
  local tmpdir="$TMP_ROOT/$branch"

  if ! remote_branch_exists "$branch"; then
    if [ "$branch" = "quanx" ]; then
      echo "origin/quanx not found, building quanx baseline from restored surge artifacts"
      generate_quanx_from_restored_surge
      return 0
    fi
    if [ "$branch" = "egern" ]; then
      echo "origin/egern not found, building egern baseline from restored surge artifacts"
      generate_egern_from_restored_surge
      return 0
    fi
    echo "required remote branch origin/$branch not found" >&2
    return 1
  fi

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
restore_branch_artifacts quanx
restore_branch_artifacts egern
restore_branch_artifacts sing-box
restore_branch_artifacts mihomo

echo "published artifact restore done"
