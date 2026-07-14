#!/usr/bin/env bash

: "${ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${BIN_DIR:=$ROOT/.bin}"

: "${TOOL_LOCK_FILE:=$ROOT/config/tools-lock.json}"

setup_tool_cache() {
  mkdir -p "$BIN_DIR"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) export PATH="$BIN_DIR:$PATH" ;;
  esac
}

write_if_changed() {
  local src="$1"
  local dst="$2"

  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    rm -f "$src"
    return 0
  fi

  mv "$src" "$dst"
}

write_if_nonempty_or_remove() {
  local src="$1"
  local dst="$2"

  if [ ! -s "$src" ]; then
    rm -f "$src" "$dst"
    return 0
  fi

  write_if_changed "$src" "$dst"
}

list_files_by_extension() {
  local dir="$1"
  local extension="$2"

  if [ ! -d "$dir" ]; then
    return 0
  fi

  find "$dir" -maxdepth 1 -type f -name "*.${extension}" | sort
}

list_rule_files() {
  list_files_by_extension "$1" list
}

detect_os() {
  local raw_os
  raw_os="$(uname -s)"
  case "$raw_os" in
    MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
    *) printf '%s' "$raw_os" | tr '[:upper:]' '[:lower:]' ;;
  esac
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) printf 'amd64' ;;
    arm64|aarch64) printf 'arm64' ;;
    *)
      echo "unsupported architecture: $arch" >&2
      return 1
      ;;
  esac
}

require_non_windows_shell() {
  local os
  os="$(detect_os)"

  if [ "$os" = "windows" ]; then
    echo "local Windows builds are not supported; use GitHub Actions or a non-Windows shell environment" >&2
    return 1
  fi

  printf '%s' "$os"
}

download_file() {
  local url="$1"
  local out="$2"
  local out_dir tmp

  out_dir="$(dirname "$out")"
  mkdir -p "$out_dir"
  tmp="$(mktemp "${out_dir}/.download.$(basename "$out").XXXXXX")"

  if curl --retry 3 --retry-all-errors --connect-timeout 20 --max-time 300 -fL "$url" -o "$tmp"; then
    mv "$tmp" "$out"
  else
    rm -f "$tmp"
    return 1
  fi
}

tool_lock_value() {
  local tool="$1"
  local field="$2"
  local platform="${3:-}"
  python3 - "$TOOL_LOCK_FILE" "$tool" "$field" "$platform" <<'PY'
import json
import sys

path, tool, field, platform = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    entry = json.load(handle)["tools"][tool]
if platform:
    entry = entry["platforms"][platform]
value = entry[field]
if not isinstance(value, str) or not value:
    raise SystemExit(f"invalid locked value: {tool}.{field}")
print(value, end="")
PY
}

resolve_sing_box_version() {
  tool_lock_value "sing-box" version
}

resolve_mihomo_version() {
  tool_lock_value "mihomo" version
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | cut -d ' ' -f 1
  else
    python3 - "$file" <<'PY'
import hashlib
import sys

with open(sys.argv[1], "rb") as handle:
    print(hashlib.file_digest(handle, "sha256").hexdigest())
PY
  fi
}

verify_archive_sha256() {
  local archive="$1"
  local expected="$2"
  local actual
  actual="$(sha256_file "$archive")"
  if [ "$actual" != "$expected" ]; then
    echo "checksum mismatch for $(basename "$archive"): expected $expected, got $actual" >&2
    return 1
  fi
}

tool_provenance_file() {
  printf '%s/%s.provenance.json' "$BIN_DIR" "$1"
}

tool_version_probe() {
  local tool="$1"
  local binary="$2"
  local output
  case "$tool" in
    sing-box) output="$("$binary" version 2>&1)" || return 1 ;;
    mihomo) output="$("$binary" -v 2>&1)" || return 1 ;;
    *) return 1 ;;
  esac
  printf '%s' "${output%%$'\n'*}"
}

probe_matches_version() {
  local tool="$1"
  local probe="$2"
  local version="$3"
  case "$tool" in
    sing-box) [[ "$probe" == *"sing-box version ${version}"* ]] ;;
    mihomo) [[ "$probe" == *"Mihomo Meta v${version}"* || "$probe" == *"mihomo v${version}"* ]] ;;
    *) return 1 ;;
  esac
}

