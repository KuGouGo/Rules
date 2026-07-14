#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DRY_RUN="${PUBLISH_DRY_RUN:-0}"
ALLOW_REMOTE_FALLBACK="${PUBLISH_ALLOW_REMOTE_FALLBACK:-0}"
ARTIFACT_ROOT="${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
MANIFEST_FILE="$ARTIFACT_ROOT/artifact-manifest.json"
CAPABILITY_REGISTRY="$(python3 "$ROOT/scripts/tools/platform_capabilities.py" shell-registry)"

ARTIFACT_SOURCE_SHA="${ARTIFACT_SOURCE_SHA:-}" "$ROOT/scripts/commands/verify-artifact-manifest.sh"
read -r MANIFEST_GENERATION_ID MANIFEST_SOURCE_SHA < <(
  python3 - <<'PY' "$MANIFEST_FILE"
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
print(manifest["generation_id"], manifest["source"]["commit"] or "unknown")
PY
)

branch_readme() {
  local branch="$1"
  local template="$ROOT/templates/branch-readmes/${branch}.md"

  if [ ! -f "$template" ]; then
    echo "missing publish README template: $template" >&2
    exit 1
  fi

  cp "$template" README.md
}

has_publish_source_artifacts() {
  local src_dir="$1"
  local extensions_csv="$2"
  local -a extensions=()
  local extension

  IFS=',' read -r -a extensions <<< "$extensions_csv"
  for extension in "${extensions[@]}"; do
    if find "$ARTIFACT_ROOT/$src_dir" -maxdepth 1 -type f -name "*.${extension}" -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done

  return 1
}

