#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.work"
DIST="$ROOT/dist"
BIN="$WORK/bin"
UPSTREAM="$WORK/upstream"
INPUT="$ROOT/input"

mkdir -p "$BIN" "$UPSTREAM" "$DIST" "$INPUT"

export PATH="/usr/local/go/bin:/opt/homebrew/bin:/opt/homebrew/opt/go/bin:$PATH"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd curl
need_cmd unzip
need_cmd go

clone_or_update() {
  local repo_url="$1"
  local dir="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --depth=1 origin
    git -C "$dir" reset --hard origin/HEAD
  else
    git clone --depth=1 "$repo_url" "$dir"
  fi
}

clone_or_update https://github.com/nekolsd/sing-geosite.git "$UPSTREAM/sing-geosite"
clone_or_update https://github.com/nekolsd/geoip.git "$UPSTREAM/geoip"

mkdir -p "$DIST/geosite" "$DIST/geoip"

pushd "$UPSTREAM/sing-geosite" >/dev/null
go build -o "$BIN/sing-geosite" .
"$BIN/sing-geosite"
rm -rf "$DIST/geosite/surge" "$DIST/geosite/sing-box"
mkdir -p "$DIST/geosite/surge" "$DIST/geosite/sing-box"
cp -R domain-set/. "$DIST/geosite/surge/"
cp -R rule-set/. "$DIST/geosite/sing-box/"
popd >/dev/null

if [ ! -f "$INPUT/Country.mmdb" ]; then
  echo "missing input/Country.mmdb" >&2
  echo "download one, for example from Loyalsoldier/geoip release, then rerun" >&2
  exit 1
fi

pushd "$UPSTREAM/geoip" >/dev/null
go build -o "$BIN/geoip" .
"$BIN/geoip" convert -c "$ROOT/configs/geoip-convert.json"
popd >/dev/null

echo "build complete: $DIST"
