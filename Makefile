SHELL := /usr/bin/env bash
REQUIRE_SHELLCHECK ?= 0

SHELL_SCRIPTS := $(shell find scripts -type f -name '*.sh' | sort)
PYTHON_TOOLS := $(shell find scripts/tools -type f -name '*.py' | sort)

.PHONY: help check-runtime lint lint-shell lint-python lint-config lint-rules test validate preflight build-custom build-custom-text clean

help:
	@echo "Available targets:"
	@echo "  make check-runtime     Verify the supported Bash and Python runtimes"
	@echo "  make lint              Run shell, Python, and custom rule lint checks"
	@echo "  make test              Run all repository test scripts"
	@echo "  make validate          Run lint and tests"
	@echo "  make preflight         Run local checks before pushing changes"
	@echo "  make build-custom      Build custom rules and binary artifacts"
	@echo "  make build-custom-text Build custom text artifacts without downloading binary compilers"
	@echo "  make clean             Remove generated artifacts and temporary files"

check-runtime:
	@./scripts/commands/check-runtime.sh

lint: check-runtime lint-shell lint-python lint-config lint-rules

lint-shell:
	bash -n $(SHELL_SCRIPTS)
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SHELL_SCRIPTS); \
	elif [ "$(REQUIRE_SHELLCHECK)" = "1" ]; then \
		echo "shellcheck not found"; \
		exit 1; \
	else \
		echo "shellcheck not found, skipping local shell lint"; \
	fi

lint-python:
	python3 -m py_compile $(PYTHON_TOOLS)

lint-config:
	python3 scripts/tools/lint-config.py

lint-rules:
	./scripts/commands/lint-custom-rules.sh

test: check-runtime
	./scripts/tests/run.sh

validate: lint test

preflight: validate build-custom-text

build-custom: check-runtime
	./scripts/commands/build-custom.sh

build-custom-text: check-runtime
	RULES_BUILD_CUSTOM_TEXT_ONLY=1 ./scripts/commands/build-custom.sh

clean:
	./scripts/commands/clean.sh
