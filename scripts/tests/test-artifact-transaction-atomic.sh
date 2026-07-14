#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/scripts/commands" "$REPO/scripts/tools" "$REPO/.output"
cp "$ROOT/scripts/commands/build-artifacts-transaction.sh" "$REPO/scripts/commands/"
printf 'old live tree\n' > "$REPO/.output/sentinel"

cat > "$REPO/scripts/commands/sync-upstream.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$RULES_ARTIFACT_ROOT"
printf 'partial staged tree\n' > "$RULES_ARTIFACT_ROOT/new"
printf '[{"status":"ok"}]\n' > "$RULES_ARTIFACT_ROOT/upstream-summary.json"
case "${RULES_SYNC_FAIL_AT:-}" in
  late-domain|late-ip|late-compiler) exit 1 ;;
esac
EOF
cat > "$REPO/scripts/commands/restore-artifacts.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$RULES_ARTIFACT_ROOT"
printf 'partial restore\n' > "$RULES_ARTIFACT_ROOT/new"
case "${RULES_RESTORE_FAIL_AT:-}" in late-text|late-binary) exit 1 ;; esac
EOF
for command in build-custom.sh guard-artifacts.sh generate-artifact-manifest.sh verify-artifact-manifest.sh; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/scripts/commands/$command"
done
cat > "$REPO/scripts/tools/summarize-artifacts.py" <<'EOF'
import argparse
p=argparse.ArgumentParser(); p.add_argument('root'); p.add_argument('--output'); a=p.parse_args()
open(a.output, 'w').write('{}\n')
EOF
chmod +x "$REPO/scripts/commands/"*.sh

snapshot() { find "$REPO/.output" -type f -print0 | sort -z | xargs -0 sha256sum; }
assert_preserved() {
  local label="$1"; shift
  snapshot > "$TMP/before"
  if env "$@" "$REPO/scripts/commands/build-artifacts-transaction.sh" >/dev/null 2>"$TMP/$label.err"; then
    echo "expected transaction failure: $label" >&2; exit 1
  fi
  snapshot > "$TMP/after"
  cmp -s "$TMP/before" "$TMP/after" || { echo "$label changed live output" >&2; exit 1; }
  grep -R '"status":"failed"' "$REPO/.artifacts/diagnostics" >/dev/null
}

for point in late-domain late-ip late-compiler; do
  assert_preserved "sync-$point" RULES_BUILD_SCOPE=full RULES_SYNC_FAIL_AT="$point" ARTIFACT_GENERATION_ID="$point"
done
for point in late-text late-binary; do
  assert_preserved "restore-$point" RULES_BUILD_SCOPE=custom RULES_RESTORE_FAIL_AT="$point" ARTIFACT_GENERATION_ID="$point"
done

if RULES_ARTIFACT_ROOT="$TMP/caller-stage" "$REPO/scripts/commands/build-artifacts-transaction.sh" >"$TMP/root.out" 2>"$TMP/root.err"; then
  echo "transaction accepted caller-supplied RULES_ARTIFACT_ROOT" >&2; exit 1
fi
grep -F 'RULES_ARTIFACT_ROOT is transaction-owned' "$TMP/root.err" >/dev/null
[ ! -e "$TMP/caller-stage" ]

LIVE_OVERRIDE="$TMP/live-override"
RULES_BUILD_SCOPE=full RULES_LIVE_ARTIFACT_ROOT="$LIVE_OVERRIDE" "$REPO/scripts/commands/build-artifacts-transaction.sh" >/dev/null
[ -f "$LIVE_OVERRIDE/new" ]
grep -F 'partial staged tree' "$LIVE_OVERRIDE/new" >/dev/null
[ -f "$REPO/.output/sentinel" ]

grep -F 'inject_sync_failure late-domain' "$ROOT/scripts/commands/sync-upstream.sh" >/dev/null
grep -F 'inject_sync_failure late-ip' "$ROOT/scripts/commands/sync-upstream.sh" >/dev/null
grep -F 'inject_sync_failure late-compiler' "$ROOT/scripts/commands/sync-upstream.sh" >/dev/null
grep -F 'inject_restore_failure late-binary' "$ROOT/scripts/commands/restore-artifacts.sh" >/dev/null

echo 'artifact transaction atomic failure tests passed'