tool_cache_is_trusted() {
  local tool="$1"
  local platform="$2"
  local binary="$BIN_DIR/$tool"
  local sidecar version tag_commit asset archive_sha locked_binary_sha binary_sha recorded_probe actual_sha actual_probe

  [ -x "$binary" ] || return 1
  sidecar="$(tool_provenance_file "$tool")"
  [ -s "$sidecar" ] || return 1
  version="$(tool_lock_value "$tool" version)"
  tag_commit="$(tool_lock_value "$tool" tag_commit)"
  asset="$(tool_lock_value "$tool" asset "$platform")"
  archive_sha="$(tool_lock_value "$tool" sha256 "$platform")"
  locked_binary_sha="$(tool_lock_value "$tool" binary_sha256 "$platform")" || return 1

  if ! IFS=$'\t' read -r binary_sha recorded_probe < <(
    python3 - "$sidecar" "$tool" "$version" "$tag_commit" "$platform" "$asset" "$archive_sha" <<'PY'
import json
import re
import sys

path, tool, version, tag_commit, platform, asset, archive_sha = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    expected = {
        "schema_version": 1,
        "tool": tool,
        "version": version,
        "tag_commit": tag_commit,
        "platform": platform,
        "asset": asset,
        "archive_sha256": archive_sha,
    }
    if set(data) != {*expected, "binary_sha256", "version_probe"}:
        raise ValueError
    if any(data.get(key) != value for key, value in expected.items()):
        raise ValueError
    binary_sha = data["binary_sha256"]
    probe = data["version_probe"]
    if not isinstance(binary_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", binary_sha):
        raise ValueError
    if not isinstance(probe, str) or not probe or "\n" in probe or "\r" in probe:
        raise ValueError
    print(f"{binary_sha}\t{probe}")
except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)
PY
  ); then
    return 1
  fi

  actual_sha="$(sha256_file "$binary")"
  [ "$actual_sha" = "$locked_binary_sha" ] || return 1
  [ "$actual_sha" = "$binary_sha" ] || return 1
  # Execute only after the binary is anchored to the independently locked
  # digest derived from the verified official release archive.
  actual_probe="$(tool_version_probe "$tool" "$binary")" || return 1
  [ "$actual_probe" = "$recorded_probe" ] || return 1
  probe_matches_version "$tool" "$actual_probe" "$version"
}

