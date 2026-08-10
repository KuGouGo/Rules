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

stage_domain_canonical_rules() {
  local rule_dir="$1"
  local canonical_dir="$2"
  local rule_file

  rm -rf "$canonical_dir"
  mkdir -p "$canonical_dir"
  for rule_file in "$rule_dir"/*.list; do
    [ -f "$rule_file" ] || continue
    cp "$rule_file" "$canonical_dir/"
  done
  if ! compgen -G "$canonical_dir/*.list" >/dev/null; then
    echo "canonical domain rule directory is empty: $rule_dir" >&2
    return 1
  fi
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

build_mihomo_domain_text_from_rules() {
  local rule_list="$1"
  local plain_out="$2"

  python3 "$ROOT/scripts/tools/export-domain-rules.py" mihomo-text "$rule_list" "$plain_out"
}

assert_compiled_file_count() {
  local label="$1"
  local expected="$2"
  local output_dir="$3"
  local pattern="$4"
  local actual

  actual="$(find "$output_dir" -maxdepth 1 -type f -name "$pattern" -size +0c | wc -l | tr -d ' ')"
  if [ "$actual" -ne "$expected" ]; then
    echo "$label produced $actual non-empty artifacts; expected $expected" >&2
    return 1
  fi
}

compiler_cache_dir() {
  local tool="$1"
  local artifact_kind="$2"
  local format_version="$3"
  local binary binary_digest cache_root

  binary="$(command -v "$tool")"
  binary_digest="$(sha256sum "$binary" | awk '{print $1}')"
  cache_root="${RULES_COMPILE_CACHE_ROOT:-$ROOT/.cache/compiled-rules}"
  printf '%s/%s/%s/%s\n' "$cache_root" "$artifact_kind" "$format_version" "$binary_digest"
}

compile_domain_singbox_json_dir() {
  local tmp_dir="$1"
  local singbox_dir="$2"
  local jobs="$3"
  local cache_dir="${4:-$tmp_dir/.compile-cache/sing-box}"
  local list_file="$tmp_dir/.singbox-json-files"
  local stats_dir="$tmp_dir/.singbox-cache-stats"
  local expected hits misses

  find "$tmp_dir" -maxdepth 1 -type f -name '*.json' -print0 > "$list_file"
  expected="$(find "$tmp_dir" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  if [ "$expected" -eq 0 ]; then
    return 0
  fi
  mkdir -p "$cache_dir" "$stats_dir"
  rm -f "$stats_dir"/*

  # shellcheck disable=SC2016
  xargs -0 -n 1 -P "$jobs" sh -c '
    out_dir="$1"
    cache_dir="$2"
    stats_dir="$3"
    json="$4"
    base="$(basename "$json" .json)"
    key="$(sha256sum "$json" | awk "{print \$1}")"
    cached="$cache_dir/$key.srs"
    sidecar="$cached.sha256"
    cache_valid=0
    if [ -s "$cached" ] && [ -s "$sidecar" ]; then
      expected_digest="$(awk "NR == 1 {print \$1}" "$sidecar")"
      actual_digest="$(sha256sum "$cached" | awk "{print \$1}")"
      [ -n "$expected_digest" ] && [ "$expected_digest" = "$actual_digest" ] && cache_valid=1
    fi
    if [ "$cache_valid" -eq 1 ]; then
      cp "$cached" "$out_dir/$base.srs"
      : > "$stats_dir/$base.hit"
    else
      rm -f "$cached" "$sidecar"
      temporary="$(mktemp "$cache_dir/.${key}.XXXXXX")"
      sidecar_temporary="$(mktemp "$cache_dir/.${key}.sha256.XXXXXX")"
      trap '\''rm -f "$temporary" "$sidecar_temporary"'\'' EXIT
      sing-box rule-set compile "$json" --output "$temporary"
      test -s "$temporary"
      cp "$temporary" "$out_dir/$base.srs"
      sha256sum "$temporary" | awk "{print \$1}" > "$sidecar_temporary"
      mv -f "$temporary" "$cached"
      mv -f "$sidecar_temporary" "$sidecar"
      trap - EXIT
      : > "$stats_dir/$base.miss"
    fi
    test -s "$out_dir/$base.srs"
  ' sh "$singbox_dir" "$cache_dir" "$stats_dir" < "$list_file" || return 1
  assert_compiled_file_count "sing-box domain compile" "$expected" "$singbox_dir" '*.srs' || return 1
  hits="$(find "$stats_dir" -type f -name '*.hit' | wc -l | tr -d ' ')"
  misses="$(find "$stats_dir" -type f -name '*.miss' | wc -l | tr -d ' ')"
  echo "sing-box domain compile cache: hits=$hits, misses=$misses"
}

compile_domain_mihomo_text_dir() {
  local tmp_dir="$1"
  local mihomo_dir="$2"
  local jobs="$3"
  local cache_dir="${4:-$tmp_dir/.compile-cache/mihomo}"
  local list_file="$tmp_dir/.mihomo-text-files"
  local stats_dir="$tmp_dir/.mihomo-cache-stats"
  local expected hits misses

  find "$tmp_dir" -maxdepth 1 -type f -name '*.mihomo.txt' -size +0c -print0 > "$list_file"
  expected="$(find "$tmp_dir" -maxdepth 1 -type f -name '*.mihomo.txt' -size +0c | wc -l | tr -d ' ')"
  if [ "$expected" -eq 0 ]; then
    return 0
  fi
  mkdir -p "$cache_dir" "$stats_dir"
  rm -f "$stats_dir"/*

  # shellcheck disable=SC2016
  xargs -0 -n 1 -P "$jobs" sh -c '
    out_dir="$1"
    cache_dir="$2"
    stats_dir="$3"
    plain="$4"
    base="$(basename "$plain" .mihomo.txt)"
    key="$(sha256sum "$plain" | awk "{print \$1}")"
    cached="$cache_dir/$key.mrs"
    sidecar="$cached.sha256"
    cache_valid=0
    if [ -s "$cached" ] && [ -s "$sidecar" ]; then
      expected_digest="$(awk "NR == 1 {print \$1}" "$sidecar")"
      actual_digest="$(sha256sum "$cached" | awk "{print \$1}")"
      [ -n "$expected_digest" ] && [ "$expected_digest" = "$actual_digest" ] && cache_valid=1
    fi
    if [ "$cache_valid" -eq 1 ]; then
      cp "$cached" "$out_dir/$base.mrs"
      : > "$stats_dir/$base.hit"
    else
      rm -f "$cached" "$sidecar"
      temporary="$(mktemp "$cache_dir/.${key}.XXXXXX")"
      sidecar_temporary="$(mktemp "$cache_dir/.${key}.sha256.XXXXXX")"
      trap '\''rm -f "$temporary" "$sidecar_temporary"'\'' EXIT
      mihomo convert-ruleset domain text "$plain" "$temporary" >/dev/null
      test -s "$temporary"
      cp "$temporary" "$out_dir/$base.mrs"
      sha256sum "$temporary" | awk "{print \$1}" > "$sidecar_temporary"
      mv -f "$temporary" "$cached"
      mv -f "$sidecar_temporary" "$sidecar"
      trap - EXIT
      : > "$stats_dir/$base.miss"
    fi
    test -s "$out_dir/$base.mrs"
  ' sh "$mihomo_dir" "$cache_dir" "$stats_dir" < "$list_file" || return 1
  assert_compiled_file_count "mihomo domain compile" "$expected" "$mihomo_dir" '*.mrs' || return 1
  hits="$(find "$stats_dir" -type f -name '*.hit' | wc -l | tr -d ' ')"
  misses="$(find "$stats_dir" -type f -name '*.miss' | wc -l | tr -d ' ')"
  echo "mihomo domain compile cache: hits=$hits, misses=$misses"
}

build_domain_artifacts_from_rule_dir() {
  local rule_dir="$1"
  local tmp_dir="$2"
  local singbox_dir="$3"
  local mihomo_dir="$4"
  local mihomo_txt source_version compile_jobs singbox_cache mihomo_cache
  local mihomo_built=0
  local mihomo_skipped=0

  ensure_sing_box
  rm -rf "$singbox_dir" "$mihomo_dir" "$tmp_dir"
  mkdir -p "$singbox_dir" "$mihomo_dir" "$tmp_dir"
  source_version="$(detect_singbox_rule_set_source_version)"
  singbox_cache="$(compiler_cache_dir sing-box domain-srs "$source_version")"

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
  compile_domain_singbox_json_dir "$tmp_dir" "$singbox_dir" "$compile_jobs" "$singbox_cache"

  if [ "$mihomo_built" -gt 0 ]; then
    ensure_mihomo
    mihomo_cache="$(compiler_cache_dir mihomo domain-mrs 1)"
    compile_domain_mihomo_text_dir "$tmp_dir" "$mihomo_dir" "$compile_jobs" "$mihomo_cache"
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

  python3 "$ROOT/scripts/tools/normalize-ip-rules.py" custom-source "$input_file" "$plain_out"
  render_ip_plain_to_surge_list "$plain_out" "$surge_out"
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
  local -a args=(render-classical surge "$plain_list" "$surge_out")

  if [ "$SURGE_IP_APPEND_NO_RESOLVE" != "1" ]; then
    args+=(--omit-no-resolve)
  fi
  python3 "$ROOT/scripts/tools/normalize-ip-rules.py" "${args[@]}"
}

render_ip_plain_to_canonical_list() {
  local plain_list="$1"
  local canonical_out="$2"

  mkdir -p "$(dirname "$canonical_out")"
  awk '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    { printf "%s,%s\n", ($0 ~ /:/ ? "IP-CIDR6" : "IP-CIDR"), $0 }
  ' "$plain_list" > "$canonical_out"
  if [ ! -s "$canonical_out" ]; then
    echo "canonical IP rule source is empty: $plain_list" >&2
    return 1
  fi
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

  python3 "$ROOT/scripts/tools/normalize-ip-rules.py" render-egern "$plain_list" "$egern_out"
}

build_ip_json_from_plain() {
  local plain_list="$1"
  local json_out="$2"
  local source_version

  source_version="${SINGBOX_RULE_SET_VERSION:-4}"

  SINGBOX_RULE_SET_VERSION="$source_version" \
    python3 "$ROOT/scripts/tools/normalize-ip-rules.py" singbox-json "$plain_list" "$json_out"
}

compile_ip_binary_dirs() {
  local tmp_dir="$1"
  local singbox_dir="$2"
  local mihomo_dir="$3"
  local jobs="$4"
  local json_list plain_list expected

  json_list="$tmp_dir/.singbox-ip-json-files"
  find "$tmp_dir" -maxdepth 1 -type f -name '*.json' -print0 > "$json_list"
  expected="$(find "$tmp_dir" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  if [ "$expected" -gt 0 ]; then
    # shellcheck disable=SC2016
    xargs -0 -n 1 -P "$jobs" sh -c '
      out_dir="$1"
      json="$2"
      base="$(basename "$json" .json)"
      sing-box rule-set compile "$json" --output "$out_dir/$base.srs"
      test -s "$out_dir/$base.srs"
    ' sh "$singbox_dir" < "$json_list"
    assert_compiled_file_count "sing-box IP compile" "$expected" "$singbox_dir" '*.srs'
  fi

  plain_list="$tmp_dir/.mihomo-ip-text-files"
  find "$tmp_dir" -maxdepth 1 -type f -name '*.txt' -size +0c -print0 > "$plain_list"
  expected="$(find "$tmp_dir" -maxdepth 1 -type f -name '*.txt' -size +0c | wc -l | tr -d ' ')"
  if [ "$expected" -gt 0 ]; then
    # shellcheck disable=SC2016
    xargs -0 -n 1 -P "$jobs" sh -c '
      out_dir="$1"
      plain="$2"
      base="$(basename "$plain" .txt)"
      mihomo convert-ruleset ipcidr text "$plain" "$out_dir/$base.mrs" >/dev/null
      test -s "$out_dir/$base.mrs"
    ' sh "$mihomo_dir" < "$plain_list"
    assert_compiled_file_count "mihomo IP compile" "$expected" "$mihomo_dir" '*.mrs'
  fi
}

build_ip_artifacts_from_surge_dir() {
  local surge_dir="$1"
  local tmp_dir="$2"
  local singbox_dir="$3"
  local mihomo_dir="$4"
  local list base plain_txt json source_version compile_jobs

  ensure_sing_box
  ensure_mihomo
  rm -rf "$singbox_dir" "$mihomo_dir" "$tmp_dir"
  mkdir -p "$singbox_dir" "$mihomo_dir" "$tmp_dir"
  source_version="$(detect_singbox_rule_set_source_version)"

  for list in "$surge_dir"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    plain_txt="$tmp_dir/$base.txt"
    json="$tmp_dir/$base.json"

    normalize_ip_surge_list_to_plain "$list" "$plain_txt"
    if [ ! -s "$plain_txt" ]; then
      echo "skipping empty IP list: $base" >&2
      continue
    fi
    SINGBOX_RULE_SET_VERSION="$source_version" \
      build_ip_json_from_plain "$plain_txt" "$json"
  done

  compile_jobs="$(detect_compile_jobs)"
  echo "IP binary compile jobs: $compile_jobs"
  compile_ip_binary_dirs "$tmp_dir" "$singbox_dir" "$mihomo_dir" "$compile_jobs"
}
