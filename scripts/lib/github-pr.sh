#!/usr/bin/env bash
# Shared git-push and pull-request helpers for the automation updaters
# (update-tool-versions.sh, update-upstream-pins.sh). Callers source this file
# after their own constants; network calls expect gh/git with GITHUB_TOKEN.

# Push an automation branch, rebasing the remote ref via force-with-lease when
# a stale branch already exists, and setting upstream on first push.
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

# Open one pull request for an automation branch, or update it in place when a
# PR is already open. Repository settings that forbid Actions-created PRs
# degrade to a warning with a manual compare URL instead of failing the run.
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
