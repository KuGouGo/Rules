#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=scripts/lib/rules.sh
source "$ROOT/scripts/lib/rules.sh"

mkdir -p "$TMP_DIR/domain-in" "$TMP_DIR/domain-out" "$TMP_DIR/ip-out" "$TMP_DIR/bin"
printf '{"version":4,"rules":[{"domain_suffix":["example.com"]}]}' > "$TMP_DIR/domain-in/sample.json"
printf '192.0.2.0/24\n' > "$TMP_DIR/domain-in/sample.txt"

# A compiler may incorrectly return success without creating output. The batch
# helpers must fail closed instead of relying on the command status alone.
cat > "$TMP_DIR/bin/sing-box" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat > "$TMP_DIR/bin/mihomo" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$TMP_DIR/bin/sing-box" "$TMP_DIR/bin/mihomo"

if PATH="$TMP_DIR/bin:$PATH" compile_domain_singbox_json_dir \
  "$TMP_DIR/domain-in" "$TMP_DIR/domain-out" 1 >/dev/null 2>&1; then
  echo "test failed: missing sing-box output was accepted" >&2
  exit 1
fi

if PATH="$TMP_DIR/bin:$PATH" compile_ip_binary_dirs \
  "$TMP_DIR/domain-in" "$TMP_DIR/domain-out" "$TMP_DIR/ip-out" 1 >/dev/null 2>&1; then
  echo "test failed: missing IP binary output was accepted" >&2
  exit 1
fi

RULES_COMPILE_JOBS=3
[ "$(detect_compile_jobs)" = 3 ] || {
  echo "test failed: RULES_COMPILE_JOBS was not honored" >&2
  exit 1
}
RULES_COMPILE_JOBS=0
if detect_compile_jobs >/dev/null 2>&1; then
  echo "test failed: zero compile jobs were accepted" >&2
  exit 1
fi

echo "binary compile contract tests passed"
