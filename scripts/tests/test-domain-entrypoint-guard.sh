#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TRACE_TEST="$TMP_DIR/test.trace"
TRACE_BUILD="$TMP_DIR/build.trace"

required_text_commands=(
  normalize-classical
  surge-list
  quanx-list
  egern-yaml
)

assert_trace_contains() {
  local trace_file="$1"
  local command="$2"
  local label="$3"

  if ! grep -Fxq "$command" "$trace_file"; then
    echo "test failed: $label missing traced command '$command'" >&2
    echo "trace contents:" >&2
    cat "$trace_file" >&2
    exit 1
  fi
}

collect_filtered_trace() {
  local trace_file="$1"
  local output_file="$2"
  : > "$output_file"
  for command in "${required_text_commands[@]}"; do
    if grep -Fxq "$command" "$trace_file"; then
      printf '%s\n' "$command" >> "$output_file"
    fi
  done
}

assert_wrapper_calls_cli() {
  local function_name="$1"
  local expected_subcommand="$2"
  local body_file="$TMP_DIR/${function_name}.body"

  awk -v fn="$function_name" '
    $0 ~ ("^" fn "\\(\\) \\{") { capture = 1; print; next }
    capture {
      print
      if ($0 == "}") {
        exit
      }
    }
  ' "$ROOT/scripts/lib/rules.sh" > "$body_file"

  if ! grep -Fq "$expected_subcommand" "$body_file"; then
    echo "test failed: $function_name does not call expected CLI subcommand '$expected_subcommand'" >&2
    cat "$body_file" >&2
    exit 1
  fi

  if grep -Fq "<<'PY'" "$body_file"; then
    echo "test failed: $function_name still contains inline Python" >&2
    cat "$body_file" >&2
    exit 1
  fi
}

RULES_TRACE_DOMAIN_CLI_FILE="$TRACE_TEST" ./scripts/tests/test-domain-parsing.sh >/dev/null
RULES_TRACE_DOMAIN_CLI_FILE="$TRACE_BUILD" RULES_BUILD_CUSTOM_TEXT_ONLY=1 ./scripts/commands/build-custom.sh >/dev/null

for command in "${required_text_commands[@]}"; do
  assert_trace_contains "$TRACE_TEST" "$command" "test-domain-parsing"
  assert_trace_contains "$TRACE_BUILD" "$command" "build-custom"
done

TEST_FILTERED_TRACE="$TMP_DIR/test.filtered"
BUILD_FILTERED_TRACE="$TMP_DIR/build.filtered"
collect_filtered_trace "$TRACE_TEST" "$TEST_FILTERED_TRACE"
collect_filtered_trace "$TRACE_BUILD" "$BUILD_FILTERED_TRACE"

if ! diff -u "$TEST_FILTERED_TRACE" "$BUILD_FILTERED_TRACE"; then
  echo "test failed: test-domain-parsing and build-custom do not share the same text-platform CLI entrypoints" >&2
  exit 1
fi

assert_wrapper_calls_cli "normalize_custom_domain_source" "normalize-classical"
assert_wrapper_calls_cli "render_surge_domain_ruleset_from_rules" "surge-list"
assert_wrapper_calls_cli "render_quanx_domain_ruleset_from_rules" "quanx-list"
assert_wrapper_calls_cli "render_egern_domain_ruleset_from_rules" "egern-yaml"
assert_wrapper_calls_cli "render_domain_rule_dir_to_text_platform_dirs" "text-platform-dirs"

echo "domain entrypoint guard passed"
