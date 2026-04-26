#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

WORK_TMP_DIR="$ROOT_DIR/.tmp/sync"
BIN_DIR="$ROOT_DIR/.bin"
DOMAIN_BUILD_TMP_DIR="$WORK_TMP_DIR/domain-build"
DOMAIN_BINARY_RULE_TMP_DIR="$WORK_TMP_DIR/domain-binary-rules"
DOMAIN_RULE_TMP_DIR="$WORK_TMP_DIR/domain-rules"
IP_BUILD_TMP_DIR="$WORK_TMP_DIR/ip-build"
ARTIFACTS_DIR="$ROOT_DIR/.output"
DOMAIN_ARTIFACTS_DIR="$ARTIFACTS_DIR/domain"
IP_ARTIFACTS_DIR="$ARTIFACTS_DIR/ip"

UPSTREAMS_CONFIG_FILE="$ROOT_DIR/config/upstreams.json"
UPSTREAM_SUMMARY_FILE="$ARTIFACTS_DIR/upstream-summary.jsonl"
FIRST_BATCH_BASELINES_FILE="$ROOT_DIR/config/upstream-first-batch-baselines.json"

upstream_value() {
  local section="$1"
  local name="$2"
  local key="$3"
  python3 - <<'PY' "$UPSTREAMS_CONFIG_FILE" "$section" "$name" "$key"
import json, sys
config, section, name, key = sys.argv[1:]
data = json.load(open(config, encoding="utf-8"))[section][name]
value = data.get(key, "")
if isinstance(value, list):
    print(" ".join(str(item) for item in value))
else:
    print(value)
PY
}

upstream_asn_group() {
  local name="$1"
  python3 - <<'PY' "$UPSTREAMS_CONFIG_FILE" "$name"
import json, sys
config, name = sys.argv[1:]
print(" ".join(str(item) for item in json.load(open(config, encoding="utf-8"))["asn_groups"][name]))
PY
}

DOMAIN_SOURCE_REPO_URL="$(upstream_value domain dlc url)"
ANTI_AD_DOMAIN_SOURCE_URL="$(upstream_value domain anti-ad url)"
ANTI_AD_DOMAIN_SOURCE_FALLBACK_URL="$(upstream_value domain anti-ad fallback_url)"
ANTI_AD_SING_BOX_SRS_SOURCE_URL="$(upstream_value domain anti-ad sing_box_srs_url)"
ANTI_AD_SING_BOX_SRS_SOURCE_FALLBACK_URL="$(upstream_value domain anti-ad sing_box_srs_fallback_url)"
ANTI_AD_MIHOMO_MRS_SOURCE_URL="$(upstream_value domain anti-ad mihomo_mrs_url)"
ANTI_AD_MIHOMO_MRS_SOURCE_FALLBACK_URL="$(upstream_value domain anti-ad mihomo_mrs_fallback_url)"
CN_IPV4_SOURCE_URL="$(upstream_value ip cn-ipv4 url)"
CN_IPV6_SOURCE_URL="$(upstream_value ip cn-ipv6 url)"
CN_ASN_IPV4_SOURCE_URL="$(upstream_value ip cn-asn-ipv4 url)"
CN_ASN_IPV6_SOURCE_URL="$(upstream_value ip cn-asn-ipv6 url)"
GOOGLE_IP_SOURCE_URL="$(upstream_value ip google url)"
TELEGRAM_IP_SOURCE_URL="$(upstream_value ip telegram url)"
CLOUDFLARE_IPV4_SOURCE_URL="$(upstream_value ip cloudflare-ipv4 url)"
CLOUDFLARE_IPV6_SOURCE_URL="$(upstream_value ip cloudflare-ipv6 url)"
AWS_IP_SOURCE_URL="$(upstream_value ip aws url)"
FASTLY_IP_SOURCE_URL="$(upstream_value ip fastly url)"
GITHUB_IP_SOURCE_URL="$(upstream_value ip github url)"
APPLE_IP_SOURCE_URL="$(upstream_value ip apple url)"
APPLE_IP_SOURCE_FALLBACK_URL="$(upstream_value ip apple fallback_url)"
RIPE_STAT_BASE_URL="$(upstream_value ip ripe-stat base_url)"
APPLE_MIN_CIDR_COUNT="${APPLE_MIN_CIDR_COUNT:-$(upstream_value ip apple min_cidrs)}"
ANTI_AD_MIN_RULE_COUNT="${ANTI_AD_MIN_RULE_COUNT:-$(upstream_value domain anti-ad min_rules)}"
ANTI_AD_SING_BOX_SRS_MIN_BYTES="${ANTI_AD_SING_BOX_SRS_MIN_BYTES:-$(upstream_value domain anti-ad sing_box_srs_min_bytes)}"
ANTI_AD_MIHOMO_MRS_MIN_BYTES="${ANTI_AD_MIHOMO_MRS_MIN_BYTES:-$(upstream_value domain anti-ad mihomo_mrs_min_bytes)}"
read -r -a NETFLIX_ASNS <<< "$(upstream_asn_group netflix)"
read -r -a SPOTIFY_ASNS <<< "$(upstream_asn_group spotify)"
read -r -a DISNEY_ASNS <<< "$(upstream_asn_group disney)"

