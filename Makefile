SHELL := /usr/bin/env bash
REQUIRE_SHELLCHECK ?= 0

SHELL_SCRIPTS := $(shell find scripts -type f -name '*.sh' | sort)
PYTHON_TOOLS := $(shell find scripts/tools -type f -name '*.py' | sort)

.PHONY: help check check-runtime lint lint-shell lint-python lint-config lint-rules test test-python validate validate-tool-update build-custom build-custom-text clean

help:
	@echo "Available targets:"
	@echo "  make check             Quick syntax, config, and rule checks"
	@echo "  make check-runtime     Verify the supported Bash and Python runtimes"
	@echo "  make lint              Run shell, Python, and custom rule lint checks"
	@echo "  make test              Run all repository test scripts"
	@echo "  make test-python       Run the Python unit test suite"
	@echo "  make validate          Run lint and tests"
	@echo "  make validate-tool-update Validate tests and compile custom rules with locked tools"
	@echo "  make build-custom      Build custom rules and binary artifacts"
	@echo "  make build-custom-text Build custom text artifacts without downloading binary compilers"
	@echo "  make clean             Remove generated artifacts and temporary files"

check: lint

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

test-python:
	python3 -m unittest discover -s scripts/tests/python -t scripts/tests/python

validate: lint test test-python

validate-tool-update:
	$(MAKE) validate
	$(MAKE) build-custom

build-custom:
	./scripts/commands/build-custom.sh

build-custom-text:
	RULES_BUILD_CUSTOM_TEXT_ONLY=1 ./scripts/commands/build-custom.sh

clean:
	./scripts/commands/clean.sh
