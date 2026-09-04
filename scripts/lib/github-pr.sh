#!/usr/bin/env bash

push_automation_branch() {
  local branch="$1"
  local remote_sha
  remote_sha="$(git ls-remote origin "refs/heads/${branch}" | awk 'NR == 1 { print $1 }')"
  if [ -n "$remote_sha" ]; then
    git push -u --force-with-lease="refs/heads/${branch}:${remote_sha}" origin "$branch"
  else
    git push -u origin "$branch"
  fi
}

validate_automation_branch() {
  local branch="$1"
  local head_sha run_id="" runs attempt

  head_sha="$(git rev-parse HEAD)"
  gh workflow run validate.yml --ref "$branch"

  for attempt in {1..12}; do
    runs="$(gh run list --workflow validate.yml --branch "$branch" \
      --event workflow_dispatch --limit 10 --json databaseId,headSha \
      --jq '.[] | select(.headSha == "'"$head_sha"'") | .databaseId')" \
      || continue
    run_id="${runs%%$'\n'*}"
    [ -n "$run_id" ] && break
    echo "waiting for dispatched validation run (${attempt}/12)"
    sleep 5
  done

  [ -n "$run_id" ] || {
    echo "dispatched validation run was not found for ${head_sha}" >&2
    return 1
  }
  echo "waiting for validation run ${run_id} on ${branch}"
  gh run watch "$run_id" --exit-status
}

record_validation_status() {
  local context="$1"
  local description="$2"
  local head_sha repository status_output

  head_sha="$(git rev-parse HEAD)"
  repository="${GITHUB_REPOSITORY:-KuGouGo/Rules}"
  if status_output="$(gh api --method POST "repos/${repository}/statuses/${head_sha}" \
    -f state=success \
    -f context="$context" \
    -f description="$description" \
    -f target_url="${GITHUB_SERVER_URL:-https://github.com}/${repository}/actions/runs/${GITHUB_RUN_ID:-}" \
    2>&1)"; then
    echo "recorded ${context} status on ${head_sha}"
  else
    printf 'failed to record validation status on %s: %s\n' "$head_sha" "$status_output" >&2
    return 1
  fi
}

ensure_automation_pull_request() {
  local branch="$1"
  local title="$2"
  local body="$3"
  local pr_number pr_output compare_url

  pr_number="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)"
  if [ -n "$pr_number" ]; then
    echo "pull request #${pr_number} already open for ${branch}; branch updated"
    return 0
  fi

  if pr_output="$(gh pr create --base main --head "$branch" --title "$title" --body "$body" 2>&1)"; then
    printf '%s\n' "$pr_output"
    return 0
  fi

  if [[ "$pr_output" == *"not permitted to create or approve pull requests"* ]]; then
    compare_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-KuGouGo/Rules}/compare/main...${branch}?expand=1"
    echo "::warning::GitHub Actions cannot create pull requests for this repository; the updated branch was pushed."
    echo "Create the pull request manually: $compare_url"
    return 0
  fi

  printf 'pull request creation failed: %s\n' "$pr_output" >&2
  return 1
}
