#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/scripts/commands/check-runtime.sh"
PUBLISH_GIT_ROOT="$ROOT"
# shellcheck source=scripts/lib/baseline.sh
source "$ROOT/scripts/lib/baseline.sh"

DRY_RUN="${PUBLISH_DRY_RUN:-0}"
ARTIFACT_ROOT="${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
MANIFEST_FILE="$ARTIFACT_ROOT/artifact-manifest.json"
CAPABILITY_REGISTRY="$(python3 "$ROOT/scripts/tools/platform_capabilities.py" shell-registry)"

ARTIFACT_SOURCE_SHA="${ARTIFACT_SOURCE_SHA:-}" "$ROOT/scripts/commands/verify-artifact-manifest.sh"
manifest_identity="$(python3 - <<'PY' "$MANIFEST_FILE"
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
print(
    manifest["generation_id"],
    manifest["source"]["commit"] or "unknown",
    manifest["baseline"]["status"],
    manifest["baseline"]["source_commit"] or "-",
)
PY
)"
read -r MANIFEST_GENERATION_ID MANIFEST_SOURCE_SHA MANIFEST_BASELINE_STATUS MANIFEST_BASELINE_SOURCE <<< "$manifest_identity"

refresh_and_validate_remote_baseline() {
  local metadata_file
  metadata_file="$(mktemp)"

  if ! fetch_publish_branch_metadata "$metadata_file"; then
    rm -f "$metadata_file"
    return 1
  fi
  if ! assert_remote_baseline_matches_manifest "$metadata_file" "$MANIFEST_FILE"; then
    rm -f "$metadata_file"
    return 1
  fi
  rm -f "$metadata_file"
}

assert_candidate_advances_baseline() {
  if [ "$MANIFEST_BASELINE_STATUS" = "consistent" ]; then
    if ! git -C "$ROOT" cat-file -e "${MANIFEST_BASELINE_SOURCE}^{commit}" 2>/dev/null; then
      echo "published baseline source $MANIFEST_BASELINE_SOURCE is unavailable locally; skipping ancestry check" >&2
    elif ! git -C "$ROOT" merge-base --is-ancestor \
      "$MANIFEST_BASELINE_SOURCE" "$MANIFEST_SOURCE_SHA"; then
      echo "stale publication source refused: candidate $MANIFEST_SOURCE_SHA does not descend from baseline $MANIFEST_BASELINE_SOURCE" >&2
      return 1
    fi
  fi

  python3 - "$MANIFEST_FILE" <<'PY'
import json
import re
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
candidate = manifest["generation_id"]
pattern = re.compile(r"([0-9]+)-([0-9]+)")
candidate_match = pattern.fullmatch(candidate)
if candidate_match is None:
    raise SystemExit("candidate publication generation must use <run-id>-<attempt>")
candidate_order = tuple(map(int, candidate_match.groups()))
for branch, item in manifest["baseline"]["branches"].items():
    baseline = item["generation_id"]
    if baseline is None:
        continue
    baseline_match = pattern.fullmatch(baseline)
    if baseline_match is None:
        raise SystemExit(f"baseline generation is invalid for {branch}: {baseline}")
    if candidate_order <= tuple(map(int, baseline_match.groups())):
        raise SystemExit(
            f"stale publication generation refused: candidate {candidate} "
            f"is not newer than {branch} baseline {baseline}"
        )
PY
}

assert_remote_main_tip() {
  local remote_main
  remote_main="$(git -C "$ROOT" ls-remote --exit-code origin refs/heads/main | awk 'NR == 1 {print $1}')"
  if [ "$remote_main" != "$MANIFEST_SOURCE_SHA" ]; then
    echo "stale publication source refused: remote main is $remote_main, candidate is $MANIFEST_SOURCE_SHA" >&2
    return 1
  fi
}

assert_remote_main_tip
refresh_and_validate_remote_baseline
assert_candidate_advances_baseline

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