source "$ROOT_DIR/scripts/lib/common.sh"
source "$ROOT_DIR/scripts/lib/rules.sh"
setup_tool_cache

rm -rf "$WORK_TMP_DIR"
mkdir -p "$WORK_TMP_DIR" "$BIN_DIR" "$DOMAIN_BUILD_TMP_DIR" "$DOMAIN_RULE_TMP_DIR" "$IP_BUILD_TMP_DIR"
trap 'rm -rf "$WORK_TMP_DIR"' EXIT

mkdir -p "$DOMAIN_ARTIFACTS_DIR" "$IP_ARTIFACTS_DIR"
: > "$UPSTREAM_SUMMARY_FILE"

echo "=== SYNC START ==="

record_upstream_summary() {
  local category="$1"
  local name="$2"
  local status="$3"
  local url="$4"
  local raw_file="${5:-}"
  local normalized_file="${6:-}"
  local fallback_used="${7:-0}"
  local detail="${8:-}"

  python3 - <<'PY' "$UPSTREAMS_CONFIG_FILE" "$UPSTREAM_SUMMARY_FILE" "$category" "$name" "$status" "$url" "$raw_file" "$normalized_file" "$fallback_used" "$detail"
import json, sys
from pathlib import Path
config_file, summary_file, category, name, status, url, raw_file, normalized_file, fallback_used, detail = sys.argv[1:]
config = json.load(open(config_file, encoding="utf-8"))
source = config.get(category, {}).get(name, {})
payload = {
    "category": category,
    "name": name,
    "status": status,
    "kind": source.get("kind", ""),
    "trust": source.get("trust", ""),
    "url": url,
    "fallback_used": fallback_used == "1",
}
if detail:
    payload["detail"] = detail
for key, file_name in (("raw", raw_file), ("normalized", normalized_file)):
    if not file_name:
        continue
    path = Path(file_name)
    info = {"path": str(path)}
    if path.exists():
        info["bytes"] = path.stat().st_size
        if path.is_file():
            lines = [line for line in path.read_text(encoding="utf-8", errors="ignore").splitlines() if line.strip() and not line.lstrip().startswith("#")]
            info["entries"] = len(lines)
    payload[key] = info
Path(summary_file).parent.mkdir(parents=True, exist_ok=True)
with open(summary_file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
PY
}

record_dlc_summary() {
  local repo_dir="$1"
  local commit=""
  commit="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
  record_upstream_summary domain dlc ok "$DOMAIN_SOURCE_REPO_URL" "" "" 0 "commit=$commit"
}

write_upstream_summary_json() {
  local json_file="$ARTIFACTS_DIR/upstream-summary.json"
  python3 - <<'PY' "$UPSTREAM_SUMMARY_FILE" "$json_file"
import json, sys
from pathlib import Path
jsonl_file, json_file = map(Path, sys.argv[1:])
items = []
if jsonl_file.exists():
    items = [json.loads(line) for line in jsonl_file.read_text(encoding="utf-8").splitlines() if line.strip()]
json_file.write_text(json.dumps(items, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

clone_repository_shallow() {
  local repo_url="$1"
  local dest="$2"
  git clone --depth=1 --single-branch "$repo_url" "$dest"
}

assert_files_present() {
  local label="$1"
  local glob="$2"
  if ! compgen -G "$glob" >/dev/null; then
    echo "$label is empty: $glob" >&2
    exit 1
  fi
}

merge_cidr_plain_files() {
  local output_file="$1"
  shift
  # Filter blank/comment lines while deduplicating.
  awk '!/^[[:space:]]*$/ && !/^[[:space:]]*#/ && !seen[$0]++' "$@" > "$output_file"
}

# sync_asn_ip_list <name> <asn> [<asn> ...]
# Download RIPE NCC Stat prefix data for each ASN, normalise in one batch,
# merge, and render to a Surge list at IP_ARTIFACTS_DIR/surge/<name>.list.
sync_asn_ip_list() {
  local name="$1"
  shift
  local -a asns=("$@")
  local -a cidr_files=()
  local -a task_args=()
  local asn raw_json cidr_txt manifest_file

  for asn in "${asns[@]}"; do
    raw_json="$IP_BUILD_TMP_DIR/${name}_as${asn}.raw.json"
    cidr_txt="$IP_BUILD_TMP_DIR/${name}_as${asn}.cidr.txt"
    download_file "${RIPE_STAT_BASE_URL}${asn}" "$raw_json"
    cidr_files+=("$cidr_txt")
    task_args+=(
      "ripe-stat-json"
      "$raw_json"
      "$cidr_txt"
    )
  done

  manifest_file="$IP_BUILD_TMP_DIR/${name}.asn-normalize-tasks.json"
  generate_normalize_manifest "$manifest_file" "${task_args[@]}"
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" batch "$manifest_file"

  merge_cidr_plain_files "$IP_BUILD_TMP_DIR/${name}.cidr.txt" "${cidr_files[@]}"

  if [ ! -s "$IP_BUILD_TMP_DIR/${name}.cidr.txt" ]; then
    echo "warning: no prefixes found for $name (ASNs: ${asns[*]}), skipping" >&2
    return 0
  fi

  render_ip_plain_to_surge_list \
    "$IP_BUILD_TMP_DIR/${name}.cidr.txt" \
    "$IP_ARTIFACTS_DIR/surge/${name}.list"
  render_ip_plain_to_quanx_list \
    "$IP_BUILD_TMP_DIR/${name}.cidr.txt" \
    "$IP_ARTIFACTS_DIR/quanx/${name}.list" \
    "$name"
  record_upstream_summary ip "${name}-asn" ok "$RIPE_STAT_BASE_URL" "" "$IP_BUILD_TMP_DIR/${name}.cidr.txt" 0 "asns=${asns[*]}"
}

generate_normalize_manifest() {
  local manifest_file="$1"
  shift

  python3 - <<'PY' "$manifest_file" "$@"
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
args = sys.argv[2:]

if len(args) % 3 != 0:
    raise SystemExit("normalize manifest generator expects triplets: source_type input_file output_file")

tasks = []
for i in range(0, len(args), 3):
    tasks.append({
        "source_type": args[i],
        "input_file": args[i + 1],
        "output_file": args[i + 2],
    })

manifest_path.write_text(json.dumps(tasks, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

generate_ip_normalize_manifest() {
  local manifest_file="$1"
  local tmp_dir="$IP_BUILD_TMP_DIR"

  generate_normalize_manifest "$manifest_file" \
    text "$tmp_dir/cn_ipv4.raw.txt" "$tmp_dir/cn_ipv4.cidr.txt" \
    text "$tmp_dir/cn_ipv6.raw.txt" "$tmp_dir/cn_ipv6.cidr.txt" \
    text "$tmp_dir/cn_asn_ipv4.raw.txt" "$tmp_dir/cn_asn_ipv4.cidr.txt" \
    text "$tmp_dir/cn_asn_ipv6.raw.txt" "$tmp_dir/cn_asn_ipv6.cidr.txt" \
    text "$tmp_dir/cloudflare_ipv4.raw.txt" "$tmp_dir/cloudflare_ipv4.cidr.txt" \
    text "$tmp_dir/cloudflare_ipv6.raw.txt" "$tmp_dir/cloudflare_ipv6.cidr.txt" \
    aws-cloudfront-json "$tmp_dir/aws.raw.json" "$tmp_dir/cloudfront.cidr.txt" \
    aws-json "$tmp_dir/aws.raw.json" "$tmp_dir/aws.cidr.txt" \
    fastly-json "$tmp_dir/fastly.raw.json" "$tmp_dir/fastly.cidr.txt" \
    html "$tmp_dir/apple.raw.html" "$tmp_dir/apple.cidr.txt"
}

download_file_with_fallback() {
  local out_file="$1"
  shift
  local url
  local attempted=""
  local attempt_index=0

  UPSTREAM_LAST_URL=""
  UPSTREAM_LAST_FALLBACK_USED=0
  for url in "$@"; do
    attempt_index=$((attempt_index + 1))
    if download_file "$url" "$out_file"; then
      UPSTREAM_LAST_URL="$url"
      if [ "$attempt_index" -gt 1 ]; then
        UPSTREAM_LAST_FALLBACK_USED=1
      fi
      echo "downloaded $(basename "$out_file") from $url"
      return 0
    fi

    attempted="${attempted}${attempted:+, }$url"
    echo "download failed from $url, trying next fallback..." >&2
  done

  echo "failed to download $(basename "$out_file") from all sources: $attempted" >&2
  return 1
}

FIRST_BATCH_GOOGLE_JSON_STATUS=""
FIRST_BATCH_GOOGLE_JSON_REASON=""
FIRST_BATCH_GITHUB_JSON_STATUS=""
FIRST_BATCH_GITHUB_JSON_REASON=""
FIRST_BATCH_TELEGRAM_STATUS=""
FIRST_BATCH_TELEGRAM_REASON=""

set_first_batch_result() {
  local source="$1"
  local status="$2"
  local reason="$3"

  case "$source" in
    google-json)
      FIRST_BATCH_GOOGLE_JSON_STATUS="$status"
      FIRST_BATCH_GOOGLE_JSON_REASON="$reason"
      ;;
    github-json)
      FIRST_BATCH_GITHUB_JSON_STATUS="$status"
      FIRST_BATCH_GITHUB_JSON_REASON="$reason"
      ;;
    telegram)
      FIRST_BATCH_TELEGRAM_STATUS="$status"
      FIRST_BATCH_TELEGRAM_REASON="$reason"
      ;;
    *)
      echo "unsupported first-batch source: $source" >&2
      return 1
      ;;
  esac
}

first_batch_status() {
  local source="$1"
  local status=""

  case "$source" in
    google-json) status="$FIRST_BATCH_GOOGLE_JSON_STATUS" ;;
    github-json) status="$FIRST_BATCH_GITHUB_JSON_STATUS" ;;
    telegram) status="$FIRST_BATCH_TELEGRAM_STATUS" ;;
    *)
      echo "unsupported first-batch source: $source" >&2
      return 1
      ;;
  esac

  printf '%s' "${status:-transport_incident}"
}

