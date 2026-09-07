#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/scripts/commands/check-runtime.sh"

TEXT_ONLY_MODE="${RULES_BUILD_CUSTOM_TEXT_ONLY:-0}"

"$ROOT/scripts/commands/lint-custom-rules.sh"

CUSTOM_DOMAIN_DIR="$ROOT/sources/custom/domain"
CUSTOM_IP_DIR="$ROOT/sources/custom/ip"
TMP_PARENT_DIR="$ROOT/.tmp"
mkdir -p "$TMP_PARENT_DIR"
TMP_DIR="$(mktemp -d "$TMP_PARENT_DIR/custom.XXXXXX")"
TMP_DOMAIN_DIR="$TMP_DIR/domain"
TMP_IP_DIR="$TMP_DIR/ip"
STAGE_ROOT="$TMP_DIR/output"
CANONICAL_STAGE_ROOT="$TMP_DIR/canonical"
BIN_DIR="$ROOT/.bin"
ARTIFACT_ROOT="${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
CUSTOM_NAMES_FILE="$ARTIFACT_ROOT/custom-lists.json"
DOMAIN_SURGE_DIR="$STAGE_ROOT/domain/surge"
DOMAIN_QUANX_DIR="$STAGE_ROOT/domain/quanx"
DOMAIN_EGERN_DIR="$STAGE_ROOT/domain/egern"
DOMAIN_SINGBOX_DIR="$STAGE_ROOT/domain/sing-box"
DOMAIN_MIHOMO_DIR="$STAGE_ROOT/domain/mihomo"
IP_SURGE_DIR="$STAGE_ROOT/ip/surge"
IP_QUANX_DIR="$STAGE_ROOT/ip/quanx"
IP_EGERN_DIR="$STAGE_ROOT/ip/egern"
IP_SINGBOX_DIR="$STAGE_ROOT/ip/sing-box"
IP_MIHOMO_DIR="$STAGE_ROOT/ip/mihomo"

# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/rules.sh"
setup_tool_cache

DOMAIN_RULE_FILES="$(list_rule_files "$CUSTOM_DOMAIN_DIR")"
IP_RULE_FILES="$(list_rule_files "$CUSTOM_IP_DIR")"

mkdir -p \
  "$DOMAIN_SURGE_DIR" \
  "$DOMAIN_QUANX_DIR" \
  "$DOMAIN_EGERN_DIR" \
  "$DOMAIN_SINGBOX_DIR" \
  "$DOMAIN_MIHOMO_DIR" \
  "$IP_SURGE_DIR" \
  "$IP_QUANX_DIR" \
  "$IP_EGERN_DIR" \
  "$IP_SINGBOX_DIR" \
  "$IP_MIHOMO_DIR" \
  "$BIN_DIR"
mkdir -p "$TMP_DOMAIN_DIR" "$TMP_IP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

has_custom_domain=0
has_custom_ip=0
if [ -n "$DOMAIN_RULE_FILES" ]; then
  has_custom_domain=1
fi
if [ -n "$IP_RULE_FILES" ]; then
  has_custom_ip=1
fi

if [ "$has_custom_domain" -eq 0 ] && [ "$has_custom_ip" -eq 0 ]; then
  echo "no custom rule lists found, skip"
  rm -f "$CUSTOM_NAMES_FILE"
  exit 0
fi

prepare_canonical_stage() {
  mkdir -p "$CANONICAL_STAGE_ROOT/domain" "$CANONICAL_STAGE_ROOT/ip"
  if [ -d "$ARTIFACT_ROOT/.canonical" ]; then
    cp -R "$ARTIFACT_ROOT/.canonical/." "$CANONICAL_STAGE_ROOT/"
  fi
}

previous_custom_names() {
  if [ -f "$CUSTOM_NAMES_FILE" ]; then
    python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))))' "$CUSTOM_NAMES_FILE"
  fi
}
PREVIOUS_CUSTOM_NAMES="$(previous_custom_names)"

is_previous_custom_name() {
  printf '%s\n' "$PREVIOUS_CUSTOM_NAMES" | grep -Fxq "$1"
}

