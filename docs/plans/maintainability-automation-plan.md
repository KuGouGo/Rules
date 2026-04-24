# Rules Maintainability and Automation Plan

## Problem Frame

The repository is a ruleset automation pipeline: custom sources in `sources/custom/**` and upstream network/domain sources are normalized, converted into multiple client formats, guarded, and force-published to format-specific branches by `.github/workflows/build.yml`. The current implementation works, but long-term maintenance risk is concentrated in large shell scripts, duplicated parsing/rendering logic, inline Python/AWK fragments, and GitHub Actions logic that is difficult to test outside CI.

This plan improves repository content quality, code logic quality, and long-term automation maintainability without changing generated artifact semantics intentionally.

## Scope

In scope:

- Refactor script internals for clearer boundaries and reusable helpers.
- Move repeated rule parsing/rendering logic into tested Python modules where it reduces shell complexity.
- Improve local and CI validation so maintainers can catch regressions before scheduled publishing.
- Document source formats, generated artifact contracts, and maintenance workflows.
- Preserve branch publishing behavior and output directory conventions.

Out of scope:

- Changing rule source policy, adding/removing third-party upstream sources, or redefining which domains/IPs belong in each list.
- Replacing the current shell-based orchestration wholesale with another build system.
- Changing published branch names or public artifact paths unless a later migration plan explicitly covers compatibility.

## Current Architecture Summary

- `.github/workflows/build.yml` selects `full` or `custom` scope, runs lint/tests, syncs upstream artifacts, builds custom artifacts, guards outputs, and publishes client branches.
- `scripts/sync-upstream.sh` downloads and normalizes upstream domain/IP sources.
- `scripts/build-custom.sh` turns `sources/custom/domain/*.list` and `sources/custom/ip/*.list` into `.output/**` artifacts.
- `scripts/lib/rules.sh` contains the main rendering and compilation helpers for Surge, QuanX, Egern, sing-box, and Mihomo.
- `scripts/lib/common.sh` resolves tool versions and downloads `sing-box`/`mihomo` into `.bin/`.
- `scripts/lint-custom-rules.sh`, `scripts/test-domain-parsing.sh`, and `scripts/guard-artifacts.sh` provide the current quality gate.
- `scripts/export-domain-rules.py` and `scripts/normalize-ip-source.py` are the only substantial Python modules and are good candidates for absorbing duplicated parser/renderer logic.

## Key Decisions

1. Keep shell as the orchestration layer, but reduce embedded business logic.
   - Rationale: existing CI and scripts are shell-oriented, and a full rewrite would create unnecessary publishing risk.

2. Treat generated artifacts as compatibility-sensitive outputs.
   - Rationale: consumers likely depend on current file names, branch names, formats, and no-resolve behavior.

3. Add characterization tests before refactoring renderers.
   - Rationale: several transformations are currently duplicated across shell, AWK, and inline Python; tests should lock expected behavior before consolidation.

4. Centralize rule grammar and format rendering in Python modules.
   - Rationale: domain/IP parsing rules are easier to validate and test in Python than across many inline heredocs.

5. Split CI into fast validation and publish-capable build stages where possible.
   - Rationale: maintainers need quick feedback on pull requests without invoking network-heavy sync/publish paths unnecessarily.

## Implementation Units

### Unit 1: Repository Documentation and Contracts

Files:

- `README.md`
- `GEOLOCATION-NOT-CN.md`
- `docs/rule-source-format.md`
- `docs/generated-artifacts.md`
- `docs/maintenance-runbook.md`

Changes:

- Document accepted custom domain rules: `DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`, `DOMAIN-REGEX`, casing behavior, comments, deduplication, and client compatibility differences.
- Document accepted custom IP rules and how `no-resolve` is handled.
- Document generated artifact matrix: `domain/surge`, `domain/quanx`, `domain/egern`, `domain/sing-box`, `domain/mihomo`, `ip/*`.
- Add a runbook for manual `workflow_dispatch` scopes: `auto`, `custom`, and `full`.
- Explain `.bin/`, `.tmp/`, and `.output/` as generated local state.

Tests/verification:

- Markdown link check if a markdown checker is added later.
- Manual review that README links point to the new docs.

