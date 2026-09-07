#!/usr/bin/env bash

: "${ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${BIN_DIR:=$ROOT/.bin}"

SING_BOX_VERSION="1.14.0"
MIHOMO_VERSION="1.19.30"

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

export GIT_HTTP_LOW_SPEED_LIMIT=${GIT_HTTP_LOW_SPEED_LIMIT:-1000}
export GIT_HTTP_LOW_SPEED_TIME=${GIT_HTTP_LOW_SPEED_TIME:-60}

download_files_parallel() {
  if [ $(( $# % 4 )) -ne 0 ]; then
    echo "parallel download expects groups of: label mode url output" >&2
    return 2
  fi

  local log_dir="${RULES_DOWNLOAD_LOG_DIR:-${WORK_TMP_DIR:-}}"
  if [ -z "$log_dir" ]; then
    echo "parallel download log directory is not configured" >&2
    return 2
  fi
  mkdir -p "$log_dir"

  local -a labels=() modes=() urls=() outputs=() pids=() logs=()
  local label mode url output log index failed=0
  while [ "$#" -gt 0 ]; do
    label="$1"
    mode="$2"
    url="$3"
    output="$4"
    shift 4
    case "$mode" in
      required|classified) ;;
      *) echo "unsupported download mode for $label: $mode" >&2; return 2 ;;
    esac
    labels+=("$label")
    modes+=("$mode")
    urls+=("$url")
    outputs+=("$output")
  done

  for index in "${!labels[@]}"; do
    log="$log_dir/download-${index}.log"
    logs+=("$log")
    download_file "${urls[$index]}" "${outputs[$index]}" >"$log" 2>&1 &
    pids+=("$!")
  done

  for index in "${!labels[@]}"; do
    if wait "${pids[$index]}"; then
      cat "${logs[$index]}"
    else
      cat "${logs[$index]}" >&2
      rm -f "${outputs[$index]}"
      if [ "${modes[$index]}" = "required" ]; then
        echo "required download failed: ${labels[$index]}" >&2
        failed=1
      fi
    fi
    rm -f "${logs[$index]}"
  done

  [ "$failed" -eq 0 ]
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

tool_is_ready() {
  local tool="$1"
  local version="$2"
  local binary="$BIN_DIR/$tool"

  [ -x "$binary" ] || return 1
  probe_matches_version "$tool" "$(tool_version_probe "$tool" "$binary")" "$version"
}

ensure_tool() {
  local tool="$1"
  local version="$2"
  local repository="$3"
  local asset_pattern="$4"
  local archive_format="$5"

  local os arch platform asset archive temp_binary package_dir probe
  setup_tool_cache
  os="$(require_non_windows_shell)"
  [ "$os" = "linux" ] || { echo "binary tools only ship linux assets: $tool on $os is unsupported" >&2; return 1; }
  arch="$(detect_arch)"
  platform="${os}-${arch}"

  if tool_is_ready "$tool" "$version"; then
    return 0
  fi

  asset="$(printf '%s' "$asset_pattern" | sed "s/{version}/${version}/g; s/{platform}/${platform}/g")"
  archive="$BIN_DIR/$tool.download.$archive_format"
  temp_binary="$BIN_DIR/$tool.download"
  package_dir=""

  discard_download() {
    rm -f "$temp_binary" "$archive"
    [ -z "$package_dir" ] || rm -rf "${BIN_DIR:?}/$package_dir"
  }

  download_file "https://github.com/${repository}/releases/download/v${version}/${asset}" "$archive" || {
    discard_download; return 1; }

  case "$archive_format" in
    tar.gz)
      package_dir="${tool}-${version}-${platform}"
      rm -rf "${BIN_DIR:?}/$package_dir"
      tar -xzf "$archive" -C "$BIN_DIR"
      mv "$BIN_DIR/$package_dir/$tool" "$temp_binary"
      ;;
    gz)
      gzip -dc "$archive" > "$temp_binary"
      ;;
  esac

  chmod +x "$temp_binary"
  probe="$(tool_version_probe "$tool" "$temp_binary")"
  probe_matches_version "$tool" "$probe" "$version" || {
    echo "unexpected $tool version probe: $probe" >&2
    discard_download
    return 1
  }

  mv -f "$temp_binary" "$BIN_DIR/$tool"
  discard_download
}

ensure_sing_box() {
  ensure_tool "sing-box" "$SING_BOX_VERSION" "SagerNet/sing-box" 'sing-box-{version}-{platform}.tar.gz' "tar.gz"
}

ensure_mihomo() {
  if [ "$(detect_arch)" = "arm64" ]; then
    ensure_tool "mihomo" "$MIHOMO_VERSION" "MetaCubeX/mihomo" 'mihomo-{platform}-v{version}.gz' "gz"
  else
    ensure_tool "mihomo" "$MIHOMO_VERSION" "MetaCubeX/mihomo" 'mihomo-{platform}-compatible-v{version}.gz' "gz"
  fi
}
