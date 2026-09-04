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

cat > "$TMP_DIR/bin/sing-box" <<'EOF'
#!/usr/bin/env sh
output="$5"
printf 'srs' > "$output"
EOF
cat > "$TMP_DIR/bin/mihomo" <<'EOF'
#!/usr/bin/env sh
output="$5"
printf 'mrs' > "$output"
EOF
chmod +x "$TMP_DIR/bin/sing-box" "$TMP_DIR/bin/mihomo"
printf '.example.org\n' > "$TMP_DIR/domain-in/cn.mihomo.txt"
if ! PATH="$TMP_DIR/bin:$PATH" compile_domain_mihomo_text_dir \
  "$TMP_DIR/domain-in" "$TMP_DIR/domain-out" 1 >/dev/null 2>&1; then
  echo "test failed: mihomo compile failed with producing stub" >&2
  exit 1
fi
[ -f "$TMP_DIR/domain-out/cn.mrs" ] || {
  echo "test failed: mihomo artifact must be named <stem>.mrs; got: $(ls "$TMP_DIR/domain-out")" >&2
  exit 1
}
if [ -f "$TMP_DIR/domain-out/cn.mihomo.mrs" ]; then
  echo "test failed: mihomo artifact leaked the intermediate suffix into its name" >&2
  exit 1
fi

echo "binary compile contract tests passed"