### Unit 2: Shared Script Utilities

Files:

- `scripts/lib/common.sh`
- `scripts/lib/rules.sh`
- `scripts/build-custom.sh`
- `scripts/lint-custom-rules.sh`
- `scripts/sync-upstream.sh`
- `scripts/guard-artifacts.sh`
- `scripts/test-shell-utils.sh`

Changes:

- Move duplicated `list_rule_files` implementations from `scripts/build-custom.sh` and `scripts/lint-custom-rules.sh` into `scripts/lib/common.sh`.
- Add common helpers for sorted file iteration, safe temp file creation, and consistent error messages.
- Keep existing command-line behavior stable while reducing per-script helper drift.
- Add focused shell tests for file listing, `write_if_changed`, version normalization, and safe no-op behavior for missing directories.

Tests/verification:

- `scripts/test-shell-utils.sh` covers helper behavior.
- Existing `shellcheck scripts/*.sh scripts/lib/*.sh` remains green.
- Existing `scripts/lint-custom-rules.sh` and `scripts/test-domain-parsing.sh` remain green.

### Unit 3: Domain Rule Parser and Renderers

Files:

- `scripts/export-domain-rules.py`
- `scripts/lib/rules.sh`
- `scripts/test-domain-parsing.sh`
- `tests/fixtures/domain/*.list`
- `tests/fixtures/domain/expected/*`

Changes:

- Extend `scripts/export-domain-rules.py` into the single domain grammar implementation for normalization and rendering.
- Replace inline Python heredocs in `scripts/lib/rules.sh` for custom domain normalization, Surge rendering, QuanX rendering, Egern rendering, and Mihomo text generation with calls to `scripts/export-domain-rules.py` subcommands.
- Preserve support for `DOMAIN-REGEX` where currently supported and skip it where target clients do not support it.
- Add fixture-based tests for comments, blank lines, aliases, duplicate removal, trailing dots, invalid prefixes, casing, and client-specific output.

Tests/verification:

- `scripts/test-domain-parsing.sh` should cover all domain renderer outputs from fixtures.
- Run a small custom build and compare `.output/domain/**` before/after for unchanged fixtures.

### Unit 4: IP Rule Parser and Renderers

Files:

- `scripts/normalize-ip-source.py`
- `scripts/lib/rules.sh`
- `scripts/lint-custom-rules.sh`
- `scripts/test-ip-parsing.sh`
- `tests/fixtures/ip/*.list`
- `tests/fixtures/ip/expected/*`

Changes:

- Add renderer subcommands to `scripts/normalize-ip-source.py` or introduce `scripts/export-ip-rules.py` if separation is clearer.
- Consolidate IP normalization and output rendering currently split across AWK and inline Python in `scripts/lib/rules.sh`.
- Use Python `ipaddress` consistently for validation, canonicalization, IPv4/IPv6 detection, and CIDR counting.
- Keep `SURGE_IP_APPEND_NO_RESOLVE` behavior stable and explicitly test both enabled and disabled modes.

Tests/verification:

- New `scripts/test-ip-parsing.sh` covers CIDR normalization, invalid CIDRs, duplicate removal, Surge/QuanX/Egern output, and `no-resolve` behavior.
- `scripts/lint-custom-rules.sh` continues to reject invalid custom IP files.

### Unit 5: Upstream Source Manifest

Files:

- `scripts/sync-upstream.sh`
- `config/upstream-sources.yaml` or `config/upstream-sources.json`
- `scripts/test-upstream-manifest.sh`
- `README.md`

Changes:

- Extract hard-coded upstream source metadata from `scripts/sync-upstream.sh` into a manifest with source name, URL, source type, output path, minimum expected entries, and optional fallback URLs.
- Keep imperative shell code for downloading and orchestration, but make source definitions data-driven.
- Validate manifest shape before use.
- Document how to add or retire an upstream source.

Tests/verification:

- `scripts/test-upstream-manifest.sh` validates required fields and unique output names.
- `scripts/sync-upstream.sh` supports a dry-run or manifest-validation mode that does not download remote data.

### Unit 6: Artifact Guard Maintainability

Files:

