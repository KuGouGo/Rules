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

normalize_custom_domain_source() {
  local input_file="$1"
  local output_file="$2"

  python3 - "$input_file" "$output_file" <<'PY'
import sys

input_file, output_file = sys.argv[1], sys.argv[2]
allowed = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX"}
rules = []
seen = set()

with open(input_file, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        if "," not in line:
            continue
        rule_type, value = line.split(",", 1)
        rule_type = rule_type.strip().upper()
        value = value.strip()
        if rule_type not in allowed or not value:
            continue
        normalized = f"{rule_type},{value}"
        if normalized in seen:
            continue
        seen.add(normalized)
        rules.append(normalized)

with open(output_file, "w", encoding="utf-8") as fh:
    if rules:
        fh.write("\n".join(rules) + "\n")
PY
}

build_domain_json_from_rules() {
  local rule_list="$1"
  local json_out="$2"

  python3 "$ROOT/scripts/export-domain-list-community.py" singbox-json "$rule_list" "$json_out"
}

render_surge_domain_ruleset_from_rules() {
  local rule_list="$1"
  local surge_out="$2"

  python3 - "$rule_list" "$surge_out" <<'PY'
import sys

rule_list, output_file = sys.argv[1], sys.argv[2]
allowed = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD"}
rules = []
seen = set()

with open(rule_list, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        line = raw_line.split("#", 1)[0].strip()
        if not line or "," not in line:
            continue
        rule_type, value = line.split(",", 1)
        rule_type = rule_type.strip().upper()
        value = value.strip()
        if rule_type not in allowed or not value:
            continue
        normalized = f"{rule_type},{value}"
        if normalized in seen:
            continue
        seen.add(normalized)
        rules.append(normalized)

with open(output_file, "w", encoding="utf-8") as fh:
    if rules:
        fh.write("\n".join(rules) + "\n")
PY
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

build_mihomo_domain_text_from_rules() {
  local rule_list="$1"
  local plain_out="$2"

  python3 - "$rule_list" "$plain_out" <<'PY'
import sys

rule_list, output_file = sys.argv[1], sys.argv[2]
entries = []
seen = set()

with open(rule_list, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        rule_type, separator, value = line.partition(",")
        if not separator:
            continue
        rule_type = rule_type.strip()
        value = value.strip()
        if rule_type == "DOMAIN":
            normalized = value
        elif rule_type == "DOMAIN-SUFFIX":
            normalized = f".{value}"
        else:
            continue
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        entries.append(normalized)

with open(output_file, "w", encoding="utf-8") as fh:
    if entries:
        fh.write("\n".join(entries) + "\n")
PY

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

  ensure_rule_build_tools
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
      echo "domain list $base has no DOMAIN/DOMAIN-SUFFIX entries; cannot build mihomo mrs" >&2
      return 1
    fi

    compile_mihomo_domain_plain_to_binary_artifact "$mihomo_txt" "$mrs_out"
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

render_ip_plain_to_surge_list() {
  local plain_list="$1"
  local surge_out="$2"

  awk '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    {
      value=$0
      gsub(/\r$/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value == "") {
        next
      }
      type = (value ~ /:/ ? "IP-CIDR6" : "IP-CIDR")
      printf "%s,%s,no-resolve\n", type, value
    }
  ' "$plain_list" > "$surge_out"

  dedupe_file_in_place "$surge_out"
}

build_ip_json_from_plain() {
  local plain_list="$1"
  local json_out="$2"

  python3 - "$plain_list" "$json_out" <<'PY'
import json, sys
plain_list, json_out = sys.argv[1], sys.argv[2]
cidrs = [ln.strip() for ln in open(plain_list, encoding="utf-8") if ln.strip()]
data = {"version": 3, "rules": [{"ip_cidr": cidrs}]}
open(json_out, "w", encoding="utf-8").write(json.dumps(data, separators=(",", ":")))
PY
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