prepare_publish_side() {
  local src_dir="$1"
  local extensions_csv="$2"
  local dest_dir="$3"

  if has_publish_source_artifacts "$src_dir" "$extensions_csv"; then
    copy_artifacts "$src_dir" "$dest_dir" "$extensions_csv"
    return 0
  fi

  echo "publish source missing artifacts: $ARTIFACT_ROOT/$src_dir (expected: $extensions_csv)" >&2
  echo "hint: run the build pipeline first to populate .output before publishing" >&2
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

create_publish_commit() {
  local branch="$1"
  local tree="$2"
  local remote_commit="$3"
  local message commit

  message="chore: publish ${branch} artifacts [generation ${MANIFEST_GENERATION_ID} source ${MANIFEST_SOURCE_SHA}]"
  commit="$(git commit-tree "$tree" -m "$message")"
  git update-ref "refs/heads/$branch" "$commit"
  printf '%s' "$commit"
}

prepare_branch() {
  local branch="$1"
  local domain_dir="$2"
  local ip_dir="$3"
  local domain_extensions="$4"
  local ip_extensions="$5"
  local local_tree remote_tree remote_commit commit

  reset_publish_worktree "$branch"
  prepare_publish_side "$domain_dir" "$domain_extensions" domain
  prepare_publish_side "$ip_dir" "$ip_extensions" ip
  branch_readme "$branch"
  assert_branch_layout "$domain_extensions" "$ip_extensions"

  git add README.md domain ip
  local_tree="$(git write-tree)"
  remote_tree="$(git -C "$ROOT" rev-parse --verify "origin/$branch^{tree}" 2>/dev/null || true)"
  remote_commit="$(git -C "$ROOT" rev-parse --verify "origin/$branch^{commit}" 2>/dev/null || true)"

  if [ -z "$remote_tree" ] || [ "$local_tree" != "$remote_tree" ]; then
    PUBLISH_COHORT_CHANGED=1
    echo "$branch artifact tree changed"
  else
    echo "$branch artifact tree unchanged; cohort metadata commit prepared"
  fi

  commit="$(create_publish_commit "$branch" "$local_tree" "$remote_commit")"
  queue_publish_ref "$branch" "$commit" "$remote_commit"

  if [ "$DRY_RUN" = "1" ]; then
    echo "=== ${branch} publish dry-run ==="
    echo "domain files: $(find domain -maxdepth 1 -type f | wc -l | tr -d ' ')"
    echo "ip files: $(find ip -maxdepth 1 -type f | wc -l | tr -d ' ')"
    return 0
  fi
}

publish_queued_refs() {
  local remote_url branch commit remote_commit refspec lease
  local -a refspecs=()
  local -a leases=()
  local -a names=()

  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi

  assert_remote_main_tip
  refresh_and_validate_remote_baseline

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
  if ! assert_remote_main_tip; then
    echo "artifact cohort was published while main advanced; this run is failed intentionally and the queued current-main run must roll forward" >&2
    return 1
  fi
}

PUBLISH_TMPDIR="$(mktemp -d)"
PUBLISH_QUEUE_FILE="$PUBLISH_TMPDIR/publish-queue.tsv"
PUBLISH_WORKTREE="$PUBLISH_TMPDIR/worktree"
trap 'cleanup_tempdir "$PUBLISH_TMPDIR"' EXIT HUP INT TERM

mkdir -p "$PUBLISH_WORKTREE"
cd "$PUBLISH_WORKTREE"
git init -q
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
mkdir -p .git/objects/info
git -C "$ROOT" rev-parse --path-format=absolute --git-path objects > .git/objects/info/alternates

if [ "$MANIFEST_BASELINE_STATUS" = "consistent" ] \
  && git -C "$ROOT" cat-file -e "${MANIFEST_BASELINE_SOURCE}^{commit}" 2>/dev/null; then
  PUBLISH_COHORT_CHANGED=0
else

  PUBLISH_COHORT_CHANGED=1
fi

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
