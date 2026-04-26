#!/usr/bin/env bash

: "${ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# Keep Surge IP rule behavior stable by default.
# Set SURGE_IP_APPEND_NO_RESOLVE=0 to omit no-resolve for A/B verification.
: "${SURGE_IP_APPEND_NO_RESOLVE:=1}"
# Set RULES_COMPILE_JOBS to override local binary compile parallelism.
: "${RULES_COMPILE_JOBS:=}"

SINGBOX_RULE_SET_SOURCE_VERSION_CACHE="${SINGBOX_RULE_SET_SOURCE_VERSION_CACHE:-}"

is_positive_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac

  [ "$1" -gt 0 ]
}

detect_compile_jobs() {
  local jobs cpus

  jobs="$RULES_COMPILE_JOBS"
  if [ -n "$jobs" ]; then
    if ! is_positive_integer "$jobs"; then
      echo "RULES_COMPILE_JOBS must be a positive integer" >&2
      return 1
    fi
    printf '%s' "$jobs"
    return 0
  fi

  cpus=""
  if command -v getconf >/dev/null 2>&1; then
    cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  fi
  if ! is_positive_integer "$cpus" && command -v sysctl >/dev/null 2>&1; then
    cpus="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  fi
  if ! is_positive_integer "$cpus" && command -v nproc >/dev/null 2>&1; then
    cpus="$(nproc 2>/dev/null || true)"
  fi
  if ! is_positive_integer "$cpus"; then
    cpus=1
  fi
  if [ "$cpus" -gt 4 ]; then
    cpus=4
  fi

  printf '%s' "$cpus"
}

singbox_rule_set_source_version_for_release() {
  local version="$1"
  local major minor rest

  version="${version#v}"
  major="${version%%.*}"
  rest="${version#*.}"
  if [ "$rest" = "$version" ]; then
    minor=0
  else
    minor="${rest%%.*}"
  fi
  major="${major//[^0-9]/}"
  minor="${minor//[^0-9]/}"
  major="${major:-0}"
  minor="${minor:-0}"

  if [ "$major" -gt 1 ]; then
    printf '5'
  elif [ "$major" -lt 1 ]; then
    printf '1'
  elif [ "$minor" -ge 14 ]; then
    printf '5'
  elif [ "$minor" -ge 13 ]; then
    printf '4'
  elif [ "$minor" -ge 11 ]; then
    printf '3'
  elif [ "$minor" -ge 10 ]; then
    printf '2'
  else
    printf '1'
  fi
}

detect_singbox_rule_set_source_version() {
  local version_line version

  if [ -n "${SINGBOX_RULE_SET_VERSION:-}" ]; then
    printf '%s' "$SINGBOX_RULE_SET_VERSION"
    return 0
  fi

  if [ -n "$SINGBOX_RULE_SET_SOURCE_VERSION_CACHE" ]; then
    printf '%s' "$SINGBOX_RULE_SET_SOURCE_VERSION_CACHE"
    return 0
  fi

  if version_line="$(sing-box version 2>/dev/null | head -n 1)" && [ -n "$version_line" ]; then
    version="${version_line##* }"
    SINGBOX_RULE_SET_SOURCE_VERSION_CACHE="$(singbox_rule_set_source_version_for_release "$version")"
  else
    SINGBOX_RULE_SET_SOURCE_VERSION_CACHE="4"
  fi

  printf '%s' "$SINGBOX_RULE_SET_SOURCE_VERSION_CACHE"
}

ensure_rule_build_tools() {
  ensure_sing_box
  ensure_mihomo
}

