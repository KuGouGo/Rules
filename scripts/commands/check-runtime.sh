#!/usr/bin/env bash

required_bash_major=5
required_python_major=3
required_python_minor=11

validate_test_minimum() {
  local name="$1"
  local value="$2"

  case "$value" in
    ''|*[!0-9]*)
      echo "$name must be a non-negative integer" >&2
      exit 2
      ;;
  esac
}

if [ -n "${RULES_RUNTIME_TEST_BASH_MIN_MAJOR:-}" ]; then
  validate_test_minimum RULES_RUNTIME_TEST_BASH_MIN_MAJOR "$RULES_RUNTIME_TEST_BASH_MIN_MAJOR"
  required_bash_major="$RULES_RUNTIME_TEST_BASH_MIN_MAJOR"
fi
if [ -n "${RULES_RUNTIME_TEST_PYTHON_MIN_MAJOR:-}" ]; then
  validate_test_minimum RULES_RUNTIME_TEST_PYTHON_MIN_MAJOR "$RULES_RUNTIME_TEST_PYTHON_MIN_MAJOR"
  required_python_major="$RULES_RUNTIME_TEST_PYTHON_MIN_MAJOR"
fi
if [ -n "${RULES_RUNTIME_TEST_PYTHON_MIN_MINOR:-}" ]; then
  validate_test_minimum RULES_RUNTIME_TEST_PYTHON_MIN_MINOR "$RULES_RUNTIME_TEST_PYTHON_MIN_MINOR"
  required_python_minor="$RULES_RUNTIME_TEST_PYTHON_MIN_MINOR"
fi

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]:-0}" -lt "$required_bash_major" ]; then
  echo "Bash ${required_bash_major}+ is required (found ${BASH_VERSION:-non-Bash shell})" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python ${required_python_major}.${required_python_minor}+ is required (python3 not found in PATH)" >&2
  exit 1
fi

python3 - "$required_python_major" "$required_python_minor" <<'PY'
import sys

required = tuple(map(int, sys.argv[1:]))
if sys.version_info[:2] < required:
    current = ".".join(map(str, sys.version_info[:3]))
    raise SystemExit(
        f"Python {required[0]}.{required[1]}+ is required (found {current})"
    )
PY