assert_no_name_conflict() {
  local base="$1"
  local rel_path="$2"
  shift 2
  local tracked_path conflicts=()

  if is_previous_custom_name "$base"; then
    return 0
  fi

  for tracked_path in "$@"; do
    if [ -e "$ARTIFACT_ROOT/${tracked_path#.output/}" ]; then
      conflicts+=("$tracked_path")
    fi
  done

  if [ ${#conflicts[@]} -gt 0 ]; then
    echo "custom rule name conflict detected for base '$base'" >&2
    printf 'conflicting generated files:\n' >&2
    printf '  - %s\n' "${conflicts[@]}" >&2
    echo "rename the list to a unique name and retry: $rel_path" >&2
    return 1
  fi
}

print_domain_rule_stats() {
  local plain_list="$1"
  local base="$2"

  awk -F, -v name="$base" '
    $1 == "DOMAIN" { domain++ }
    $1 == "DOMAIN-SUFFIX" { suffix++ }
    $1 == "DOMAIN-KEYWORD" { keyword++ }
    $1 == "DOMAIN-REGEX" { regex++ }
    END {
      total = domain + suffix + keyword + regex
      printf "Building domain rules for %s: %d rules (DOMAIN=%d, SUFFIX=%d, KEYWORD=%d, REGEX=%d)\n", \
        name, total, domain, suffix, keyword, regex
    }
  ' "$plain_list"
}

print_ip_rule_stats() {
  local plain_list="$1"
  local base="$2"

  awk -v name="$base" '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    /:/ { ipv6++; next }
    { ipv4++ }
    END {
      printf "Building IP rules for %s: %d CIDRs (IPv4=%d, IPv6=%d)\n", \
        name, ipv4 + ipv6, ipv4, ipv6
    }
  ' "$plain_list"
}

build_domain_plain_and_surge() {
  local list_file="$1"
  local base surge_out quanx_out egern_out plain_out surge_tmp quanx_tmp egern_tmp
  base="$(basename "$list_file" .list)"
  surge_out="$DOMAIN_SURGE_DIR/$base.list"
  quanx_out="$DOMAIN_QUANX_DIR/$base.list"
  egern_out="$DOMAIN_EGERN_DIR/$base.yaml"
  plain_out="$TMP_DOMAIN_DIR/$base.list"
  surge_tmp="$TMP_DOMAIN_DIR/$base.surge.tmp"
  quanx_tmp="$TMP_DOMAIN_DIR/$base.quanx.tmp"
  egern_tmp="$TMP_DOMAIN_DIR/$base.egern.tmp"

  normalize_custom_domain_source "$list_file" "$plain_out"
  print_domain_rule_stats "$plain_out" "$base"
  cp "$plain_out" "$CANONICAL_STAGE_ROOT/domain/$base.list"
  render_surge_domain_ruleset_from_rules "$plain_out" "$surge_tmp"
  render_quanx_domain_ruleset_from_rules "$plain_out" "$quanx_tmp" "$base"
  render_egern_domain_ruleset_from_rules "$plain_out" "$egern_tmp"
  write_if_nonempty_or_remove "$surge_tmp" "$surge_out"
  write_if_nonempty_or_remove "$quanx_tmp" "$quanx_out"
  write_if_nonempty_or_remove "$egern_tmp" "$egern_out"
}

build_ip_plain_and_surge() {
  local list_file="$1"
  local base surge_out quanx_out egern_out plain_out surge_tmp quanx_tmp egern_tmp plain_tmp
  base="$(basename "$list_file" .list)"
  surge_out="$IP_SURGE_DIR/$base.list"
  quanx_out="$IP_QUANX_DIR/$base.list"
  egern_out="$IP_EGERN_DIR/$base.yaml"
  plain_out="$TMP_IP_DIR/$base.txt"
  surge_tmp="$TMP_IP_DIR/$base.surge.tmp"
  quanx_tmp="$TMP_IP_DIR/$base.quanx.tmp"
  egern_tmp="$TMP_IP_DIR/$base.egern.tmp"
  plain_tmp="$TMP_IP_DIR/$base.plain.tmp"

  normalize_ip_rule_source "$list_file" "$surge_tmp" "$plain_tmp"
  print_ip_rule_stats "$plain_tmp" "$base"
  render_ip_plain_to_quanx_list "$plain_tmp" "$quanx_tmp" "$base"
  render_ip_plain_to_egern_yaml "$plain_tmp" "$egern_tmp"
  write_if_nonempty_or_remove "$surge_tmp" "$surge_out"
  write_if_nonempty_or_remove "$quanx_tmp" "$quanx_out"
  write_if_nonempty_or_remove "$egern_tmp" "$egern_out"
  mv "$plain_tmp" "$plain_out"
  render_ip_plain_to_canonical_list "$plain_out" "$CANONICAL_STAGE_ROOT/ip/$base.list"
  rm -f "$surge_tmp" "$quanx_tmp" "$egern_tmp"
}

build_domain_binaries_parallel() {
  local jobs singbox_count mihomo_count

  jobs="$(detect_compile_jobs)"
  echo "Compiling domain binaries with $jobs parallel jobs..."

  compile_domain_singbox_json_dir "$TMP_DOMAIN_DIR" "$DOMAIN_SINGBOX_DIR" "$jobs"
  singbox_count="$(find "$DOMAIN_SINGBOX_DIR" -maxdepth 1 -type f -name '*.srs' -size +0c | wc -l | tr -d ' ')"
  echo "  sing-box: compiled $singbox_count rule-sets"

  ensure_mihomo
  compile_domain_mihomo_text_dir "$TMP_DOMAIN_DIR" "$DOMAIN_MIHOMO_DIR" "$jobs"
  mihomo_count="$(find "$DOMAIN_MIHOMO_DIR" -maxdepth 1 -type f -name '*.mrs' -size +0c | wc -l | tr -d ' ')"
  echo "  mihomo: compiled $mihomo_count rule-sets"
}

build_ip_json() {
  local plain_list="$1"
  local base json
  base="$(basename "$plain_list" .txt)"
  json="$TMP_IP_DIR/$base.json"

  SINGBOX_RULE_SET_VERSION="$(detect_singbox_rule_set_source_version)" \
    build_ip_json_from_plain "$plain_list" "$json" || {
      echo "failed to generate IP JSON for $base" >&2
      return 1
    }
}

build_ip_binaries_parallel() {
  local jobs singbox_count mihomo_count

  jobs="$(detect_compile_jobs)"
  echo "Compiling IP binaries with $jobs parallel jobs..."
  compile_ip_binary_dirs "$TMP_IP_DIR" "$IP_SINGBOX_DIR" "$IP_MIHOMO_DIR" "$jobs"

  singbox_count="$(find "$IP_SINGBOX_DIR" -maxdepth 1 -type f -name '*.srs' -size +0c | wc -l | tr -d ' ')"
  mihomo_count="$(find "$IP_MIHOMO_DIR" -maxdepth 1 -type f -name '*.mrs' -size +0c | wc -l | tr -d ' ')"
  echo "  sing-box: compiled $singbox_count rule-sets"
  echo "  mihomo: compiled $mihomo_count rule-sets"
}

prepare_canonical_stage

CUSTOM_NAMES=()
while IFS= read -r list_file; do
  [ -n "$list_file" ] || continue
  base="$(basename "$list_file" .list)"
  CUSTOM_NAMES+=("$base")
  assert_no_name_conflict \
    "$base" \
    "sources/custom/domain/$base.list" \
    "domain/surge/$base.list" \
    "domain/quanx/$base.list" \
    "domain/egern/$base.yaml" \
    "domain/sing-box/$base.srs" \
    "domain/mihomo/$base.mrs"
  build_domain_plain_and_surge "$list_file"
done <<< "$DOMAIN_RULE_FILES"

while IFS= read -r list_file; do
  [ -n "$list_file" ] || continue
  base="$(basename "$list_file" .list)"
  CUSTOM_NAMES+=("$base")
  assert_no_name_conflict \
    "$base" \
    "sources/custom/ip/$base.list" \
    "ip/surge/$base.list" \
    "ip/quanx/$base.list" \
    "ip/egern/$base.yaml" \
    "ip/sing-box/$base.srs" \
    "ip/mihomo/$base.mrs"
  build_ip_plain_and_surge "$list_file"
done <<< "$IP_RULE_FILES"

if [ "$TEXT_ONLY_MODE" -ne 1 ]; then
  ensure_sing_box
fi

if [ "$TEXT_ONLY_MODE" -ne 1 ] && [ "$has_custom_ip" -gt 0 ]; then
  ensure_mihomo
fi

if [ "$TEXT_ONLY_MODE" -ne 1 ]; then

  for plain_list in "$TMP_DOMAIN_DIR"/*.list; do
    [ -f "$plain_list" ] || continue
    base="$(basename "$plain_list" .list)"
    json="$TMP_DOMAIN_DIR/$base.json"
    mihomo_text_tmp="$TMP_DOMAIN_DIR/$base.mihomo.txt"

    SINGBOX_RULE_SET_VERSION="$(detect_singbox_rule_set_source_version)" \
      build_domain_json_from_rules "$plain_list" "$json" || {
        echo "failed to generate sing-box JSON for $base" >&2
        exit 1
      }
    build_mihomo_domain_text_from_rules "$plain_list" "$mihomo_text_tmp"
    if [ ! -s "$mihomo_text_tmp" ]; then
      echo "custom domain list $base has no DOMAIN/DOMAIN-SUFFIX entries; skip mihomo mrs" >&2
      rm -f "$DOMAIN_MIHOMO_DIR/$base.mrs" "$mihomo_text_tmp"
    fi
  done

  for plain_list in "$TMP_IP_DIR"/*.txt; do
    [ -f "$plain_list" ] || continue
    build_ip_json "$plain_list"
  done

  if compgen -G "$TMP_DOMAIN_DIR/*.list" >/dev/null; then
    build_domain_binaries_parallel
  fi

  if compgen -G "$TMP_IP_DIR/*.txt" >/dev/null; then
    build_ip_binaries_parallel
  fi
fi

commit_staged_custom_artifacts() {
  local relative staged target target_dir

  for relative in "${CONTROLLED_ARTIFACTS[@]}"; do
    staged="$STAGE_ROOT/$relative"
    target="$ARTIFACT_ROOT/$relative"
    target_dir="$(dirname "$target")"
    mkdir -p "$target_dir" || return 1
    if [ -f "$staged" ]; then
      write_if_changed "$staged" "$target" || return 1
    else
      rm -f "$target" || return 1
    fi
  done
}

controlled_artifact_paths() {
  local list_file base
  while IFS= read -r list_file; do
    [ -n "$list_file" ] || continue
    base="$(basename "$list_file" .list)"
    printf '%s\n' \
      "domain/surge/$base.list" \
      "domain/quanx/$base.list" \
      "domain/egern/$base.yaml"
    if [ "$TEXT_ONLY_MODE" -ne 1 ]; then
      printf '%s\n' \
        "domain/sing-box/$base.srs" \
        "domain/mihomo/$base.mrs"
    fi
  done <<< "$DOMAIN_RULE_FILES"

  while IFS= read -r list_file; do
    [ -n "$list_file" ] || continue
    base="$(basename "$list_file" .list)"
    printf '%s\n' \
      "ip/surge/$base.list" \
      "ip/quanx/$base.list" \
      "ip/egern/$base.yaml"
    if [ "$TEXT_ONLY_MODE" -ne 1 ]; then
      printf '%s\n' \
        "ip/sing-box/$base.srs" \
        "ip/mihomo/$base.mrs"
    fi
  done <<< "$IP_RULE_FILES"
}

controlled_artifact_paths > "$TMP_DIR/controlled-artifacts.list"
mapfile -t CONTROLLED_ARTIFACTS < "$TMP_DIR/controlled-artifacts.list"
commit_staged_custom_artifacts

rm -rf "$ARTIFACT_ROOT/.canonical"
cp -R "$CANONICAL_STAGE_ROOT" "$ARTIFACT_ROOT/.canonical"
python3 - "$CUSTOM_NAMES_FILE" "${CUSTOM_NAMES[@]}" <<'PY'
import json
import sys
import tempfile
import os

path, names = sys.argv[1], sys.argv[2:]
payload = json.dumps(sorted(names), indent=2) + "\n"
directory = os.path.dirname(path)
os.makedirs(directory, exist_ok=True)
with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=directory, delete=False) as handle:
    handle.write(payload)
    temp_path = handle.name
os.replace(temp_path, path)
PY

if [ "$TEXT_ONLY_MODE" -eq 1 ]; then
  echo "custom build done (text only)"
else
  echo "custom build done"
fi
