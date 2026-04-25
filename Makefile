SHELL := /usr/bin/env bash

.PHONY: lint test validate build-custom clean

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		find scripts -type f -name '*.sh' -exec shellcheck {} +; \
	else \
		echo "shellcheck not found, skipping local shell lint"; \
	fi
	./scripts/commands/lint-custom-rules.sh

test:
	./scripts/tests/test-artifact-summary.sh
	./scripts/tests/test-guard-artifacts.sh
	./scripts/tests/test-domain-entrypoint-guard.sh
	./scripts/tests/test-domain-parsing.sh
	./scripts/tests/test-build-scope.sh
	./scripts/tests/test-first-batch-upstreams.sh
	./scripts/tests/test-ip-normalization.sh
	./scripts/tests/test-shell-utils.sh
	./scripts/tests/test-sync-upstream-classification.sh
	./scripts/tests/test-upstream-config.sh

validate: lint test

build-custom:
	./scripts/commands/build-custom.sh

clean:
	./scripts/commands/clean.sh