first_batch_reason() {
  local source="$1"
  local reason=""

  case "$source" in
    google-json) reason="$FIRST_BATCH_GOOGLE_JSON_REASON" ;;
    github-json) reason="$FIRST_BATCH_GITHUB_JSON_REASON" ;;
    telegram) reason="$FIRST_BATCH_TELEGRAM_REASON" ;;
    *)
      echo "unsupported first-batch source: $source" >&2
      return 1
      ;;
  esac

  printf '%s' "${reason:-not checked}"
}

first_batch_raw_file() {
  case "$1" in
    google-json) printf '%s' "$IP_BUILD_TMP_DIR/google.raw.json" ;;
    github-json) printf '%s' "$IP_BUILD_TMP_DIR/github.raw.json" ;;
    telegram) printf '%s' "$IP_BUILD_TMP_DIR/telegram.raw.txt" ;;
    *)
      echo "unsupported first-batch source: $1" >&2
      return 1
      ;;
  esac
}

first_batch_source_type() {
  case "$1" in
    google-json) printf '%s' "google-json" ;;
    github-json) printf '%s' "github-json" ;;
    telegram) printf '%s' "text" ;;
    *)
      echo "unsupported first-batch source: $1" >&2
      return 1
      ;;
  esac
}

classify_first_batch_source() {
  local source="$1"
  local raw_file result_json status reason

  raw_file="$(first_batch_raw_file "$source")"
  result_json="$(
    python3 "$ROOT_DIR/scripts/tools/classify-upstream-health.py" \
      classify \
      "$source" \
      "$raw_file" \
      "$FIRST_BATCH_BASELINES_FILE"
  )"
  status="$(printf '%s' "$result_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  reason="$(printf '%s' "$result_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["reason"])')"

  set_first_batch_result "$source" "$status" "$reason"
  record_upstream_summary ip "$source" "$status" "" "$raw_file" "" 0 "$reason"
}