copy_artifacts() {
  local src_dir="$1"
  local dest_dir="$2"
  local extensions_csv="$3"
  local -a extensions=()
  local extension file copied=0

  IFS=',' read -r -a extensions <<< "$extensions_csv"

  mkdir -p "$dest_dir"
  shopt -s nullglob
  for extension in "${extensions[@]}"; do
    for file in "$ARTIFACT_ROOT/$src_dir"/*."$extension"; do
      cp "$file" "$dest_dir/"
      copied=1
    done
  done
  shopt -u nullglob

  if [ "$copied" -eq 0 ]; then
    echo "no supported artifacts found in $src_dir ($extensions_csv)" >&2
    exit 1
  fi
}

restore_remote_publish_side() {
  local branch="$1"
  local side="$2"
  local extensions_csv="$3"
  local dest_dir="$4"
  local tree_path="$side"
  local -a extensions=()
  local extension restored=0
  local file_path rel_name

  IFS=',' read -r -a extensions <<< "$extensions_csv"
  mkdir -p "$dest_dir"

  if ! git -C "$ROOT" rev-parse --verify "origin/$branch^{commit}" >/dev/null 2>&1; then
    return 1
  fi

  while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    rel_name="${file_path#"${tree_path}"/}"
    mkdir -p "$dest_dir/$(dirname "$rel_name")"
    if git -C "$ROOT" show "origin/$branch:$file_path" > "$dest_dir/$rel_name"; then
      restored=1
    else
      rm -f "$dest_dir/$rel_name"
      return 1
    fi
  done < <(
    for extension in "${extensions[@]}"; do
      git -C "$ROOT" ls-tree -r --name-only "origin/$branch" -- "$tree_path" 2>/dev/null | grep -E "\\.${extension}$" || true
    done
  )

  [ "$restored" -eq 1 ]
}

prepare_publish_side() {
  local branch="$1"
  local src_dir="$2"
  local side="$3"
  local extensions_csv="$4"
  local dest_dir="$5"

  if has_publish_source_artifacts "$src_dir" "$extensions_csv"; then
    copy_artifacts "$src_dir" "$dest_dir" "$extensions_csv"
    return 0
  fi

  if [ "$ALLOW_REMOTE_FALLBACK" != "1" ]; then
    echo "publish source missing artifacts: $ARTIFACT_ROOT/$src_dir (expected: $extensions_csv)" >&2
    echo "hint: run the build pipeline first to populate .output before publishing" >&2
    echo "hint: set PUBLISH_ALLOW_REMOTE_FALLBACK=1 to explicitly allow origin/$branch:$side fallback" >&2
    exit 1
  fi

  echo "publish source missing local artifacts for $src_dir; attempting fallback from origin/$branch:$side" >&2
  if restore_remote_publish_side "$branch" "$side" "$extensions_csv" "$dest_dir"; then
    echo "restored $side artifacts from origin/$branch baseline" >&2
    return 0
  fi

  echo "publish source missing artifacts: $ARTIFACT_ROOT/$src_dir (expected: $extensions_csv)" >&2
  echo "hint: run the build pipeline first to populate .output before publishing" >&2
  echo "hint: or ensure origin/$branch contains baseline $side artifacts for fallback restore" >&2
  exit 1
}

has_allowed_extension() {
  local file="$1"
  local extensions_csv="$2"
  local -a extensions=()
  local extension

  IFS=',' read -r -a extensions <<< "$extensions_csv"
  for extension in "${extensions[@]}"; do
    [[ "$file" == *."$extension" ]] && return 0
  done

  return 1
}

assert_branch_layout() {
  local domain_extensions="$1"
  local ip_extensions="$2"
  local file rel

  [ -f "README.md" ] || {
    echo "missing publish file: README.md" >&2
    exit 1
  }

  while IFS= read -r -d '' file; do
    rel="${file#./}"
    if [[ "$rel" == domain/* ]]; then
      has_allowed_extension "$rel" "$domain_extensions" || {
        echo "unexpected file in publish tree: $rel" >&2
        exit 1
      }
      continue
    fi
    if [[ "$rel" == ip/* ]]; then
      has_allowed_extension "$rel" "$ip_extensions" || {
        echo "unexpected file in publish tree: $rel" >&2
        exit 1
      }
      continue
    fi
    echo "unexpected file in publish tree: $rel" >&2
    exit 1
  done < <(find domain ip -type f -print0)
}

cleanup_tempdir() {
  local tempdir="$1"
  [ -n "$tempdir" ] && rm -rf "$tempdir"
}

reset_publish_worktree() {
  local branch="$1"

  git checkout --orphan "$branch" >/dev/null 2>&1
  git rm -rf . >/dev/null 2>&1 || true
  find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
}

queue_publish_ref() {
  local branch="$1"
  local commit="$2"
  local remote_commit="$3"

  printf '%s\t%s\t%s\n' "$branch" "$commit" "$remote_commit" >> "$PUBLISH_QUEUE_FILE"
}

prepare_branch() {
  local branch="$1"
  local domain_dir="$2"
  local ip_dir="$3"
  local domain_extensions="$4"
  local ip_extensions="$5"
  local local_tree remote_tree remote_commit commit

  reset_publish_worktree "$branch"
  prepare_publish_side "$branch" "$domain_dir" domain "$domain_extensions" domain
  prepare_publish_side "$branch" "$ip_dir" ip "$ip_extensions" ip
  branch_readme "$branch"
  assert_branch_layout "$domain_extensions" "$ip_extensions"

  git add README.md domain ip
  local_tree="$(git write-tree)"
  remote_tree="$(git -C "$ROOT" rev-parse --verify "origin/$branch^{tree}" 2>/dev/null || true)"

  if [ -n "$remote_tree" ] && [ "$local_tree" = "$remote_tree" ]; then
    echo "$branch artifacts unchanged, skip publish"
    return 0
  fi

  git commit -m "chore: publish ${branch} artifacts [generation ${MANIFEST_GENERATION_ID} source ${MANIFEST_SOURCE_SHA}]" >/dev/null
  commit="$(git rev-parse HEAD)"
  remote_commit="$(git -C "$ROOT" rev-parse --verify "origin/$branch^{commit}" 2>/dev/null || true)"

  if [ "$DRY_RUN" = "1" ]; then
    echo "=== ${branch} publish dry-run ==="
    echo "domain files: $(find domain -maxdepth 1 -type f | wc -l | tr -d ' ')"
    echo "ip files: $(find ip -maxdepth 1 -type f | wc -l | tr -d ' ')"
    return 0
  fi

  queue_publish_ref "$branch" "$commit" "$remote_commit"
}

publish_queued_refs() {
  local remote_url branch commit remote_commit refspec lease
  local -a refspecs=()
  local -a leases=()
  local -a names=()

  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi

  if [ ! -s "$PUBLISH_QUEUE_FILE" ]; then
    echo "all publish branches unchanged, skip push"
    return 0
  fi

  remote_url="$(git -C "$ROOT" remote get-url origin)"
  if [[ "$remote_url" == https://github.com/* ]] && [ -n "${GITHUB_TOKEN:-}" ]; then
    remote_url="https://x-access-token:${GITHUB_TOKEN}@${remote_url#https://}"
  fi
  git remote add origin "$remote_url"

  git ls-remote --exit-code origin HEAD >/dev/null

  while IFS=$'\t' read -r branch commit remote_commit; do
    [ -n "$branch" ] || continue
    refspec="${commit}:refs/heads/${branch}"
    if [ -n "$remote_commit" ]; then
      lease="--force-with-lease=refs/heads/${branch}:${remote_commit}"
    else
      lease="--force-with-lease=refs/heads/${branch}:"
    fi
    refspecs+=("$refspec")
    leases+=("$lease")
    names+=("$branch")
  done < "$PUBLISH_QUEUE_FILE"

  echo "publishing branches atomically: ${names[*]}"
  git push --atomic "${leases[@]}" origin "${refspecs[@]}"
}

PUBLISH_TMPDIR="$(mktemp -d)"
PUBLISH_QUEUE_FILE="$PUBLISH_TMPDIR/publish-queue.tsv"
PUBLISH_WORKTREE="$PUBLISH_TMPDIR/worktree"
trap 'cleanup_tempdir "$PUBLISH_TMPDIR"' EXIT

mkdir -p "$PUBLISH_WORKTREE"
cd "$PUBLISH_WORKTREE"
git init -q
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

declare -A PUBLISH_BRANCH PUBLISH_DOMAIN_EXTENSION PUBLISH_IP_EXTENSION
while IFS=$'\t' read -r platform _public_name branch section extension _format _empty _compiler _verifier; do
  PUBLISH_BRANCH["$platform"]="$branch"
  if [ "$section" = domain ]; then
    PUBLISH_DOMAIN_EXTENSION["$platform"]="$extension"
  else
    PUBLISH_IP_EXTENSION["$platform"]="$extension"
  fi
done <<< "$CAPABILITY_REGISTRY"

while IFS=$'\t' read -r platform _public_name _branch section _extension _format _empty _compiler _verifier; do
  [ "$section" = ip ] || continue
  prepare_branch \
    "${PUBLISH_BRANCH[$platform]}" \
    "domain/$platform" \
    "ip/$platform" \
    "${PUBLISH_DOMAIN_EXTENSION[$platform]}" \
    "${PUBLISH_IP_EXTENSION[$platform]}"
done <<< "$CAPABILITY_REGISTRY"
publish_queued_refs