write_tool_provenance() {
  local tool="$1"
  local platform="$2"
  local binary="$3"
  local probe="$4"
  local sidecar sidecar_tmp
  sidecar="${5:-$(tool_provenance_file "$tool")}"
  sidecar_tmp="$(mktemp "${BIN_DIR}/.${tool}.provenance.XXXXXX")"
  if ! python3 - "$sidecar_tmp" "$tool" \
    "$(tool_lock_value "$tool" version)" \
    "$(tool_lock_value "$tool" tag_commit)" "$platform" \
    "$(tool_lock_value "$tool" asset "$platform")" \
    "$(tool_lock_value "$tool" sha256 "$platform")" \
    "$(sha256_file "$binary")" "$probe" <<'PY'
import json
import os
import sys

path, tool, version, tag_commit, platform, asset, archive_sha, binary_sha, probe = sys.argv[1:]
data = {
    "schema_version": 1,
    "tool": tool,
    "version": version,
    "tag_commit": tag_commit,
    "platform": platform,
    "asset": asset,
    "archive_sha256": archive_sha,
    "binary_sha256": binary_sha,
    "version_probe": probe,
}
with open(path, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
  then
    rm -f "$sidecar_tmp"
    return 1
  fi
  mv -f "$sidecar_tmp" "$sidecar"
}

install_tool_with_provenance() {
  local tool="$1" platform="$2" temp_binary="$3" probe="$4"
  local binary sidecar staged_sidecar backup_binary backup_sidecar
  binary="$BIN_DIR/$tool"
  sidecar="$(tool_provenance_file "$tool")"
  staged_sidecar="$BIN_DIR/.${tool}.provenance.install"
  backup_binary="$BIN_DIR/.${tool}.binary.backup"
  backup_sidecar="$BIN_DIR/.${tool}.provenance.backup"
  rm -f "$staged_sidecar" "$backup_binary" "$backup_sidecar"

  # Create durable metadata before touching either canonical cache path.
  if ! write_tool_provenance "$tool" "$platform" "$temp_binary" "$probe" "$staged_sidecar"; then
    rm -f "$staged_sidecar"
    return 1
  fi

  [ ! -e "$binary" ] || mv "$binary" "$backup_binary" || { rm -f "$staged_sidecar"; return 1; }
  if [ -e "$sidecar" ] && ! mv "$sidecar" "$backup_sidecar"; then
    [ ! -e "$backup_binary" ] || mv "$backup_binary" "$binary"
    rm -f "$staged_sidecar"
    return 1
  fi
  if mv "$temp_binary" "$binary" && mv "$staged_sidecar" "$sidecar"; then
    rm -f "$backup_binary" "$backup_sidecar"
    return 0
  fi

  rm -f "$binary" "$sidecar" "$staged_sidecar"
  [ ! -e "$backup_binary" ] || mv "$backup_binary" "$binary"
  [ ! -e "$backup_sidecar" ] || mv "$backup_sidecar" "$sidecar"
  return 1
}

ensure_sing_box() {
  local tool="sing-box" os arch platform version repository tag asset expected_sha archive package_dir temp_binary probe
  setup_tool_cache
  os="$(require_non_windows_shell)"
  [ "$os" = "linux" ] || { echo "unsupported operating system for locked $tool assets: $os" >&2; return 1; }
  arch="$(detect_arch)"
  platform="${os}-${arch}"
  if tool_cache_is_trusted "$tool" "$platform"; then return 0; fi

  version="$(tool_lock_value "$tool" version)"
  repository="$(tool_lock_value "$tool" repository)"
  tag="$(tool_lock_value "$tool" tag)"
  asset="$(tool_lock_value "$tool" asset "$platform")"
  expected_sha="$(tool_lock_value "$tool" sha256 "$platform")"
  archive="$BIN_DIR/$tool.new.tar.gz"
  package_dir="sing-box-${version}-${os}-${arch}"
  temp_binary="$BIN_DIR/$tool.new"
  rm -f "$archive" "$temp_binary" "$(tool_provenance_file "$tool").new"
  rm -rf "${BIN_DIR:?}/$package_dir"
  download_file "https://github.com/${repository}/releases/download/${tag}/${asset}" "$archive"
  if ! verify_archive_sha256 "$archive" "$expected_sha"; then rm -f "$archive"; return 1; fi
  tar -xzf "$archive" -C "$BIN_DIR"
  mv "$BIN_DIR/$package_dir/sing-box" "$temp_binary"
  chmod +x "$temp_binary"
  if ! verify_archive_sha256 "$temp_binary" "$(tool_lock_value "$tool" binary_sha256 "$platform")"; then rm -f "$temp_binary" "$archive"; rm -rf "${BIN_DIR:?}/$package_dir"; return 1; fi
  probe="$(tool_version_probe "$tool" "$temp_binary")"
  probe_matches_version "$tool" "$probe" "$version" || { echo "unexpected $tool version probe: $probe" >&2; rm -f "$temp_binary" "$archive"; rm -rf "${BIN_DIR:?}/$package_dir"; return 1; }
  install_tool_with_provenance "$tool" "$platform" "$temp_binary" "$probe" || { rm -f "$temp_binary" "$archive"; rm -rf "${BIN_DIR:?}/$package_dir"; return 1; }
  rm -rf "${BIN_DIR:?}/$package_dir" "$archive"
}

ensure_mihomo() {
  local tool="mihomo" os arch platform version repository tag asset expected_sha archive temp_binary probe
  setup_tool_cache
  os="$(require_non_windows_shell)"
  [ "$os" = "linux" ] || { echo "unsupported operating system for locked $tool assets: $os" >&2; return 1; }
  arch="$(detect_arch)"
  platform="${os}-${arch}"
  if tool_cache_is_trusted "$tool" "$platform"; then return 0; fi

  version="$(tool_lock_value "$tool" version)"
  repository="$(tool_lock_value "$tool" repository)"
  tag="$(tool_lock_value "$tool" tag)"
  asset="$(tool_lock_value "$tool" asset "$platform")"
  expected_sha="$(tool_lock_value "$tool" sha256 "$platform")"
  archive="$BIN_DIR/$tool.new.gz"
  temp_binary="$BIN_DIR/$tool.new"
  rm -f "$archive" "$temp_binary" "$(tool_provenance_file "$tool").new"
  download_file "https://github.com/${repository}/releases/download/${tag}/${asset}" "$archive"
  if ! verify_archive_sha256 "$archive" "$expected_sha"; then rm -f "$archive"; return 1; fi
  gzip -dc "$archive" > "$temp_binary"
  chmod +x "$temp_binary"
  if ! verify_archive_sha256 "$temp_binary" "$(tool_lock_value "$tool" binary_sha256 "$platform")"; then rm -f "$temp_binary" "$archive"; return 1; fi
  probe="$(tool_version_probe "$tool" "$temp_binary")"
  probe_matches_version "$tool" "$probe" "$version" || { echo "unexpected $tool version probe: $probe" >&2; rm -f "$temp_binary" "$archive"; return 1; }
  install_tool_with_provenance "$tool" "$platform" "$temp_binary" "$probe" || { rm -f "$temp_binary" "$archive"; return 1; }
  rm -f "$archive"
}
