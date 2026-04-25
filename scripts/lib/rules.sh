#!/usr/bin/env bash

: "${ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# Keep Surge IP rule behavior stable by default.
# Set SURGE_IP_APPEND_NO_RESOLVE=0 to omit no-resolve for A/B verification.
: "${SURGE_IP_APPEND_NO_RESOLVE:=1}"

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

compile_domain_rule_list_to_artifacts() {
  local rule_list="$1"
  local json_out="$2"
  local srs_out="$3"

  build_domain_json_from_rules "$rule_list" "$json_out"
  sing-box rule-set compile "$json_out" --output "$srs_out"
}

render_domain_rule_dir_to_surge_dir() {
  local rule_dir="$1"
  local surge_dir="$2"
  local tmp_dir="$3"
  local list base surge_tmp surge_out

  rm -rf "$surge_dir"
  mkdir -p "$surge_dir" "$tmp_dir"

  for list in "$rule_dir"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    surge_tmp="$tmp_dir/$base.surge.tmp"
    surge_out="$surge_dir/$base.list"
    render_surge_domain_ruleset_from_rules "$list" "$surge_tmp"

    if [ ! -s "$surge_tmp" ]; then
      echo "domain list $base has no Surge-compatible DOMAIN/DOMAIN-SUFFIX/DOMAIN-KEYWORD entries" >&2
      return 1
    fi

    mv "$surge_tmp" "$surge_out"
  done
}

render_domain_rule_dir_to_quanx_dir() {
  local rule_dir="$1"
  local quanx_dir="$2"
  local tmp_dir="$3"
  local list base quanx_tmp quanx_out

  rm -rf "$quanx_dir"
  mkdir -p "$quanx_dir" "$tmp_dir"

  for list in "$rule_dir"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    quanx_tmp="$tmp_dir/$base.quanx.tmp"
    quanx_out="$quanx_dir/$base.list"
    render_quanx_domain_ruleset_from_rules "$list" "$quanx_tmp" "$base"

    if [ ! -s "$quanx_tmp" ]; then
      echo "domain list $base has no QuanX-compatible HOST/HOST-SUFFIX/HOST-KEYWORD entries" >&2
      return 1
    fi

    mv "$quanx_tmp" "$quanx_out"
  done
}

render_domain_rule_dir_to_egern_dir() {
  local rule_dir="$1"
  local egern_dir="$2"
  local tmp_dir="$3"
  local list base egern_tmp egern_out

  rm -rf "$egern_dir"
  mkdir -p "$egern_dir" "$tmp_dir"

  for list in "$rule_dir"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    egern_tmp="$tmp_dir/$base.egern.tmp"
    egern_out="$egern_dir/$base.yaml"
    render_egern_domain_ruleset_from_rules "$list" "$egern_tmp"

    if [ ! -s "$egern_tmp" ]; then
      echo "domain list $base has no Egern-compatible entries" >&2
      return 1
    fi

    mv "$egern_tmp" "$egern_out"
  done
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

build_domain_artifacts_from_rule_dir() {
  local rule_dir="$1"
  local tmp_dir="$2"
  local singbox_dir="$3"
  local mihomo_dir="$4"
  local list base json srs_out mihomo_txt mrs_out
  local mihomo_ready=0
  local mihomo_built=0
  local mihomo_skipped=0

  ensure_sing_box
  rm -rf "$singbox_dir" "$mihomo_dir"
  mkdir -p "$singbox_dir" "$mihomo_dir" "$tmp_dir"

  for list in "$rule_dir"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    json="$tmp_dir/$base.json"
    srs_out="$singbox_dir/$base.srs"
    mrs_out="$mihomo_dir/$base.mrs"
    mihomo_txt="$tmp_dir/$base.mihomo.txt"

    compile_domain_rule_list_to_artifacts "$list" "$json" "$srs_out"
    build_mihomo_domain_text_from_rules "$list" "$mihomo_txt"

    if [ ! -s "$mihomo_txt" ]; then
      mihomo_skipped=$((mihomo_skipped + 1))
      rm -f "$mrs_out"
      continue
    fi

    if [ "$mihomo_ready" -eq 0 ]; then
      ensure_mihomo
      mihomo_ready=1
    fi

    compile_mihomo_domain_plain_to_binary_artifact "$mihomo_txt" "$mrs_out"
    mihomo_built=$((mihomo_built + 1))
  done

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
entries = []
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
        entries.append(line)

with open(output_file, "w", encoding="utf-8") as fh:
    if entries:
        fh.write("no_resolve: true\n")
        fh.write("ip_cidr_set:\n")
        for value in entries:
            fh.write(f"  - {yaml_quote(value)}\n")
PY
}

build_ip_json_from_plain() {
  local plain_list="$1"
  local json_out="$2"

  python3 "$ROOT/scripts/tools/normalize-ip-rules.py" singbox-json "$plain_list" "$json_out"
}

compile_ip_plain_to_binary_artifacts() {
  local plain_list="$1"
  local json_out="$2"
  local srs_out="$3"
  local mrs_out="$4"

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