download_and_classify_first_batch_source() {
  local source="$1"
  local url="$2"
  local raw_file

  raw_file="$(first_batch_raw_file "$source")"
  if ! download_file "$url" "$raw_file"; then
    rm -f "$raw_file"
  fi

  classify_first_batch_source "$source"
}

normalize_first_batch_source() {
  local source="$1"
  local raw_file output_file source_type

  if [ "$(first_batch_status "$source")" != "ok" ]; then
    return 0
  fi

  raw_file="$(first_batch_raw_file "$source")"
  source_type="$(first_batch_source_type "$source")"

  case "$source" in
    google-json) output_file="$IP_BUILD_TMP_DIR/google.cidr.txt" ;;
    github-json) output_file="$IP_BUILD_TMP_DIR/github.cidr.txt" ;;
    telegram) output_file="$IP_BUILD_TMP_DIR/telegram.cidr.txt" ;;
    *)
      echo "unsupported first-batch source: $source" >&2
      return 1
      ;;
  esac

  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" single "$source_type" "$raw_file" "$output_file"
}

summarize_first_batch_checks() {
  local source status reason failed=0

  echo "=== FIRST-BATCH SOURCE CHECKS ==="
  for source in google-json github-json telegram; do
    status="$(first_batch_status "$source")"
    reason="$(first_batch_reason "$source")"
    echo "$source: $status - $reason"
    if [ "$status" != "ok" ]; then
      failed=1
    fi
  done

  if [ "$failed" -ne 0 ]; then
    echo "first-batch source checks failed" >&2
    return 1
  fi
}

