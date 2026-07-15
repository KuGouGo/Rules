#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
mkdir -p "$REPO"
cp -R "$ROOT/scripts" "$ROOT/config" "$ROOT/sources" "$REPO/"
mkdir -p "$REPO/.output/domain/surge" "$REPO/.output/unrelated" "$REPO/.bin"
printf 'restored upstream\n' > "$REPO/.output/unrelated/upstream.txt"
printf 'old controlled output\n' > "$REPO/.output/domain/surge/emby.list"

git -C "$REPO" init -q
git -C "$REPO" config user.name test
git -C "$REPO" config user.email test@example.com
git -C "$REPO" add scripts config sources
git -C "$REPO" commit -m base >/dev/null
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"

snapshot_output() {
  local destination="$1"
  python3 - "$REPO/.output" "$destination" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
rows = []
for path in sorted(item for item in root.rglob("*") if item.is_file()):
    rows.append(f"{path.relative_to(root).as_posix()} {hashlib.sha256(path.read_bytes()).hexdigest()}")
Path(sys.argv[2]).write_text("\n".join(rows) + "\n", encoding="utf-8")
PY
}

assert_injected_failure_preserves_output() {
  local point="$1"
  shift
  local before="$TMP_DIR/$point.before"
  local after="$TMP_DIR/$point.after"

  snapshot_output "$before"
  if env RULES_CONFLICT_BASE_SHA="$BASE_SHA" RULES_BUILD_CUSTOM_FAIL_AT="$point" "$@" \
    "$REPO/scripts/commands/build-custom.sh" \
    >"$TMP_DIR/$point.stdout" 2>"$TMP_DIR/$point.stderr"; then
    echo "test failed: expected injected $point failure" >&2
    exit 1
  fi
  grep -Fx "injected custom build failure at $point" "$TMP_DIR/$point.stderr" >/dev/null || {
    echo "test failed: missing injected failure marker for $point" >&2
    cat "$TMP_DIR/$point.stderr" >&2
    exit 1
  }
  snapshot_output "$after"
  if ! cmp -s "$before" "$after"; then
    echo "test failed: $point failure changed .output" >&2
    diff -u "$before" "$after" >&2 || true
    exit 1
  fi
}

# Change a maintained source so staging contains output different from the
# restored controlled artifact. A late text failure must still publish nothing.
printf '\nDOMAIN-SUFFIX,atomic-stage.example.com\n' >> "$REPO/sources/custom/domain/emby.list"
assert_injected_failure_preserves_output late-text RULES_BUILD_CUSTOM_TEXT_ONLY=1

# Avoid network/tool-lock behavior only inside this disposable test copy. The
# fake compilers produce deterministic binary payloads so failure is injected
# after all binary compile calls have completed.
cat >> "$REPO/scripts/lib/common.sh" <<'EOF'
ensure_sing_box() { return 0; }
ensure_mihomo() { return 0; }
EOF
cat > "$REPO/.bin/sing-box" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = version ]; then
  echo 'sing-box version 1.13.11'
  exit 0
fi
out=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then out="$2"; shift 2; else shift; fi
done
printf 'fake-srs\n' > "$out"
EOF
cat > "$REPO/.bin/mihomo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = -v ]; then echo 'Mihomo Meta v1.19.15'; exit 0; fi
for arg in "$@"; do out="$arg"; done
printf 'fake-mrs\n' > "$out"
EOF
chmod +x "$REPO/.bin/sing-box" "$REPO/.bin/mihomo"
assert_injected_failure_preserves_output late-binary

# A successful text-only commit updates only controlled text targets. Binary
# targets and unrelated restored/upstream files remain untouched.
printf 'restored binary\n' > "$REPO/.output/domain/surge/unrelated.list"
RULES_CONFLICT_BASE_SHA="$BASE_SHA" RULES_BUILD_CUSTOM_TEXT_ONLY=1 \
  "$REPO/scripts/commands/build-custom.sh" >/dev/null
grep -Fx 'DOMAIN-SUFFIX,atomic-stage.example.com' "$REPO/.output/domain/surge/emby.list" >/dev/null
grep -Fx 'restored upstream' "$REPO/.output/unrelated/upstream.txt" >/dev/null
grep -Fx 'restored binary' "$REPO/.output/domain/surge/unrelated.list" >/dev/null

echo "custom build atomic staging tests passed"
