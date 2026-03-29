#!/usr/bin/env bash

: "${ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

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

normalize_domain_surge_list_to_plain() {
  local input_file="$1"
  local plain_out="$2"

  awk '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    {
      value=$0
      gsub(/\r$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value != "") print value
    }
  ' "$input_file" > "$plain_out"

  dedupe_file_in_place "$plain_out"
}

normalize_custom_domain_source() {
  local input_file="$1"
  local surge_out="$2"
  local plain_out="$3"

  : > "$surge_out"
  : > "$plain_out"

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
  ' surge="$surge_out" plain="$plain_out" "$input_file"

  dedupe_file_in_place "$surge_out"
  dedupe_file_in_place "$plain_out"
}

build_domain_json_from_plain() {
  local plain_list="$1"
  local json_out="$2"
  local domains suffixes

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
  } > "$json_out"
}

compile_domain_plain_to_binary_artifacts() {
  local plain_list="$1"
  local json_out="$2"
  local srs_out="$3"
  local mrs_out="$4"

  build_domain_json_from_plain "$plain_list" "$json_out"
  sing-box rule-set compile "$json_out" --output "$srs_out"
  mihomo convert-ruleset domain text "$plain_list" "$mrs_out" >/dev/null 2>&1
}

build_domain_artifacts_from_surge_dir() {
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
    plain_txt="$tmp_dir/$base.list"
    json="$tmp_dir/$base.json"
    srs_out="$singbox_dir/$base.srs"
    mrs_out="$mihomo_dir/$base.mrs"

    normalize_domain_surge_list_to_plain "$list" "$plain_txt"
    compile_domain_plain_to_binary_artifacts "$plain_txt" "$json" "$srs_out" "$mrs_out"
  done
}

normalize_ip_rule_source() {
  local input_file="$1"
  local surge_out="$2"
  local plain_out="$3"

  : > "$surge_out"
  : > "$plain_out"

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
        printf "%s,%s,no-resolve\n", type, value >> surge
      }
    }
  ' surge="$surge_out" plain="$plain_out" "$input_file"

  dedupe_file_in_place "$surge_out"
  dedupe_file_in_place "$plain_out"
}

normalize_ip_surge_list_to_plain() {
  local input_file="$1"
  local plain_out="$2"

  awk -F, '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    $1 == "IP-CIDR" || $1 == "IP-CIDR6" {
      value=$2
      gsub(/\r$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value != "") print value
    }
  ' "$input_file" > "$plain_out"

  dedupe_file_in_place "$plain_out"
}

build_ip_json_from_plain() {
  local plain_list="$1"
  local json_out="$2"
  local cidrs

  cidrs="$(awk 'NF { printf "\"%s\",", $0 }' "$plain_list" | sed 's/,$//')"
  printf '{"version":3,"rules":[{"ip_cidr":[%s]}]}\n' "$cidrs" > "$json_out"
}

compile_ip_plain_to_binary_artifacts() {
  local plain_list="$1"
  local json_out="$2"
  local srs_out="$3"
  local mrs_out="$4"

  build_ip_json_from_plain "$plain_list" "$json_out"
  sing-box rule-set compile "$json_out" --output "$srs_out"
  mihomo convert-ruleset ipcidr text "$plain_list" "$mrs_out" >/dev/null 2>&1
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
    compile_ip_plain_to_binary_artifacts "$plain_txt" "$json" "$srs_out" "$mrs_out"
  done
}
