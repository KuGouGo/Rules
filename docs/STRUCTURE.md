# Repository Structure

This repository keeps source rules, build configuration, generated artifacts, and release publishing logic separate. Generated files are written under `.output/` and are published to client-specific branches.

## Top-level layout

- `sources/custom/domain/`: maintained domain rules in classical format.
- `sources/custom/ip/`: maintained IP CIDR rules in classical format.
- `config/`: upstream source configuration, platform capability maps, and guard baselines.
- `scripts/commands/`: runnable entrypoints used by Makefile and GitHub Actions.
- `scripts/lib/`: shared shell helpers for downloads, tool cache setup, and artifact rendering.
- `scripts/tools/`: Python tools for parsing, normalization, classification, and summaries.
- `scripts/tools/lint-config.py`: validates upstream source config, baseline thresholds, and platform capabilities.
- `scripts/tests/`: shell tests. `scripts/tests/run.sh` discovers every `test-*.sh` script.
- `tests/fixtures/`: stable input and expected-output fixtures used by tests.
- `.output/`: generated artifacts. This directory is ignored and should not be edited by hand.
- `.tmp/`: temporary build workspace. This directory is ignored.
- `.bin/`: cached external compilers such as `sing-box` and `mihomo`. This directory is ignored.

## Build flow

1. `scripts/commands/sync-upstream.sh` downloads and normalizes upstream sources during a full sync.
2. `scripts/commands/build-custom.sh` renders custom rule lists and optional binary artifacts.
3. `scripts/commands/guard-artifacts.sh` checks generated artifact shape, counts, and volatility.
4. `scripts/commands/publish-branches.sh` publishes platform-specific branches:
   - `surge`
   - `quanx`
   - `egern`
   - `sing-box`
   - `mihomo`

## Local workflow

Use `make validate` before changing generation logic or rule sources. Use `make build-custom-text` when you only need to check text outputs and do not want to download binary compilers.

Useful commands:

```bash
make lint
make test
make validate
make preflight
make build-custom-text
make clean
```