dedupe_file_in_place() {
  local file="$1"
  local tmp_file="${file}.dedupe"
  awk 'NF && !seen[$0]++' "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

normalize_custom_domain_source() {
  local input_file="$1"
  local output_file="$2"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" normalize-classical "$input_file" "$output_file"
}

build_domain_json_from_rules() {
  local rule_list="$1"
  local json_out="$2"
  local source_version

  source_version="${SINGBOX_RULE_SET_VERSION:-4}"

  SINGBOX_RULE_SET_VERSION="$source_version" \
    python3 "$ROOT/scripts/tools/export-domain-rules.py" singbox-json "$rule_list" "$json_out"
}

render_surge_domain_ruleset_from_rules() {
  local rule_list="$1"
  local surge_out="$2"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" surge-list "$rule_list" "$surge_out"
}

render_quanx_domain_ruleset_from_rules() {
  local rule_list="$1"
  local quanx_out="$2"
  local policy_tag="$3"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" quanx-list "$rule_list" "$quanx_out" "$policy_tag"
}

render_egern_domain_ruleset_from_rules() {
  local rule_list="$1"
  local egern_out="$2"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" egern-yaml "$rule_list" "$egern_out"
}

render_domain_rule_dir_to_text_platform_dirs() {
  local rule_dir="$1"
  local surge_dir="$2"
  local quanx_dir="$3"
  local egern_dir="$4"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" text-platform-dirs \
    "$rule_dir" \
    "$surge_dir" \
    "$quanx_dir" \
    "$egern_dir"
}

compile_domain_rule_list_to_artifacts() {
  local rule_list="$1"
  local json_out="$2"
  local srs_out="$3"
  local source_version

  source_version="$(detect_singbox_rule_set_source_version)"

  SINGBOX_RULE_SET_VERSION="$source_version" \
    build_domain_json_from_rules "$rule_list" "$json_out"
  sing-box rule-set compile "$json_out" --output "$srs_out"
}

build_mihomo_domain_text_from_rules() {
  local rule_list="$1"
  local plain_out="$2"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" mihomo-text "$rule_list" "$plain_out"

}

compile_mihomo_domain_plain_to_binary_artifact() {
  local plain_list="$1"
  local mrs_out="$2"

  mihomo convert-ruleset domain text "$plain_list" "$mrs_out" >/dev/null
}

compile_domain_singbox_json_dir() {
  local tmp_dir="$1"
  local singbox_dir="$2"
  local jobs="$3"
  local list_file="$tmp_dir/.singbox-json-files"

  find "$tmp_dir" -maxdepth 1 -type f -name '*.json' -print0 > "$list_file"
  if [ ! -s "$list_file" ]; then
    return 0
  fi

  # shellcheck disable=SC2016
  xargs -0 -n 1 -P "$jobs" sh -c '
    out_dir="$1"
    json="$2"
    base="$(basename "$json" .json)"
    sing-box rule-set compile "$json" --output "$out_dir/$base.srs"
  ' sh "$singbox_dir" < "$list_file"
}

compile_domain_mihomo_text_dir() {
  local tmp_dir="$1"
  local mihomo_dir="$2"
  local jobs="$3"
  local list_file="$tmp_dir/.mihomo-text-files"

  find "$tmp_dir" -maxdepth 1 -type f -name '*.mihomo.txt' -size +0c -print0 > "$list_file"
  if [ ! -s "$list_file" ]; then
    return 0
  fi

  # shellcheck disable=SC2016
  xargs -0 -n 1 -P "$jobs" sh -c '
    out_dir="$1"
    plain="$2"
    base="$(basename "$plain" .mihomo.txt)"
    mihomo convert-ruleset domain text "$plain" "$out_dir/$base.mrs" >/dev/null
  ' sh "$mihomo_dir" < "$list_file"
}

build_domain_artifacts_from_rule_dir() {
  local rule_dir="$1"
  local tmp_dir="$2"
  local singbox_dir="$3"
  local mihomo_dir="$4"
  local mihomo_txt source_version compile_jobs
  local mihomo_built=0
  local mihomo_skipped=0

  ensure_sing_box
  rm -rf "$singbox_dir" "$mihomo_dir" "$tmp_dir"
  mkdir -p "$singbox_dir" "$mihomo_dir" "$tmp_dir"
  source_version="$(detect_singbox_rule_set_source_version)"

  SINGBOX_RULE_SET_VERSION="$source_version" \
    python3 "$ROOT/scripts/tools/export-domain-rules.py" binary-input-dir "$rule_dir" "$tmp_dir"
  compile_jobs="$(detect_compile_jobs)"

  for mihomo_txt in "$tmp_dir"/*.mihomo.txt; do
    [ -f "$mihomo_txt" ] || continue
    if [ ! -s "$mihomo_txt" ]; then
      mihomo_skipped=$((mihomo_skipped + 1))
      continue
    fi
    mihomo_built=$((mihomo_built + 1))
  done

  echo "domain binary compile jobs: $compile_jobs"
  compile_domain_singbox_json_dir "$tmp_dir" "$singbox_dir" "$compile_jobs"

  if [ "$mihomo_built" -gt 0 ]; then
    ensure_mihomo
    compile_domain_mihomo_text_dir "$tmp_dir" "$mihomo_dir" "$compile_jobs"
  fi

  if [ "$mihomo_skipped" -gt 0 ]; then
    echo "skipped mihomo domain artifacts for $mihomo_skipped list(s) without DOMAIN/DOMAIN-SUFFIX entries" >&2
  fi

  if [ "$mihomo_built" -eq 0 ]; then
    echo "warning: no mihomo domain artifacts were generated" >&2
  fi
}

normalize_ip_rule_source() {
  local input_file="$1"
  local surge_out="$2"
  local plain_out="$3"
  local raw_plain_out="${plain_out}.raw"

  : > "$raw_plain_out"

  awk -F, '
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
      if (type == "IP-CIDR" || type == "IP-CIDR6") {
        print value >> plain
      }
    }
  ' plain="$raw_plain_out" "$input_file"

  python3 "$ROOT/scripts/tools/normalize-ip-rules.py" single text "$raw_plain_out" "$plain_out"
  render_ip_plain_to_surge_list "$plain_out" "$surge_out"
  rm -f "$raw_plain_out"
}

normalize_ip_surge_list_to_plain() {
  local input_file="$1"
  local plain_out="$2"
  local raw_plain_out="${plain_out}.raw"

  awk -F, '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    $1 == "IP-CIDR" || $1 == "IP-CIDR6" {
      value=$2
      gsub(/\r$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value != "") print value
    }
  ' "$input_file" > "$raw_plain_out"

  python3 "$ROOT/scripts/tools/normalize-ip-rules.py" single text "$raw_plain_out" "$plain_out"
  rm -f "$raw_plain_out"
}

render_ip_plain_to_surge_list() {
  local plain_list="$1"
  local surge_out="$2"

  awk -v append_no_resolve="$SURGE_IP_APPEND_NO_RESOLVE" '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    {
      value=$0
      gsub(/\r$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value == "") {
        next
      }
      type = (value ~ /:/ ? "IP-CIDR6" : "IP-CIDR")
      suffix = (append_no_resolve == "1" ? ",no-resolve" : "")
      printf "%s,%s%s\n", type, value, suffix
    }
  ' "$plain_list" > "$surge_out"

  dedupe_file_in_place "$surge_out"
}

render_ip_plain_to_quanx_list() {
  local plain_list="$1"
  local quanx_out="$2"
  local policy_tag="$3"

  awk -v policy="$policy_tag" '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    {
      value=$0
      gsub(/\r$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value == "") {
        next
      }
      type = (value ~ /:/ ? "IP6-CIDR" : "IP-CIDR")
      printf "%s,%s,%s\n", type, value, policy
    }
  ' "$plain_list" > "$quanx_out"

  dedupe_file_in_place "$quanx_out"
}

render_ip_plain_to_egern_yaml() {
  local plain_list="$1"
  local egern_out="$2"

  python3 - "$plain_list" "$egern_out" <<'PY'
import sys

plain_list, output_file = sys.argv[1], sys.argv[2]
ipv4_entries = []
ipv6_entries = []
seen = set()

def yaml_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"

with open(plain_list, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line in seen:
            continue
        seen.add(line)
        if ":" in line:
            ipv6_entries.append(line)
        else:
            ipv4_entries.append(line)

with open(output_file, "w", encoding="utf-8") as fh:
    chunks = []
    if ipv4_entries:
        chunks.append("ip_cidr_set:\n" + "\n".join(f"  - {yaml_quote(value)}" for value in ipv4_entries))
    if ipv6_entries:
        chunks.append("ip_cidr6_set:\n" + "\n".join(f"  - {yaml_quote(value)}" for value in ipv6_entries))
    if chunks:
        fh.write("no_resolve: true\n")
        fh.write("\n")
        fh.write("\n\n".join(chunks))
        fh.write("\n")
PY
}

build_ip_json_from_plain() {
  local plain_list="$1"
  local json_out="$2"
  local source_version

  source_version="${SINGBOX_RULE_SET_VERSION:-4}"

  SINGBOX_RULE_SET_VERSION="$source_version" \
    python3 "$ROOT/scripts/tools/normalize-ip-rules.py" singbox-json "$plain_list" "$json_out"
}

compile_ip_plain_to_binary_artifacts() {
  local plain_list="$1"
  local json_out="$2"
  local srs_out="$3"
  local mrs_out="$4"
  local source_version

  source_version="$(detect_singbox_rule_set_source_version)"

  SINGBOX_RULE_SET_VERSION="$source_version" \
    build_ip_json_from_plain "$plain_list" "$json_out"
  sing-box rule-set compile "$json_out" --output "$srs_out"
  mihomo convert-ruleset ipcidr text "$plain_list" "$mrs_out" >/dev/null
}

build_ip_artifacts_from_surge_dir() {
  local surge_dir="$1"
  local tmp_dir="$2"
  local singbox_dir="$3"
  local mihomo_dir="$4"
  local list base plain_txt json srs_out mrs_out

  ensure_rule_build_tools
  rm -rf "$singbox_dir" "$mihomo_dir"
  mkdir -p "$singbox_dir" "$mihomo_dir" "$tmp_dir"

  for list in "$surge_dir"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    plain_txt="$tmp_dir/$base.txt"
    json="$tmp_dir/$base.json"
    srs_out="$singbox_dir/$base.srs"
    mrs_out="$mihomo_dir/$base.mrs"

    normalize_ip_surge_list_to_plain "$list" "$plain_txt"
    if [ ! -s "$plain_txt" ]; then
      echo "skipping empty IP list: $base" >&2
      continue
    fi
    compile_ip_plain_to_binary_artifacts "$plain_txt" "$json" "$srs_out" "$mrs_out"
  done
}

build_ip_egern_artifacts_from_surge_dir() {
  local surge_dir="$1"
  local tmp_dir="$2"
  local egern_dir="$3"
  local list base plain_txt yaml_out

  rm -rf "$egern_dir"
  mkdir -p "$egern_dir" "$tmp_dir"

  for list in "$surge_dir"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    plain_txt="$tmp_dir/$base.egern.txt"
    yaml_out="$egern_dir/$base.yaml"

    normalize_ip_surge_list_to_plain "$list" "$plain_txt"
    if [ ! -s "$plain_txt" ]; then
      echo "skipping empty IP list for egern: $base" >&2
      continue
    fi
    render_ip_plain_to_egern_yaml "$plain_txt" "$yaml_out"
  done
}
