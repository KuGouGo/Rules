#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CUSTOM_SRC_DIR="$ROOT/sources/custom/domain"
TMP_DIR="$ROOT/.tmp/custom"
BIN_DIR="$ROOT/.bin"
ARTIFACT_ROOT="$ROOT/.output"
SURGE_DIR="$ARTIFACT_ROOT/domain/surge"
SINGBOX_DIR="$ARTIFACT_ROOT/domain/sing-box"
MIHOMO_DIR="$ARTIFACT_ROOT/domain/mihomo"

mkdir -p "$SURGE_DIR" "$SINGBOX_DIR" "$MIHOMO_DIR" "$TMP_DIR" "$BIN_DIR"
rm -f "$TMP_DIR"/*

shopt -s nullglob
custom_lists=("$CUSTOM_SRC_DIR"/*.list)
if [ ${#custom_lists[@]} -eq 0 ]; then
  echo "no custom domain lists found, skip"
  exit 0
fi

write_if_changed() {
  local src="$1"
  local dst="$2"

  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    return 0
  fi

  mv "$src" "$dst"
}

build_plain_and_surge() {
  local list_file="$1"
  local base surge_out plain_out surge_tmp plain_tmp
  base="$(basename "$list_file" .list)"
  surge_out="$SURGE_DIR/$base.list"
  plain_out="$TMP_DIR/$base.list"
  surge_tmp="$TMP_DIR/$base.surge.tmp"
  plain_tmp="$TMP_DIR/$base.plain.tmp"

  : > "$surge_tmp"
  : > "$plain_tmp"

  awk -F, '
    BEGIN {
      OFS="\n"
    }
    /^[[:space:]]*$/ || /^[[:space:]]*#/ {
      next
    }
    NF < 2 {
      next
    }
    {
      type=$1
      value=$2
      sub(/\r$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", type)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (type == "DOMAIN") {
        print value >> surge
        print value >> plain
      } else if (type == "DOMAIN-SUFFIX") {
        print "." value >> surge
        print "." value >> plain
      }
    }
  ' surge="$surge_tmp" plain="$plain_tmp" "$list_file"

  write_if_changed "$surge_tmp" "$surge_out"
  mv "$plain_tmp" "$plain_out"
  rm -f "$surge_tmp"
}

ensure_sing_box() {
  if command -v sing-box >/dev/null 2>&1; then
    return 0
  fi

  if [ ! -x "$BIN_DIR/sing-box" ] && [ ! -x "$BIN_DIR/sing-box.exe" ]; then
    local ver raw_os os arch archive package_dir exe_name
    ver="1.13.2"
    raw_os="$(uname -s)"
    os="$(printf '%s' "$raw_os" | tr '[:upper:]' '[:lower:]')"
    case "$raw_os" in
      MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    esac
    arch="$(uname -m)"
    case "$arch" in
      x86_64) arch="amd64" ;;
      arm64|aarch64) arch="arm64" ;;
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
    esac
    if [ "$os" = "windows" ]; then
      archive="$BIN_DIR/sing-box.zip"
      package_dir="sing-box-${ver}-${os}-${arch}"
      exe_name="sing-box.exe"
      curl -fL -o "$archive" "https://github.com/SagerNet/sing-box/releases/download/v${ver}/${package_dir}.zip"
      unzip -oq "$archive" -d "$BIN_DIR"
      mv "$BIN_DIR/$package_dir/$exe_name" "$BIN_DIR/$exe_name"
      chmod +x "$BIN_DIR/$exe_name"
      rm -rf "$BIN_DIR/$package_dir" "$archive"
    else
      archive="$BIN_DIR/sing-box.tar.gz"
      package_dir="sing-box-${ver}-${os}-${arch}"
      curl -fL -o "$archive" "https://github.com/SagerNet/sing-box/releases/download/v${ver}/${package_dir}.tar.gz"
      tar -xzf "$archive" -C "$BIN_DIR"
      mv "$BIN_DIR/$package_dir/sing-box" "$BIN_DIR/sing-box"
      chmod +x "$BIN_DIR/sing-box"
      rm -rf "$BIN_DIR/$package_dir" "$archive"
    fi
  fi

  export PATH="$BIN_DIR:$PATH"
}

ensure_mihomo() {
  if command -v mihomo >/dev/null 2>&1; then
    return 0
  fi

  if [ ! -x "$BIN_DIR/mihomo" ] && [ ! -x "$BIN_DIR/mihomo.exe" ]; then
    local raw_os os arch asset archive
    raw_os="$(uname -s)"
    os="$(printf '%s' "$raw_os" | tr '[:upper:]' '[:lower:]')"
    case "$raw_os" in
      MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    esac
    arch="$(uname -m)"
    if [ "$os" = "windows" ]; then
      case "$arch" in
        x86_64) asset="mihomo-windows-amd64-compatible-v1.19.21.zip" ;;
        arm64|aarch64) asset="mihomo-windows-arm64-v1.19.21.zip" ;;
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
      esac
      archive="$BIN_DIR/mihomo.zip"
      curl -fL -o "$archive" "https://github.com/MetaCubeX/mihomo/releases/latest/download/${asset}"
      unzip -oq "$archive" -d "$BIN_DIR/mihomo-extract"
      mv "$BIN_DIR/mihomo-extract/mihomo.exe" "$BIN_DIR/mihomo.exe"
      chmod +x "$BIN_DIR/mihomo.exe"
      rm -rf "$BIN_DIR/mihomo-extract" "$archive"
    else
      case "$arch" in
        x86_64) asset="mihomo-${os}-amd64-compatible-v1.19.21.gz" ;;
        arm64|aarch64) asset="mihomo-${os}-arm64-v1.19.21.gz" ;;
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
      esac
      archive="$BIN_DIR/mihomo.gz"
      curl -fL -o "$archive" "https://github.com/MetaCubeX/mihomo/releases/latest/download/${asset}"
      gzip -df "$archive"
      chmod +x "$BIN_DIR/mihomo"
    fi
  fi

  export PATH="$BIN_DIR:$PATH"
}

build_binaries() {
  local plain_list="$1"
  local base json srs_tmp mrs_tmp domains suffixes
  base="$(basename "$plain_list" .list)"
  json="$TMP_DIR/$base.json"
  srs_tmp="$TMP_DIR/$base.srs.tmp"
  mrs_tmp="$TMP_DIR/$base.mrs.tmp"
  domains="$(awk 'NF && $0 !~ /^\./ { printf "\"%s\",", $0 }' "$plain_list" | sed 's/,$//')"
  suffixes="$(awk 'NF && $0 ~ /^\./ { value=$0; sub(/^\./, "", value); printf "\"%s\",", value }' "$plain_list" | sed 's/,$//')"

  {
    printf '{"version":3,"rules":[{'
    if [ -n "$domains" ]; then
      printf '"domain":[%s]' "$domains"
    fi
    if [ -n "$suffixes" ]; then
      if [ -n "$domains" ]; then
        printf ','
      fi
      printf '"domain_suffix":[%s]' "$suffixes"
    fi
    printf '}]}'
  } > "$json"

  sing-box rule-set compile "$json" --output "$srs_tmp"
  write_if_changed "$srs_tmp" "$SINGBOX_DIR/$base.srs"

  if mihomo convert-ruleset domain text "$plain_list" "$mrs_tmp" >/dev/null 2>&1; then
    write_if_changed "$mrs_tmp" "$MIHOMO_DIR/$base.mrs"
  else
    echo "failed to build mihomo ruleset for $base" >&2
    return 1
  fi
}

tracked_custom_bases="$(find "$CUSTOM_SRC_DIR" -maxdepth 1 -type f -name '*.list' -exec basename {} .list \; | sort)"

is_tracked_custom_base() {
  local name="$1"
  printf '%s\n' "$tracked_custom_bases" | grep -Fxq "$name"
}

assert_no_name_conflict() {
  local base="$1"
  local conflicts=()

  if is_tracked_custom_base "$base"; then
    return 0
  fi

  for tracked_path in \
    ".output/domain/surge/$base.list" \
    ".output/domain/sing-box/$base.srs" \
    ".output/domain/mihomo/$base.mrs"; do
    if [ -e "$ROOT/$tracked_path" ]; then
      conflicts+=("$tracked_path")
    fi
  done

  if [ ${#conflicts[@]} -gt 0 ]; then
    echo "custom rule name conflict detected for base '$base'" >&2
    printf 'conflicting generated files:\n' >&2
    printf '  - %s\n' "${conflicts[@]}" >&2
    echo "rename $CUSTOM_SRC_DIR/$base.list to a unique name and retry" >&2
    return 1
  fi
}

for list_file in "${custom_lists[@]}"; do
  base="$(basename "$list_file" .list)"
  assert_no_name_conflict "$base"
  build_plain_and_surge "$list_file"
done

ensure_sing_box
ensure_mihomo

for plain_list in "$TMP_DIR"/*.list; do
  [ -f "$plain_list" ] || continue
  build_binaries "$plain_list"
done

echo "custom build done"