assert_min_cidrs() {
  local label="$1"
  local file="$2"
  local min_expected="$3"
  local count

  count=$(wc -l < "$file" | tr -d ' ')
  echo "$label cidr entries: $count (min expected: $min_expected)"

  if [ "$count" -lt "$min_expected" ]; then
    echo "$label cidr count too low: $count < $min_expected" >&2
    return 1
  fi
}

assert_min_rules() {
  local label="$1"
  local file="$2"
  local min_expected="$3"
  local count

  count=$(wc -l < "$file" | tr -d ' ')
  echo "$label rule entries: $count (min expected: $min_expected)"

  if [ "$count" -lt "$min_expected" ]; then
    echo "$label rule count too low: $count < $min_expected" >&2
    return 1
  fi
}

assert_min_bytes() {
  local label="$1"
  local file="$2"
  local min_expected="$3"
  local count

  count=$(wc -c < "$file" | tr -d ' ')
  echo "$label bytes: $count (min expected: $min_expected)"

  if [ "$count" -lt "$min_expected" ]; then
    echo "$label bytes too low: $count < $min_expected" >&2
    return 1
  fi
}

sync_remote_domain_ruleset() {
  local name="$1"
  local min_expected="$2"
  shift 2
  local raw_file normalized_file

  raw_file="$DOMAIN_BUILD_TMP_DIR/${name}.raw.list"
  normalized_file="$DOMAIN_RULE_TMP_DIR/${name}.list"

  download_file_with_fallback "$raw_file" "$@"
  normalize_custom_domain_source "$raw_file" "$normalized_file"

  if [ ! -s "$normalized_file" ]; then
    echo "normalized remote domain ruleset is empty: $name" >&2
    return 1
  fi

  assert_min_rules "$name" "$normalized_file" "$min_expected"
  record_upstream_summary domain "$name" ok "${UPSTREAM_LAST_URL:-}" "$raw_file" "$normalized_file" "${UPSTREAM_LAST_FALLBACK_USED:-0}"
}

