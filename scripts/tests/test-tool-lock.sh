#!/usr/bin/env bash
# Calls use the sourced implementation until the deliberate final failure override.
# shellcheck disable=SC2218
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "test failed: $*" >&2
  exit 1
}

export SING_BOX_VERSION=latest
export MIHOMO_VERSION=latest
[ "$(resolve_sing_box_version)" = "1.13.14" ] || fail "sing-box version must come only from lock"
[ "$(resolve_mihomo_version)" = "1.19.28" ] || fail "mihomo version must come only from lock"
[ "$(tool_lock_value sing-box tag_commit)" = "25a600db24f7680ad9806ce5427bd0ab8afe1114" ] || fail "sing-box tag commit is not locked"
[ "$(tool_lock_value mihomo tag_commit)" = "cbd11db1e13a75d8e680e0fe7742c95be4cba2be" ] || fail "mihomo tag commit is not locked"

printf 'verified archive fixture\n' > "$TMP_DIR/archive"
archive_sha="$(sha256_file "$TMP_DIR/archive")"
verify_archive_sha256 "$TMP_DIR/archive" "$archive_sha"
if verify_archive_sha256 "$TMP_DIR/archive" "0000000000000000000000000000000000000000000000000000000000000000" 2>/dev/null; then
  fail "incorrect archive checksum was accepted"
fi

BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"
TOOL_LOCK_FILE="$TMP_DIR/tools-lock.json"
cp "$ROOT/config/tools-lock.json" "$TOOL_LOCK_FILE"
cat > "$BIN_DIR/sing-box" <<'SH'
#!/usr/bin/env bash
printf 'sing-box version 1.13.14\n'
SH
chmod +x "$BIN_DIR/sing-box"
python3 - "$TOOL_LOCK_FILE" "$(sha256_file "$BIN_DIR/sing-box")" <<'PY'
import json
import sys

path, digest = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["tools"]["sing-box"]["platforms"]["linux-amd64"]["binary_sha256"] = digest
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
write_tool_provenance "sing-box" "linux-amd64" "$BIN_DIR/sing-box" "sing-box version 1.13.14"
tool_cache_is_trusted "sing-box" "linux-amd64" || fail "valid provenance cache was rejected"
if compgen -G "$BIN_DIR/.sing-box.provenance.*" >/dev/null; then
  fail "atomic provenance temporary file was left behind"
fi

python3 - "$(tool_provenance_file sing-box)" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["tag_commit"] = "0000000000000000000000000000000000000000"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
if tool_cache_is_trusted "sing-box" "linux-amd64"; then
  fail "provenance with the wrong tag commit was accepted"
fi
write_tool_provenance "sing-box" "linux-amd64" "$BIN_DIR/sing-box" "sing-box version 1.13.14"

printf '# cache pollution\n' >> "$BIN_DIR/sing-box"
if tool_cache_is_trusted "sing-box" "linux-amd64"; then
  fail "modified cached binary was accepted"
fi

cat > "$BIN_DIR/sing-box" <<'SH'
#!/usr/bin/env bash
printf 'sing-box version 1.13.13\n'
SH
chmod +x "$BIN_DIR/sing-box"
write_tool_provenance "sing-box" "linux-amd64" "$BIN_DIR/sing-box" "sing-box version 1.13.13"
if tool_cache_is_trusted "sing-box" "linux-amd64"; then
  fail "wrong cached binary version was accepted"
fi

python3 - "$(tool_provenance_file sing-box)" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["asset"] = "unlocked-asset.tar.gz"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
if tool_cache_is_trusted "sing-box" "linux-amd64"; then
  fail "provenance inconsistent with lock was accepted"
fi

# A mutually tampered binary/sidecar pair must be rejected against the locked
# extracted-binary digest before the binary can execute.
cat > "$BIN_DIR/sing-box" <<SH
#!/usr/bin/env bash
touch "$TMP_DIR/tampered-executed"
printf 'sing-box version 1.13.14\n'
SH
chmod +x "$BIN_DIR/sing-box"
write_tool_provenance "sing-box" "linux-amd64" "$BIN_DIR/sing-box" "sing-box version 1.13.14"
if tool_cache_is_trusted "sing-box" "linux-amd64"; then
  fail "mutually tampered cache pair was accepted"
fi
[ ! -e "$TMP_DIR/tampered-executed" ] || fail "unanchored cached binary was executed"

# Failure to create provenance must not replace a matching canonical pair.
printf 'old binary\n' > "$BIN_DIR/sing-box"
printf 'old sidecar\n' > "$(tool_provenance_file sing-box)"
printf 'new binary\n' > "$BIN_DIR/sing-box.new"
old_binary_sha="$(sha256_file "$BIN_DIR/sing-box")"
old_sidecar_sha="$(sha256_file "$(tool_provenance_file sing-box)")"
write_tool_provenance() { return 1; }
if install_tool_with_provenance "sing-box" "linux-amd64" "$BIN_DIR/sing-box.new" "sing-box version 1.13.14"; then
  fail "installation succeeded despite provenance-write failure"
fi
[ "$(sha256_file "$BIN_DIR/sing-box")" = "$old_binary_sha" ] || fail "provenance failure replaced canonical binary"
[ "$(sha256_file "$(tool_provenance_file sing-box)")" = "$old_sidecar_sha" ] || fail "provenance failure replaced canonical sidecar"

echo "tool lock tests passed"
