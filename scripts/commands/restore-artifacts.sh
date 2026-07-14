#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ -z "${RULES_ARTIFACT_ROOT:-}" ]; then
  RULES_BUILD_SCOPE=custom exec "$ROOT/scripts/commands/build-artifacts-transaction.sh"
fi

ARTIFACT_ROOT="${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
TMP_ROOT="$ROOT/.tmp/restore-published"
RESTORE_METADATA_FILE="$TMP_ROOT/restored-branches.tsv"
ALLOW_LOSSY_FALLBACK="${RULES_ALLOW_LOSSY_RESTORE_FALLBACK:-0}"

inject_restore_failure() {
  local point="$1"
  if [ "${RULES_RESTORE_FAIL_AT:-}" = "$point" ]; then
    echo "injected artifact restore failure at $point" >&2
    return 1
  fi
}

# shellcheck source=scripts/lib/rules.sh
source "$ROOT/scripts/lib/rules.sh"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
: > "$RESTORE_METADATA_FILE"
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
    if [ "$ALLOW_LOSSY_FALLBACK" != "1" ]; then
      echo "required remote branch origin/$branch not found; lossy cross-platform fallback is disabled" >&2
      return 1
    fi
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

  local commit subject generation source
  commit="$(git rev-parse "origin/$branch^{commit}")"
  subject="$(git log -1 --format=%s "origin/$branch")"
  generation="$(printf '%s' "$subject" | grep -oE '\[generation [^ ]+' | cut -d' ' -f2 || true)"
  source="$(printf '%s' "$subject" | grep -oE 'source [0-9a-f]{40}\]' | cut -d' ' -f2 | tr -d ']' || true)"
  [ -n "$generation" ] && [ -n "$source" ] || {
    echo "origin/$branch lacks required generation/source publication metadata" >&2
    return 1
  }
  printf '%s\t%s\t%s\t%s\n' "$branch" "$commit" "$generation" "$source" >> "$RESTORE_METADATA_FILE"
  echo "restored $branch artifacts at $commit (generation $generation, source $source)"
}

mkdir -p "$ARTIFACT_ROOT"

restore_branch_artifacts surge
restore_branch_artifacts quanx
restore_branch_artifacts egern
inject_restore_failure late-text
restore_branch_artifacts sing-box
restore_branch_artifacts mihomo
inject_restore_failure late-binary

python3 - <<'PY' "$RESTORE_METADATA_FILE" "$ARTIFACT_ROOT/restoration-metadata.json"
import json, sys
from pathlib import Path
rows = [line.split("\t") for line in Path(sys.argv[1]).read_text().splitlines() if line]
if len(rows) != 5:
    raise SystemExit(f"restoration identity incomplete: expected 5 branch records, got {len(rows)}")
generations = {row[2] for row in rows}; sources = {row[3] for row in rows}
if len(generations) != 1 or len(sources) != 1:
    raise SystemExit(f"restored branches are from inconsistent publications: generations={sorted(generations)}, sources={sorted(sources)}")
payload = {"generation_id": next(iter(generations)), "source_commit": next(iter(sources)),
           "branches": {row[0]: {"commit": row[1]} for row in rows}}
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

python3 - <<'PY' "$ARTIFACT_ROOT" "$ARTIFACT_ROOT/artifact-origins.json"
import json, sys
from pathlib import Path
root, target = map(Path, sys.argv[1:])
origins = {}
for section in ("domain", "ip"):
    base = root / section
    if base.is_dir():
        for path in base.glob("*/*"):
            if path.is_file():
                origins[path.relative_to(root).as_posix()] = "restored-published-branch"
target.write_text(json.dumps(origins, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "published artifact restore done"
