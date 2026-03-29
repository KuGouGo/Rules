#!/usr/bin/env bash

: "${ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${BIN_DIR:=$ROOT/.bin}"

SING_BOX_VERSION="${SING_BOX_VERSION:-}"
MIHOMO_VERSION="${MIHOMO_VERSION:-}"

mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

write_if_changed() {
  local src="$1"
  local dst="$2"

  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    rm -f "$src"
    return 0
  fi

  mv "$src" "$dst"
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
  curl --retry 3 --retry-all-errors --connect-timeout 20 --max-time 300 -fL "$url" -o "$out"
}

github_api_get() {
  local url="$1"
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  local -a args=(
    --retry 3
    --retry-all-errors
    --connect-timeout 20
    --max-time 60
    -fsSL
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: KuGouGo-Rules"
  )

  if [ -n "$token" ]; then
    args+=(-H "Authorization: Bearer $token")
  fi

  curl "${args[@]}" "$url"
}

github_latest_release_tag() {
  local repo="$1"
  local json tag
  json="$(github_api_get "https://api.github.com/repos/${repo}/releases/latest")"
  tag="$(printf '%s\n' "$json" | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"

  if [ -z "$tag" ]; then
    echo "failed to resolve latest release tag for ${repo}" >&2
    return 1
  fi

  printf '%s' "$tag"
}

normalize_version() {
  local version="$1"
  printf '%s' "${version#v}"
}

resolve_sing_box_version() {
  if [ -n "$SING_BOX_VERSION" ]; then
    printf '%s' "$SING_BOX_VERSION"
    return 0
  fi

  SING_BOX_VERSION="$(normalize_version "$(github_latest_release_tag 'SagerNet/sing-box')")"
  printf '%s' "$SING_BOX_VERSION"
}

resolve_mihomo_version() {
  if [ -n "$MIHOMO_VERSION" ]; then
    printf '%s' "$MIHOMO_VERSION"
    return 0
  fi

  MIHOMO_VERSION="$(normalize_version "$(github_latest_release_tag 'MetaCubeX/mihomo')")"
  printf '%s' "$MIHOMO_VERSION"
}

tool_version_file() {
  local tool_name="$1"
  printf '%s/%s.version' "$BIN_DIR" "$tool_name"
}

tool_is_current() {
  local executable="$1"
  local expected_version="$2"
  local version_file
  version_file="$(tool_version_file "$executable")"

  if [ ! -f "$version_file" ]; then
    return 1
  fi

  [ "$(<"$version_file")" = "$expected_version" ]
}

write_tool_version() {
  local executable="$1"
  local version="$2"
  printf '%s\n' "$version" > "$(tool_version_file "$executable")"
}

ensure_sing_box() {
  local version os arch archive package_dir
  version="$(resolve_sing_box_version)"

  if [ -x "$BIN_DIR/sing-box" ] && tool_is_current "sing-box" "$version"; then
    export PATH="$BIN_DIR:$PATH"
    return 0
  fi

  rm -f "$BIN_DIR/sing-box" "$(tool_version_file "sing-box")"

  os="$(require_non_windows_shell)"
  arch="$(detect_arch)"

  archive="$BIN_DIR/sing-box.tar.gz"
  package_dir="sing-box-${version}-${os}-${arch}"
  download_file \
    "https://github.com/SagerNet/sing-box/releases/download/v${version}/${package_dir}.tar.gz" \
    "$archive"
  tar -xzf "$archive" -C "$BIN_DIR"
  mv "$BIN_DIR/$package_dir/sing-box" "$BIN_DIR/sing-box"
  chmod +x "$BIN_DIR/sing-box"
  rm -rf "$BIN_DIR/$package_dir" "$archive"

  write_tool_version "sing-box" "$version"

  export PATH="$BIN_DIR:$PATH"
}

ensure_mihomo() {
  local version os arch asset archive
  version="$(resolve_mihomo_version)"

  if [ -x "$BIN_DIR/mihomo" ] && tool_is_current "mihomo" "$version"; then
    export PATH="$BIN_DIR:$PATH"
    return 0
  fi

  rm -f "$BIN_DIR/mihomo" "$(tool_version_file "mihomo")"

  os="$(require_non_windows_shell)"
  arch="$(detect_arch)"

  case "$arch" in
    amd64) asset="mihomo-${os}-amd64-compatible-v${version}.gz" ;;
    arm64) asset="mihomo-${os}-arm64-v${version}.gz" ;;
  esac
  archive="$BIN_DIR/mihomo.gz"
  download_file \
    "https://github.com/MetaCubeX/mihomo/releases/download/v${version}/${asset}" \
    "$archive"
  gzip -df "$archive"
  chmod +x "$BIN_DIR/mihomo"

  write_tool_version "mihomo" "$version"

  export PATH="$BIN_DIR:$PATH"
}