sync_remote_domain_binary_artifact() {
  local name="$1"
  local platform="$2"
  local out_file="$3"
  local min_expected="$4"
  shift 4
  local tmp_file

  tmp_file="$DOMAIN_BUILD_TMP_DIR/$(basename "$out_file").download"
  download_file_with_fallback "$tmp_file" "$@"

  if [ ! -s "$tmp_file" ]; then
    echo "remote domain artifact is empty: $name $platform" >&2
    return 1
  fi

  assert_min_bytes "$name $platform" "$tmp_file" "$min_expected"
  mv "$tmp_file" "$out_file"
}

prepare_domain_binary_rule_dir() {
  local source_dir="$1"
  local target_dir="$2"
  local list base

  rm -rf "$target_dir"
  mkdir -p "$target_dir"

  for list in "$source_dir"/*.list; do
    [ -f "$list" ] || continue
    base="$(basename "$list" .list)"
    case "$base" in
      anti-ad) continue ;;
    esac
    cp "$list" "$target_dir/$base.list"
  done
}

# Domain rules from domain-list-community/data plus curated remote lists
# The export script now automatically generates @cn filtered versions for all rule sets
rm -rf "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/mihomo"
clone_repository_shallow "$DOMAIN_SOURCE_REPO_URL" "$WORK_TMP_DIR/domain-list-community"
record_dlc_summary "$WORK_TMP_DIR/domain-list-community"
python3 "$ROOT_DIR/scripts/tools/export-domain-rules.py" export \
  "$WORK_TMP_DIR/domain-list-community/data" \
  "$DOMAIN_RULE_TMP_DIR"
sync_remote_domain_ruleset \
  anti-ad \
  "$ANTI_AD_MIN_RULE_COUNT" \
  "$ANTI_AD_DOMAIN_SOURCE_URL" \
  "$ANTI_AD_DOMAIN_SOURCE_FALLBACK_URL"
assert_files_present "$DOMAIN_RULE_TMP_DIR" "$DOMAIN_RULE_TMP_DIR/*.list"
render_domain_rule_dir_to_text_platform_dirs \
  "$DOMAIN_RULE_TMP_DIR" \
  "$DOMAIN_ARTIFACTS_DIR/surge" \
  "$DOMAIN_ARTIFACTS_DIR/quanx" \
  "$DOMAIN_ARTIFACTS_DIR/egern"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/surge/*.list"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/quanx/*.list"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/egern/*.yaml"

# Domain sing-box and mihomo are built locally unless a source publishes native binaries.
# anti-AD provides official SRS/MRS artifacts, so exclude it from local binary compile.
prepare_domain_binary_rule_dir "$DOMAIN_RULE_TMP_DIR" "$DOMAIN_BINARY_RULE_TMP_DIR"
build_domain_artifacts_from_rule_dir \
  "$DOMAIN_BINARY_RULE_TMP_DIR" \
  "$DOMAIN_BUILD_TMP_DIR/domain-compile" \
  "$DOMAIN_ARTIFACTS_DIR/sing-box" \
  "$DOMAIN_ARTIFACTS_DIR/mihomo"
sync_remote_domain_binary_artifact \
  anti-ad \
  sing-box \
  "$DOMAIN_ARTIFACTS_DIR/sing-box/anti-ad.srs" \
  "$ANTI_AD_SING_BOX_SRS_MIN_BYTES" \
  "$ANTI_AD_SING_BOX_SRS_SOURCE_URL" \
  "$ANTI_AD_SING_BOX_SRS_SOURCE_FALLBACK_URL"
sync_remote_domain_binary_artifact \
  anti-ad \
  mihomo \
  "$DOMAIN_ARTIFACTS_DIR/mihomo/anti-ad.mrs" \
  "$ANTI_AD_MIHOMO_MRS_MIN_BYTES" \
  "$ANTI_AD_MIHOMO_MRS_SOURCE_URL" \
  "$ANTI_AD_MIHOMO_MRS_SOURCE_FALLBACK_URL"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/sing-box/*.srs"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/mihomo" "$DOMAIN_ARTIFACTS_DIR/mihomo/*.mrs"

# IP rules from curated remote sources
rm -rf "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/egern" "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/mihomo"
mkdir -p "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx"

download_file "$CN_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv4.raw.txt"
download_file "$CN_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv6.raw.txt"
download_file "$CN_ASN_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_asn_ipv4.raw.txt"
download_file "$CN_ASN_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_asn_ipv6.raw.txt"
download_and_classify_first_batch_source "google-json" "$GOOGLE_IP_SOURCE_URL"
download_and_classify_first_batch_source "telegram" "$TELEGRAM_IP_SOURCE_URL"
download_file "$CLOUDFLARE_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv4.raw.txt"
download_file "$CLOUDFLARE_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv6.raw.txt"
# AWS JSON is shared between cloudfront (service-filtered) and aws (all services)
download_file "$AWS_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/aws.raw.json"
download_file "$FASTLY_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/fastly.raw.json"
download_and_classify_first_batch_source "github-json" "$GITHUB_IP_SOURCE_URL"
download_file_with_fallback \
  "$IP_BUILD_TMP_DIR/apple.raw.html" \
  "$APPLE_IP_SOURCE_URL" \
  "$APPLE_IP_SOURCE_FALLBACK_URL"

IP_NORMALIZE_MANIFEST="$IP_BUILD_TMP_DIR/normalize-tasks.json"

generate_ip_normalize_manifest "$IP_NORMALIZE_MANIFEST"
python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" batch "$IP_NORMALIZE_MANIFEST"
record_upstream_summary ip cn-ipv4 ok "$CN_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv4.raw.txt" "$IP_BUILD_TMP_DIR/cn_ipv4.cidr.txt"
record_upstream_summary ip cn-ipv6 ok "$CN_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv6.raw.txt" "$IP_BUILD_TMP_DIR/cn_ipv6.cidr.txt"
record_upstream_summary ip cn-asn-ipv4 ok "$CN_ASN_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_asn_ipv4.raw.txt" "$IP_BUILD_TMP_DIR/cn_asn_ipv4.cidr.txt"
record_upstream_summary ip cn-asn-ipv6 ok "$CN_ASN_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_asn_ipv6.raw.txt" "$IP_BUILD_TMP_DIR/cn_asn_ipv6.cidr.txt"
record_upstream_summary ip cloudflare-ipv4 ok "$CLOUDFLARE_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv4.raw.txt" "$IP_BUILD_TMP_DIR/cloudflare_ipv4.cidr.txt"
record_upstream_summary ip cloudflare-ipv6 ok "$CLOUDFLARE_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cloudflare_ipv6.raw.txt" "$IP_BUILD_TMP_DIR/cloudflare_ipv6.cidr.txt"
record_upstream_summary ip aws ok "$AWS_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/aws.raw.json" "$IP_BUILD_TMP_DIR/aws.cidr.txt"
record_upstream_summary ip cloudfront ok "$AWS_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/aws.raw.json" "$IP_BUILD_TMP_DIR/cloudfront.cidr.txt"
record_upstream_summary ip fastly ok "$FASTLY_IP_SOURCE_URL" "$IP_BUILD_TMP_DIR/fastly.raw.json" "$IP_BUILD_TMP_DIR/fastly.cidr.txt"
record_upstream_summary ip apple ok "${UPSTREAM_LAST_URL:-$APPLE_IP_SOURCE_URL}" "$IP_BUILD_TMP_DIR/apple.raw.html" "$IP_BUILD_TMP_DIR/apple.cidr.txt" "${UPSTREAM_LAST_FALLBACK_USED:-0}"
summarize_first_batch_checks
normalize_first_batch_source "google-json"
normalize_first_batch_source "github-json"
normalize_first_batch_source "telegram"
merge_cidr_plain_files \
  "$IP_BUILD_TMP_DIR/cn.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv6.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_asn_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_asn_ipv6.cidr.txt"
merge_cidr_plain_files \
  "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv6.cidr.txt"
assert_min_cidrs apple "$IP_BUILD_TMP_DIR/apple.cidr.txt" "$APPLE_MIN_CIDR_COUNT"

render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cn.cidr.txt"         "$IP_ARTIFACTS_DIR/surge/cn.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/google.cidr.txt"     "$IP_ARTIFACTS_DIR/surge/google.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/telegram.cidr.txt"   "$IP_ARTIFACTS_DIR/surge/telegram.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" "$IP_ARTIFACTS_DIR/surge/cloudflare.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/cloudfront.cidr.txt" "$IP_ARTIFACTS_DIR/surge/cloudfront.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/aws.cidr.txt"        "$IP_ARTIFACTS_DIR/surge/aws.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/fastly.cidr.txt"     "$IP_ARTIFACTS_DIR/surge/fastly.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/github.cidr.txt"     "$IP_ARTIFACTS_DIR/surge/github.list"
render_ip_plain_to_surge_list "$IP_BUILD_TMP_DIR/apple.cidr.txt"      "$IP_ARTIFACTS_DIR/surge/apple.list"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/cn.cidr.txt"         "$IP_ARTIFACTS_DIR/quanx/cn.list" "cn"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/google.cidr.txt"     "$IP_ARTIFACTS_DIR/quanx/google.list" "google"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/telegram.cidr.txt"   "$IP_ARTIFACTS_DIR/quanx/telegram.list" "telegram"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" "$IP_ARTIFACTS_DIR/quanx/cloudflare.list" "cloudflare"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/cloudfront.cidr.txt" "$IP_ARTIFACTS_DIR/quanx/cloudfront.list" "cloudfront"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/aws.cidr.txt"        "$IP_ARTIFACTS_DIR/quanx/aws.list" "aws"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/fastly.cidr.txt"     "$IP_ARTIFACTS_DIR/quanx/fastly.list" "fastly"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/github.cidr.txt"     "$IP_ARTIFACTS_DIR/quanx/github.list" "github"
render_ip_plain_to_quanx_list "$IP_BUILD_TMP_DIR/apple.cidr.txt"      "$IP_ARTIFACTS_DIR/quanx/apple.list" "apple"

# Streaming services: no official CIDR lists; use RIPE NCC Stat (RPKI data) by ASN.
sync_asn_ip_list netflix  "${NETFLIX_ASNS[@]}"
sync_asn_ip_list spotify  "${SPOTIFY_ASNS[@]}"
sync_asn_ip_list disney   "${DISNEY_ASNS[@]}"

assert_files_present "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/surge/*.list"
assert_files_present "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/quanx/*.list"
build_ip_artifacts_from_surge_dir \
  "$IP_ARTIFACTS_DIR/surge" \
  "$IP_BUILD_TMP_DIR" \
  "$IP_ARTIFACTS_DIR/sing-box" \
  "$IP_ARTIFACTS_DIR/mihomo"
build_ip_egern_artifacts_from_surge_dir \
  "$IP_ARTIFACTS_DIR/surge" \
  "$IP_BUILD_TMP_DIR" \
  "$IP_ARTIFACTS_DIR/egern"
assert_files_present "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/sing-box/*.srs"
assert_files_present "$IP_ARTIFACTS_DIR/mihomo" "$IP_ARTIFACTS_DIR/mihomo/*.mrs"
assert_files_present "$IP_ARTIFACTS_DIR/egern" "$IP_ARTIFACTS_DIR/egern/*.yaml"
write_upstream_summary_json

echo "=== SYNC DONE ==="
