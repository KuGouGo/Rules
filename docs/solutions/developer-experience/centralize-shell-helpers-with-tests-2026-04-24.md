---
title: Centralize Shell Helpers With Focused Utility Tests
date: 2026-04-24
last_updated: 2026-04-24
category: docs/solutions/developer-experience
module: Rules automation scripts
problem_type: developer_experience
component: development_workflow
severity: low
applies_when:
  - Refactoring duplicated shell helpers shared by validation and build scripts
  - Adding maintainability improvements to automation-heavy repositories
  - Introducing shared sourced libraries in scripts that run under CI
related_components:
  - tooling
  - testing_framework
tags: [shell, ci, maintainability, automation, tests]
---

# Centralize Shell Helpers With Focused Utility Tests

## Context

The Rules repository had duplicated `.list` file discovery logic in both `scripts/build-custom.sh` and `scripts/lint-custom-rules.sh`. The same behavior was implemented with inline Python in multiple scripts, making future maintenance harder and increasing the chance that validation and build paths would drift.

During the maintainability pass, the duplicated logic was moved into `scripts/lib/common.sh` as `list_files_by_extension` and `list_rule_files`, and a focused test file `scripts/test-shell-utils.sh` was added. The CI workflow now runs this utility test alongside shellcheck, custom rule linting, and domain parsing tests.

## Guidance

During the same session, the repo was cloned with `gh repo clone KuGouGo/Rules`, inspected with `rg`, `sed`, and `wc`, and then improved through a plan/work/review/compound loop. The session history shows two useful operational details: the first `ce-setup` health check hung when `npx skills list --global --json` was allowed to run, and the workaround was to mask `npx` for health-check verification; later, `scripts/build-custom.sh` initially failed because `sing-box` was not cached and release resolution needed network access, then passed after an escalated run downloaded the tools. (session history)

When consolidating shell helper logic:

1. Move only the smallest stable behavior first.
2. Add focused tests that lock the helper contract before larger refactors.
3. Keep shared sourced libraries as close to side-effect free as possible.
4. Wire new tests into CI immediately so future helper changes are guarded.
5. Run both fast validation and the closest behavioral script that consumes the helper.

For this repo, the safe first slice was sorted `.list` discovery:

```bash
list_files_by_extension() {
  local dir="$1"
  local extension="$2"

  if [ ! -d "$dir" ]; then
    return 0
  fi

  find "$dir" -maxdepth 1 -type f -name "*.${extension}" | sort
}

list_rule_files() {
  list_files_by_extension "$1" list
}
```

The test covers the behavior the callers depend on:

- sorted output
- `.list` files only
- nested directories ignored
- missing directories returning an empty result
- existing shared helpers such as `write_if_changed` and `normalize_version`

## Why This Matters

Automation repositories often accumulate large shell scripts because they start as glue code and gradually absorb business rules. Small duplicated helpers are a good first refactor target because they reduce drift without changing generated artifact semantics.

The important trap is that shell libraries can have side effects when sourced. In this repo, `scripts/lib/common.sh` initially initialized `.bin/` and mutated `PATH` at source time. That is acceptable for build scripts that need cached tools, but it is surprising for lint-only scripts that only need file discovery. The cleanup split tool-cache setup into an explicit `setup_tool_cache` function so validation scripts can source helper functions without creating `.bin/` or altering `PATH`.

The session also surfaced an important review pattern: successful validation is not enough if a refactor changes the side-effect profile of a read-only command. `scripts/lint-custom-rules.sh` still passed, but sourcing `scripts/lib/common.sh` made lint create `.bin/` and alter `PATH`. Treat those side effects as follow-up debt even when tests are green; in this case the debt was resolved by making `setup_tool_cache` explicit and idempotent. (session history)

## When to Apply

- A validation script and a build script implement the same file traversal or normalization helper.
- A CI pipeline depends on shell helper behavior that is not directly tested.
- A repository has generated artifacts where semantic changes are risky, so refactors need characterization coverage.
- Shared shell libraries are being introduced or expanded.

## Examples

Good first step:

```bash
source "$ROOT/scripts/lib/common.sh"
DOMAIN_RULE_FILES="$(list_rule_files "$CUSTOM_DOMAIN_DIR")"
IP_RULE_FILES="$(list_rule_files "$CUSTOM_IP_DIR")"
```

Good CI follow-up:

```yaml
- name: Test shell utilities
  run: ./scripts/test-shell-utils.sh
```

Pattern used to avoid hidden side effects:

```bash
setup_tool_cache() {
  mkdir -p "$BIN_DIR"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) export PATH="$BIN_DIR:$PATH" ;;
  esac
}
```

Call `setup_tool_cache` only from scripts that download or execute cached tools, not from lint-only scripts. Add a utility test that proves sourcing the library alone does not create `.bin/` or mutate `PATH`.

## Related

- Codex session `019dbdbd-be46-70f1-a10d-a230605972f3` on 2026-04-24 (session history)
- `docs/plans/maintainability-automation-plan.md`
- `scripts/lib/common.sh`
- `scripts/test-shell-utils.sh`
- `.github/workflows/build.yml`