- `scripts/guard-artifacts.sh`
- `config/artifact-guards.yaml` or `config/artifact-guards.json`
- `scripts/test-artifact-guards.sh`

Changes:

- Move hard-coded minimum file counts, IP entry thresholds, and volatility limits into a guard config file.
- Add clear failure output showing which guard failed, baseline values, current values, and suggested maintainer action.
- Separate pure counting/threshold logic from Git baseline lookup where practical.

Tests/verification:

- `scripts/test-artifact-guards.sh` uses temporary fixture directories to test count checks and threshold failures without relying on remote branches.
- CI still runs full `scripts/guard-artifacts.sh` after build.

### Unit 7: GitHub Actions Workflow Decomposition

Files:

- `.github/workflows/build.yml`
- `.github/workflows/validate.yml`
- `scripts/resolve-build-scope.sh`
- `scripts/test-build-scope.sh`

Changes:

- Move inline build-scope decision logic from `.github/workflows/build.yml` into `scripts/resolve-build-scope.sh`.
- Add `scripts/test-build-scope.sh` with fixture git histories or mocked file lists for push-only-custom, push-with-script-change, custom deletion, manual custom, and scheduled full scenarios.
- Add a lightweight `validate.yml` for pull requests that runs shellcheck, lint, parser tests, and manifest validation without publishing.
- Keep `build.yml` responsible for scheduled/manual/push publishing workflows.

Tests/verification:

- `scripts/test-build-scope.sh` covers scope outputs and reasons.
- Pull request validation runs without requiring write permissions.
- Publishing workflow retains `contents: write` only where needed.

### Unit 8: Local Developer Entry Point

Files:

- `Makefile` or `justfile`
- `README.md`
- `.github/workflows/build.yml`

Changes:

- Add a small documented command surface such as `make validate`, `make test`, `make build-custom`, and `make clean`.
- Keep commands as wrappers over existing scripts, not a new source of logic.
- Ensure local validation command mirrors CI validation order.

Tests/verification:

- `make validate` runs shellcheck, custom rule lint, domain tests, IP tests, and manifest tests.
- `make clean` removes `.bin/`, `.tmp/`, and `.output/` only if explicitly documented.

## Suggested Execution Order

1. Add documentation and test fixtures first, without changing behavior.
2. Add shell utility tests and centralize low-risk duplicated helpers.
3. Characterize domain outputs, then consolidate domain renderers.
4. Characterize IP outputs, then consolidate IP renderers.
5. Extract upstream source manifest and guard config.
6. Move CI scope logic into a tested script and add PR validation workflow.
7. Add local developer entry point and update README references.

## Risk Management

- Generated artifacts may change due to normalization differences. Mitigate with fixture tests and before/after diffs on representative custom sources.
- Network-heavy upstream sync can make tests flaky. Keep unit tests fixture-based and reserve remote downloads for scheduled/full CI paths.
- Published branch compatibility is critical. Avoid changing branch names, artifact paths, or file extensions.
- Tool version resolution depends on GitHub release APIs. Keep existing cache fallback behavior and test version parsing separately.
- Refactoring shell around `set -euo pipefail` can change failure behavior. Make helper contracts explicit and test empty/missing directory cases.

## Success Criteria

- Maintainers can understand source formats and generated outputs from docs without reading scripts.
- Parser and renderer behavior is covered by fixture tests for both domain and IP rules.
- Workflow scope decisions are testable outside GitHub Actions.
- New upstream sources and guard thresholds can be changed in config rather than editing large shell functions.
- `shellcheck`, custom lint, parser tests, and manifest tests run through a single local command.
- Scheduled/full publishing continues producing the same public artifact layout.

## Validation Matrix

- `shellcheck scripts/*.sh scripts/lib/*.sh`
- `scripts/lint-custom-rules.sh`
- `scripts/test-domain-parsing.sh`
- `scripts/test-ip-parsing.sh`
- `scripts/test-shell-utils.sh`
- `scripts/test-upstream-manifest.sh`
- `scripts/test-artifact-guards.sh`
- `scripts/test-build-scope.sh`
- `scripts/build-custom.sh` on current `sources/custom/**`
- Full workflow dry run or manual `workflow_dispatch` on a non-production branch before relying on scheduled publishing
