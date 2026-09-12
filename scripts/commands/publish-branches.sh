#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/scripts/commands/check-runtime.sh"

DRY_RUN="${PUBLISH_DRY_RUN:-0}"
ARTIFACT_ROOT="${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
SOURCE_SHA="${ARTIFACT_SOURCE_SHA:-$(git -C "$ROOT" rev-parse HEAD)}"
CAPABILITY_REGISTRY="$(python3 "$ROOT/scripts/tools/platform_capabilities.py" shell-registry)"

branch_readme() {
  local branch="$1"
  local template="$ROOT/templates/branch-readmes/${branch}.md"

  if [ ! -f "$template" ]; then
    echo "missing publish README template: $template" >&2
    exit 1
  fi

  python3 "$ROOT/scripts/tools/render-branch-readme.py" \
    --platform "$branch" \
    --artifact-root "$ARTIFACT_ROOT" \
    --template "$template" \
    --output README.md
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
    echo "hint: run the build pipeline first to populate .output before publishing" >&2
    exit 1
  fi
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
  local file rel file_list
  file_list="$(mktemp)"
  find domain ip -type f -print0 > "$file_list"

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
  done < "$file_list"
  rm -f "$file_list"
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
  copy_artifacts "$domain_dir" domain "$domain_extensions"
  copy_artifacts "$ip_dir" ip "$ip_extensions"
  branch_readme "$branch"
  assert_branch_layout "$domain_extensions" "$ip_extensions"

  git add README.md domain ip
  local_tree="$(git write-tree)"
  remote_tree="$(git -C "$ROOT" rev-parse --verify "origin/$branch^{tree}" 2>/dev/null || true)"
  remote_commit="$(git -C "$ROOT" rev-parse --verify "origin/$branch^{commit}" 2>/dev/null || true)"

  if [ -n "$remote_tree" ] && [ "$local_tree" = "$remote_tree" ]; then
    echo "$branch artifact tree unchanged"
  else
    PUBLISH_COHORT_CHANGED=1
    echo "$branch artifact tree changed"
  fi

  commit="$(git commit-tree "$local_tree" -m "chore: publish ${branch} artifacts [source ${SOURCE_SHA}]")"
  git update-ref "refs/heads/$branch" "$commit"
  queue_publish_ref "$branch" "$commit" "$remote_commit"

  if [ "$DRY_RUN" = "1" ]; then
    echo "=== ${branch} publish dry-run ==="
    echo "domain files: $(find domain -maxdepth 1 -type f | wc -l | tr -d ' ')"
    echo "ip files: $(find ip -maxdepth 1 -type f | wc -l | tr -d ' ')"
  fi
}

publish_queued_refs() {
  local remote_url branch commit remote_commit refspec
  local -a refspecs=() leases=() names=()

  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi

  if [ "$PUBLISH_COHORT_CHANGED" -eq 0 ]; then
    echo "all publish branches unchanged, skip push"
    return 0
  fi

  if [ ! -s "$PUBLISH_QUEUE_FILE" ]; then
    echo "publish cohort changed but no refs were prepared" >&2
    return 1
  fi

  remote_url="$(git -C "$ROOT" remote get-url origin)"
  git remote add origin "$remote_url"
  if [[ "$remote_url" == https://github.com/* ]] && [ -n "${GITHUB_TOKEN:-}" ]; then
    basic_token="$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
    git config "http.${remote_url}/.extraheader" "AUTHORIZATION: basic ${basic_token}"
  fi

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

  if [ "${#names[@]}" -ne "${#PUBLISH_BRANCH_NAMES[@]}" ]; then
    echo "publish cohort incomplete: got ${#names[@]} branches (${names[*]:-none}), expected ${#PUBLISH_BRANCH_NAMES[@]} (${PUBLISH_BRANCH_NAMES[*]})" >&2
    return 1
  fi
  for expected in "${PUBLISH_BRANCH_NAMES[@]}"; do
    case " ${names[*]} " in
      *" $expected "*) ;;
      *)
        echo "publish cohort missing branch: $expected" >&2
        return 1
        ;;
    esac
  done

  echo "publishing branches atomically: ${names[*]}"
  git push --atomic "${leases[@]}" origin "${refspecs[@]}"
}

PUBLISH_TMPDIR="$(mktemp -d)"
PUBLISH_QUEUE_FILE="$PUBLISH_TMPDIR/publish-queue.tsv"
PUBLISH_WORKTREE="$PUBLISH_TMPDIR/worktree"
PUBLISH_COHORT_CHANGED=0
trap 'cleanup_tempdir "$PUBLISH_TMPDIR"' EXIT HUP INT TERM

mkdir -p "$PUBLISH_WORKTREE"
cd "$PUBLISH_WORKTREE"
git init -q
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
mkdir -p .git/objects/info
git -C "$ROOT" rev-parse --path-format=absolute --git-path objects > .git/objects/info/alternates

git -C "$ROOT" fetch -q origin '+refs/heads/*:refs/remotes/origin/*'

# A retried workflow must publish only artifacts built from current main.
current_main_sha="$(git -C "$ROOT" rev-parse --verify 'origin/main^{commit}')"
if [ "$SOURCE_SHA" != "$current_main_sha" ]; then
  echo "refusing stale publication: source=${SOURCE_SHA}, current main=${current_main_sha}" >&2
  exit 1
fi

declare -A PUBLISH_BRANCH PUBLISH_DOMAIN_EXTENSION PUBLISH_IP_EXTENSION
declare -a PUBLISH_BRANCH_NAMES=()
while IFS=$'\t' read -r platform _public_name branch section extension _format _compiler; do
  if [ -z "${PUBLISH_BRANCH[$platform]:-}" ]; then
    PUBLISH_BRANCH["$platform"]="$branch"
    PUBLISH_BRANCH_NAMES+=("$branch")
  fi
  if [ "$section" = domain ]; then
    PUBLISH_DOMAIN_EXTENSION["$platform"]="$extension"
  else
    PUBLISH_IP_EXTENSION["$platform"]="$extension"
  fi
done <<< "$CAPABILITY_REGISTRY"

while IFS=$'\t' read -r platform _public_name _branch section _extension _format _compiler; do
  [ "$section" = ip ] || continue
  prepare_branch \
    "${PUBLISH_BRANCH[$platform]}" \
    "domain/$platform" \
    "ip/$platform" \
    "${PUBLISH_DOMAIN_EXTENSION[$platform]}" \
    "${PUBLISH_IP_EXTENSION[$platform]}"
done <<< "$CAPABILITY_REGISTRY"
publish_queued_refs
