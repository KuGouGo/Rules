#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if [ -z "${RULES_ARTIFACT_ROOT:-}" ]; then
  RULES_BUILD_SCOPE=full exec "$ROOT_DIR/scripts/commands/build-artifacts-transaction.sh"
fi

WORK_TMP_DIR="$ROOT_DIR/.tmp/sync"
BIN_DIR="$ROOT_DIR/.bin"
DOMAIN_BUILD_TMP_DIR="$WORK_TMP_DIR/domain-build"
DOMAIN_RULE_TMP_DIR="$WORK_TMP_DIR/domain-rules"
IP_BUILD_TMP_DIR="$WORK_TMP_DIR/ip-build"
ARTIFACTS_DIR="${RULES_ARTIFACT_ROOT:-$ROOT_DIR/.output}"
DIAGNOSTICS_DIR="${RULES_ARTIFACT_DIAGNOSTICS_ROOT:-$ROOT_DIR/.tmp/artifact-diagnostics}"
DOMAIN_ARTIFACTS_DIR="$ARTIFACTS_DIR/domain"
IP_ARTIFACTS_DIR="$ARTIFACTS_DIR/ip"
DOMAIN_RULE_MANIFEST_FILE="$DOMAIN_ARTIFACTS_DIR/rule-manifest.json"
IP_TEXT_ARTIFACTS=(cn private google telegram cloudflare cloudfront aws fastly github apple)

UPSTREAMS_CONFIG_FILE="$ROOT_DIR/config/upstreams.json"
UPSTREAM_SUMMARY_FILE="$WORK_TMP_DIR/upstream-summary.jsonl"
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
CN_IPV46_SOURCE_URL="$(upstream_value ip cn-ipv46 url)"
CN_IPV46_APNIC_SOURCE_URL="$(upstream_value ip cn-ipv46-apnic url)"
LOYALSOLDIER_GEOIP_CN_SOURCE_URL="$(upstream_value ip loyalsoldier-geoip-cn url)"
LOYALSOLDIER_GEOIP_PRIVATE_SOURCE_URL="$(upstream_value ip loyalsoldier-geoip-private url)"
GOOGLE_IP_SOURCE_URL="$(upstream_value ip google url)"
TELEGRAM_IP_SOURCE_URL="$(upstream_value ip telegram url)"
CLOUDFLARE_IPV4_SOURCE_URL="$(upstream_value ip cloudflare-ipv4 url)"
CLOUDFLARE_IPV6_SOURCE_URL="$(upstream_value ip cloudflare-ipv6 url)"
AWS_IP_SOURCE_URL="$(upstream_value ip aws url)"
CLOUDFRONT_IP_SOURCE_URL="$(upstream_value ip cloudfront url)"
FASTLY_IP_SOURCE_URL="$(upstream_value ip fastly url)"
GITHUB_IP_SOURCE_URL="$(upstream_value ip github url)"
APPLE_IP_SOURCE_URL="$(upstream_value ip apple url)"
APPLE_IP_SOURCE_FALLBACK_URL="$(upstream_value ip apple fallback_url)"
RIPE_STAT_BASE_URL="$(upstream_value ip ripe-stat base_url)"
DLC_MIN_ATTR_RULESETS="${DLC_MIN_ATTR_RULESETS:-300}"
DLC_MIN_CN_ATTR_RULESETS="${DLC_MIN_CN_ATTR_RULESETS:-100}"
DLC_MIN_NOT_CN_ATTR_RULESETS="${DLC_MIN_NOT_CN_ATTR_RULESETS:-30}"
DLC_MIN_ADS_ATTR_RULESETS="${DLC_MIN_ADS_ATTR_RULESETS:-100}"
DLC_MIN_REGIONAL_RULESETS="${DLC_MIN_REGIONAL_RULESETS:-40}"
read -r -a TELEGRAM_ASNS <<< "$(upstream_asn_group telegram)"
read -r -a NETFLIX_ASNS <<< "$(upstream_asn_group netflix)"
read -r -a SPOTIFY_ASNS <<< "$(upstream_asn_group spotify)"
read -r -a DISNEY_ASNS <<< "$(upstream_asn_group disney)"

# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=scripts/lib/rules.sh
source "$ROOT_DIR/scripts/lib/rules.sh"
setup_tool_cache

rm -rf "$WORK_TMP_DIR"
mkdir -p "$WORK_TMP_DIR" "$BIN_DIR" "$DOMAIN_BUILD_TMP_DIR" "$DOMAIN_RULE_TMP_DIR" "$IP_BUILD_TMP_DIR"
preserve_sync_diagnostics() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    mkdir -p "$DIAGNOSTICS_DIR"
    [ ! -s "$UPSTREAM_SUMMARY_FILE" ] || cp "$UPSTREAM_SUMMARY_FILE" "$DIAGNOSTICS_DIR/upstream-summary.jsonl"
    [ ! -f "$ARTIFACTS_DIR/upstream-summary.json" ] || cp "$ARTIFACTS_DIR/upstream-summary.json" "$DIAGNOSTICS_DIR/upstream-summary.json"
  fi
  rm -rf "$WORK_TMP_DIR"
  return "$status"
}
trap preserve_sync_diagnostics EXIT

mkdir -p "$DOMAIN_ARTIFACTS_DIR" "$IP_ARTIFACTS_DIR"
: > "$UPSTREAM_SUMMARY_FILE"

echo "=== SYNC START ==="

inject_sync_failure() {
  local point="$1"
  if [ "${RULES_SYNC_FAIL_AT:-}" = "$point" ]; then
    echo "injected upstream sync failure at $point" >&2
    return 1
  fi
}

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
import hashlib, json, sys
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
    if path.is_file():
        content = path.read_bytes()
        info["bytes"] = len(content)
        info["sha256"] = hashlib.sha256(content).hexdigest()
        lines = [line for line in content.decode("utf-8", errors="ignore").splitlines() if line.strip() and not line.lstrip().startswith("#")]
        info["entries"] = len(lines)
    elif path.is_dir():
        files = sorted(candidate for candidate in path.rglob("*") if candidate.is_file())
        digest = hashlib.sha256()
        total_bytes = 0
        for candidate in files:
            relative = candidate.relative_to(path).as_posix().encode()
            content = candidate.read_bytes()
            digest.update(relative + b"\0" + content + b"\0")
            total_bytes += len(content)
        info["bytes"] = total_bytes
        info["entries"] = len(files)
        info["sha256"] = digest.hexdigest()
    payload[key] = info
Path(summary_file).parent.mkdir(parents=True, exist_ok=True)
with open(summary_file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
PY
}

verify_and_record_upstream_health() {
  local category="$1"
  local name="$2"
  local url="$3"
  local raw_file="$4"
  local normalized_file="$5"
  local fallback_used="${6:-0}"
  local context="${7:-}"
  local health_json status detail health_detail verifier_failed=0

  if health_json="$(python3 "$ROOT_DIR/scripts/tools/verify-upstream-health.py" \
    "$UPSTREAMS_CONFIG_FILE" "$category" "$name" "$raw_file" "$normalized_file")"; then
    :
  else
    verifier_failed=1
  fi
  if ! status="$(printf '%s' "$health_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' 2>/dev/null)"; then
    status=semantic_regression
    verifier_failed=1
  fi
  case "$status" in
    ok|semantic_regression) ;;
    *) status=semantic_regression; verifier_failed=1 ;;
  esac
  if [ "$status" = "semantic_regression" ] && [ "$verifier_failed" -eq 0 ]; then
    detail="optional source failed health policy"
  else
    detail=""
  fi
  health_detail="$(printf '%s' "$health_json" | python3 -c 'import json,sys; print("; ".join(json.load(sys.stdin).get("errors", [])))' 2>/dev/null || printf 'health verifier failed')"
  detail="${health_detail:-$detail}"
  if [ -n "$context" ]; then
    detail="${context}${detail:+; $detail}"
  fi
  record_upstream_summary \
    "$category" "$name" "$status" "$url" "$raw_file" "$normalized_file" "$fallback_used" "$detail"
  if [ "$verifier_failed" -ne 0 ]; then
    echo "required upstream $name failed configured health policy: $detail" >&2
    return 1
  fi
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
  rm -f "$UPSTREAM_SUMMARY_FILE"
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
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" merge "$output_file" "$@"
}

merge_cidr_plain_files_dedup() {
  local output_file="$1"
  shift
  python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" merge-dedupe "$output_file" "$@"
}

render_ip_text_artifact() {
  local name="$1"
  local plain_file="$IP_BUILD_TMP_DIR/${name}.cidr.txt"

  render_ip_plain_to_surge_list \
    "$plain_file" \
    "$IP_ARTIFACTS_DIR/surge/${name}.list"
  render_ip_plain_to_quanx_list \
    "$plain_file" \
    "$IP_ARTIFACTS_DIR/quanx/${name}.list" \
    "$name"
}

render_ip_text_artifacts() {
  local name

  for name in "$@"; do
    render_ip_text_artifact "$name"
  done
}

sync_asn_ip_cidrs() {
  local name="$1"
  shift
  local -a asns=("$@")
  local -a cidr_files=()
  local asn raw_json cidr_txt merge_mode health_json health_status health_detail

  for asn in "${asns[@]}"; do
    raw_json="$IP_BUILD_TMP_DIR/${name}_as${asn}.raw.json"
    cidr_txt="$IP_BUILD_TMP_DIR/${name}_as${asn}.cidr.txt"
    download_file "${RIPE_STAT_BASE_URL}${asn}" "$raw_json"
    cidr_files+=("$cidr_txt")
  done

  # Normalize separately so malformed responses are attributed and reported
  # before they block the transaction.
  for asn in "${asns[@]}"; do
    raw_json="$IP_BUILD_TMP_DIR/${name}_as${asn}.raw.json"
    cidr_txt="$IP_BUILD_TMP_DIR/${name}_as${asn}.cidr.txt"
    if ! python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" single ripe-stat-json "$raw_json" "$cidr_txt"; then
      : > "$cidr_txt"
      record_upstream_summary ip "ripe-stat-as${asn}" semantic_regression "${RIPE_STAT_BASE_URL}${asn}" "$raw_json" "$cidr_txt" 0 "invalid RIPE Stat response"
      echo "RIPE Stat response AS${asn} is invalid" >&2
      return 1
    fi
  done

  # Every RIPE Stat response is independently subject to the configured source
  # policy. Record the failing response before returning so transaction
  # diagnostics explain which ASN was undersized or invalid.
  for asn in "${asns[@]}"; do
    raw_json="$IP_BUILD_TMP_DIR/${name}_as${asn}.raw.json"
    cidr_txt="$IP_BUILD_TMP_DIR/${name}_as${asn}.cidr.txt"
    if health_json="$(python3 "$ROOT_DIR/scripts/tools/verify-upstream-health.py" "$UPSTREAMS_CONFIG_FILE" ip ripe-stat "$raw_json" "$cidr_txt")"; then
      health_status=ok
    else
      health_status=semantic_regression
    fi
    health_detail="$(printf '%s' "$health_json" | python3 -c 'import json,sys; print("; ".join(json.load(sys.stdin).get("errors", [])))' 2>/dev/null || printf 'health verifier failed')"
    record_upstream_summary ip "ripe-stat-as${asn}" "$health_status" "${RIPE_STAT_BASE_URL}${asn}" "$raw_json" "$cidr_txt" 0 "$health_detail"
    if [ "$health_status" != "ok" ]; then
      echo "RIPE Stat response AS${asn} failed configured health policy: $health_detail" >&2
      return 1
    fi
  done

  merge_mode="${ASN_CIDR_MERGE_MODE:-collapse}"
  case "$merge_mode" in
    collapse) merge_cidr_plain_files "$IP_BUILD_TMP_DIR/${name}.cidr.txt" "${cidr_files[@]}" ;;
    dedupe) merge_cidr_plain_files_dedup "$IP_BUILD_TMP_DIR/${name}.cidr.txt" "${cidr_files[@]}" ;;
    *)
      echo "unsupported ASN_CIDR_MERGE_MODE: $merge_mode" >&2
      return 1
      ;;
  esac

  if [ ! -s "$IP_BUILD_TMP_DIR/${name}.cidr.txt" ]; then
    echo "RIPE Stat group $name produced no prefixes (ASNs: ${asns[*]})" >&2
    record_upstream_summary ip "ripe-stat-group-${name}" semantic_regression "$RIPE_STAT_BASE_URL" "" "$IP_BUILD_TMP_DIR/${name}.cidr.txt" 0 "empty normalized group"
    return 1
  fi

  local group_raw="$IP_BUILD_TMP_DIR/${name}.ripe-group.raw"
  : > "$group_raw"
  for asn in "${asns[@]}"; do
    cat "$IP_BUILD_TMP_DIR/${name}_as${asn}.raw.json" >> "$group_raw"
  done
  if health_json="$(python3 "$ROOT_DIR/scripts/tools/verify-upstream-health.py" "$UPSTREAMS_CONFIG_FILE" ip ripe-stat "$group_raw" "$IP_BUILD_TMP_DIR/${name}.cidr.txt")"; then
    health_status=ok
  else
    health_status=semantic_regression
  fi
  health_detail="$(printf '%s' "$health_json" | python3 -c 'import json,sys; print("; ".join(json.load(sys.stdin).get("errors", [])))' 2>/dev/null || printf 'health verifier failed')"
  record_upstream_summary ip "ripe-stat-group-${name}" "$health_status" "$RIPE_STAT_BASE_URL" "$group_raw" "$IP_BUILD_TMP_DIR/${name}.cidr.txt" 0 "asns=${asns[*]}${health_detail:+; $health_detail}"
  if [ "$health_status" != "ok" ]; then
    echo "RIPE Stat group $name failed configured health policy: $health_detail" >&2
    return 1
  fi
}

# sync_asn_ip_list <name> <asn> [<asn> ...]
# Download RIPEstat announced-prefix data for each ASN, normalize it in one
# batch, merge it, and render public IP text artifacts for the named ruleset.
sync_asn_ip_list() {
  local name="$1"
  shift
  local -a asns=("$@")

  sync_asn_ip_cidrs "$name" "${asns[@]}"

  if [ ! -s "$IP_BUILD_TMP_DIR/${name}.cidr.txt" ]; then
    return 0
  fi

  render_ip_text_artifact "$name"
  record_upstream_summary ip "${name}-asn" ok "$RIPE_STAT_BASE_URL" "" "$IP_BUILD_TMP_DIR/${name}.cidr.txt" 0 "asns=${asns[*]}"
}

sync_merged_asn_ip_list() {
  local name="$1"
  shift
  local source_file="$IP_BUILD_TMP_DIR/${name}.cidr.txt"
  local asn_file="$IP_BUILD_TMP_DIR/${name}_asn.cidr.txt"
  local merged_file="$IP_BUILD_TMP_DIR/${name}_merged.cidr.txt"

  sync_asn_ip_cidrs "${name}_asn" "$@"

  if [ ! -s "$asn_file" ]; then
    echo "warning: no ASN prefixes found for $name, keeping direct source only" >&2
    return 0
  fi

  # ASN prefixes are still parsed to CIDR, then collapsed with the official
  # list so redundant child prefixes do not bloat published rules.
  merge_cidr_plain_files "$merged_file" "$source_file" "$asn_file"
  mv "$merged_file" "$source_file"
  render_ip_text_artifact "$name"
  record_upstream_summary ip "${name}-merged" ok "$RIPE_STAT_BASE_URL" "" "$source_file" 0 "official+asn-collapsed"
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
    text "$tmp_dir/cn_ipv46.raw.txt" "$tmp_dir/cn_ipv46.cidr.txt" \
    text "$tmp_dir/cn_ipv46_apnic.raw.txt" "$tmp_dir/cn_ipv46_apnic.cidr.txt" \
    text "$tmp_dir/loyalsoldier_geoip_cn.raw.txt" "$tmp_dir/loyalsoldier_geoip_cn.cidr.txt" \
    text "$tmp_dir/private.raw.txt" "$tmp_dir/private.cidr.txt" \
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

first_batch_config_name() {
  case "$1" in
    google-json) printf '%s' google ;;
    github-json) printf '%s' github ;;
    telegram) printf '%s' telegram ;;
    *) echo "unsupported first-batch source: $1" >&2; return 1 ;;
  esac
}

first_batch_source_url() {
  case "$1" in
    google-json) printf '%s' "$GOOGLE_IP_SOURCE_URL" ;;
    github-json) printf '%s' "$GITHUB_IP_SOURCE_URL" ;;
    telegram) printf '%s' "$TELEGRAM_IP_SOURCE_URL" ;;
    *) echo "unsupported first-batch source: $1" >&2; return 1 ;;
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
  if [ "$status" != "ok" ]; then
    record_upstream_summary \
      ip \
      "$(first_batch_config_name "$source")" \
      "$status" \
      "$(first_batch_source_url "$source")" \
      "$raw_file" \
      "" \
      0 \
      "$reason"
  fi
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

  if ! python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" single "$source_type" "$raw_file" "$output_file"; then
    record_upstream_summary \
      ip \
      "$(first_batch_config_name "$source")" \
      semantic_regression \
      "$(first_batch_source_url "$source")" \
      "$raw_file" \
      "$output_file" \
      0 \
      "normalization failed"
    return 1
  fi
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

assert_domain_attr_derivatives() {
  local manifest_file="$1"

  python3 - <<'PY' "$manifest_file" "$DLC_MIN_ATTR_RULESETS" "$DLC_MIN_CN_ATTR_RULESETS" "$DLC_MIN_NOT_CN_ATTR_RULESETS" "$DLC_MIN_ADS_ATTR_RULESETS" "$DLC_MIN_REGIONAL_RULESETS"
import json
import sys
from pathlib import Path

manifest_file = Path(sys.argv[1])
min_attr = int(sys.argv[2])
min_cn = int(sys.argv[3])
min_not_cn = int(sys.argv[4])
min_ads = int(sys.argv[5])
min_regional = int(sys.argv[6])

manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
lists = manifest.get("lists", [])
names = {entry.get("name", "") for entry in lists}
attr_rule_sets = [entry for entry in lists if entry.get("kind") == "attr"]
cn_attr = [entry for entry in lists if entry.get("attr") == "cn"]
not_cn_attr = [entry for entry in lists if entry.get("attr") == "!cn"]
ads_attr = [entry for entry in lists if entry.get("attr") == "ads"]
regional = [entry for entry in lists if entry.get("kind") == "regional"]
required = {
    "alibaba@!cn",
    "apple@ads",
    "apple@cn",
    "baidu@ads",
    "category-games-!cn@cn",
    "cn",
    "geolocation-!cn",
    "geolocation-!cn@cn",
    "geolocation-cn",
    "google@cn",
    "speedtest@ads",
    "tld-!cn",
    "tld-cn",
}

print(
    "domain derivative rule sets: "
    f"attr={len(attr_rule_sets)} (min {min_attr}), "
    f"@cn={len(cn_attr)} (min {min_cn}), "
    f"@!cn={len(not_cn_attr)} (min {min_not_cn}), "
    f"@ads={len(ads_attr)} (min {min_ads}), "
    f"regional={len(regional)} (min {min_regional})"
)

errors = []
if len(attr_rule_sets) < min_attr:
    errors.append(f"attribute derivative rule sets too low: {len(attr_rule_sets)} < {min_attr}")
if len(cn_attr) < min_cn:
    errors.append(f"@cn derivative rule sets too low: {len(cn_attr)} < {min_cn}")
if len(not_cn_attr) < min_not_cn:
    errors.append(f"@!cn derivative rule sets too low: {len(not_cn_attr)} < {min_not_cn}")
if len(ads_attr) < min_ads:
    errors.append(f"@ads derivative rule sets too low: {len(ads_attr)} < {min_ads}")
if len(regional) < min_regional:
    errors.append(f"regional -cn/-!cn rule sets too low: {len(regional)} < {min_regional}")
geolocation_regions = set(manifest.get("region_pairs", {}).get("geolocation", []))
if not {"cn", "!cn"}.issubset(geolocation_regions):
    errors.append("missing geolocation -cn/-!cn regional pair")

missing = sorted(required - names)
if missing:
    errors.append("missing required derivative rule sets: " + ", ".join(missing))

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
}

# Domain rules from domain-list-community/data. The source tree preserves
# upstream @attributes and -cn/-!cn regional source names, which are required
# for derived rule sets such as geolocation-!cn@cn and apple@cn.
rm -rf "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/mihomo"
clone_repository_shallow "$DOMAIN_SOURCE_REPO_URL" "$WORK_TMP_DIR/domain-list-community"
python3 "$ROOT_DIR/scripts/tools/export-domain-rules.py" export \
  "$WORK_TMP_DIR/domain-list-community/data" \
  "$DOMAIN_RULE_TMP_DIR"
python3 "$ROOT_DIR/scripts/tools/export-domain-rules.py" domain-rule-manifest \
  "$DOMAIN_RULE_TMP_DIR" \
  "$DOMAIN_RULE_MANIFEST_FILE"
assert_domain_attr_derivatives "$DOMAIN_RULE_MANIFEST_FILE"
verify_and_record_upstream_health \
  domain \
  dlc \
  "$DOMAIN_SOURCE_REPO_URL" \
  "$WORK_TMP_DIR/domain-list-community/data" \
  "$DOMAIN_RULE_TMP_DIR" \
  0 \
  "commit=$(git -C "$WORK_TMP_DIR/domain-list-community" rev-parse HEAD)"
assert_files_present "$DOMAIN_RULE_TMP_DIR" "$DOMAIN_RULE_TMP_DIR/*.list"
render_domain_rule_dir_to_text_platform_dirs \
  "$DOMAIN_RULE_TMP_DIR" \
  "$DOMAIN_ARTIFACTS_DIR/surge" \
  "$DOMAIN_ARTIFACTS_DIR/quanx" \
  "$DOMAIN_ARTIFACTS_DIR/egern"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/surge" "$DOMAIN_ARTIFACTS_DIR/surge/*.list"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/quanx" "$DOMAIN_ARTIFACTS_DIR/quanx/*.list"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/egern" "$DOMAIN_ARTIFACTS_DIR/egern/*.yaml"
inject_sync_failure late-domain

build_domain_artifacts_from_rule_dir \
  "$DOMAIN_RULE_TMP_DIR" \
  "$DOMAIN_BUILD_TMP_DIR/domain-compile" \
  "$DOMAIN_ARTIFACTS_DIR/sing-box" \
  "$DOMAIN_ARTIFACTS_DIR/mihomo"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/sing-box" "$DOMAIN_ARTIFACTS_DIR/sing-box/*.srs"
assert_files_present "$DOMAIN_ARTIFACTS_DIR/mihomo" "$DOMAIN_ARTIFACTS_DIR/mihomo/*.mrs"

# IP rules from curated remote sources
rm -rf "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/egern" "$IP_ARTIFACTS_DIR/sing-box" "$IP_ARTIFACTS_DIR/mihomo"
mkdir -p "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/quanx"

download_file "$CN_IPV46_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv46.raw.txt"
download_file "$CN_IPV46_APNIC_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_ipv46_apnic.raw.txt"
download_file "$LOYALSOLDIER_GEOIP_CN_SOURCE_URL" "$IP_BUILD_TMP_DIR/loyalsoldier_geoip_cn.raw.txt"
download_file "$LOYALSOLDIER_GEOIP_PRIVATE_SOURCE_URL" "$IP_BUILD_TMP_DIR/private.raw.txt"
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
APPLE_RESOLVED_URL="${UPSTREAM_LAST_URL:-$APPLE_IP_SOURCE_URL}"
APPLE_FALLBACK_USED="${UPSTREAM_LAST_FALLBACK_USED:-0}"

IP_NORMALIZE_MANIFEST="$IP_BUILD_TMP_DIR/normalize-tasks.json"

generate_ip_normalize_manifest "$IP_NORMALIZE_MANIFEST"
python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" batch "$IP_NORMALIZE_MANIFEST"
summarize_first_batch_checks
normalize_first_batch_source "google-json"
normalize_first_batch_source "github-json"
normalize_first_batch_source "telegram"
while IFS='|' read -r health_name health_url health_raw health_normalized fallback_used; do
  verify_and_record_upstream_health \
    ip \
    "$health_name" \
    "$health_url" \
    "$IP_BUILD_TMP_DIR/$health_raw" \
    "$IP_BUILD_TMP_DIR/$health_normalized" \
    "$fallback_used"
done <<EOF
cn-ipv46|$CN_IPV46_SOURCE_URL|cn_ipv46.raw.txt|cn_ipv46.cidr.txt|0
cn-ipv46-apnic|$CN_IPV46_APNIC_SOURCE_URL|cn_ipv46_apnic.raw.txt|cn_ipv46_apnic.cidr.txt|0
loyalsoldier-geoip-cn|$LOYALSOLDIER_GEOIP_CN_SOURCE_URL|loyalsoldier_geoip_cn.raw.txt|loyalsoldier_geoip_cn.cidr.txt|0
loyalsoldier-geoip-private|$LOYALSOLDIER_GEOIP_PRIVATE_SOURCE_URL|private.raw.txt|private.cidr.txt|0
google|$GOOGLE_IP_SOURCE_URL|google.raw.json|google.cidr.txt|0
telegram|$TELEGRAM_IP_SOURCE_URL|telegram.raw.txt|telegram.cidr.txt|0
cloudflare-ipv4|$CLOUDFLARE_IPV4_SOURCE_URL|cloudflare_ipv4.raw.txt|cloudflare_ipv4.cidr.txt|0
cloudflare-ipv6|$CLOUDFLARE_IPV6_SOURCE_URL|cloudflare_ipv6.raw.txt|cloudflare_ipv6.cidr.txt|0
aws|$AWS_IP_SOURCE_URL|aws.raw.json|aws.cidr.txt|0
cloudfront|$CLOUDFRONT_IP_SOURCE_URL|aws.raw.json|cloudfront.cidr.txt|0
fastly|$FASTLY_IP_SOURCE_URL|fastly.raw.json|fastly.cidr.txt|0
github|$GITHUB_IP_SOURCE_URL|github.raw.json|github.cidr.txt|0
apple|$APPLE_RESOLVED_URL|apple.raw.html|apple.cidr.txt|$APPLE_FALLBACK_USED
EOF
python3 "$ROOT_DIR/scripts/tools/normalize-ip-rules.py" merge \
  "$IP_BUILD_TMP_DIR/cn.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv46.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cn_ipv46_apnic.cidr.txt" \
  "$IP_BUILD_TMP_DIR/loyalsoldier_geoip_cn.cidr.txt"
merge_cidr_plain_files \
  "$IP_BUILD_TMP_DIR/cloudflare.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv4.cidr.txt" \
  "$IP_BUILD_TMP_DIR/cloudflare_ipv6.cidr.txt"
render_ip_text_artifacts "${IP_TEXT_ARTIFACTS[@]}"

# Supplement Telegram's direct source with ASN-derived prefixes.
sync_merged_asn_ip_list telegram "${TELEGRAM_ASNS[@]}"

# Streaming services without a direct CIDR source use ASN-derived prefixes.
sync_asn_ip_list netflix  "${NETFLIX_ASNS[@]}"
sync_asn_ip_list spotify  "${SPOTIFY_ASNS[@]}"
sync_asn_ip_list disney   "${DISNEY_ASNS[@]}"

assert_files_present "$IP_ARTIFACTS_DIR/surge" "$IP_ARTIFACTS_DIR/surge/*.list"
assert_files_present "$IP_ARTIFACTS_DIR/quanx" "$IP_ARTIFACTS_DIR/quanx/*.list"
inject_sync_failure late-ip
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
inject_sync_failure late-compiler
write_upstream_summary_json
python3 "$ROOT_DIR/scripts/tools/artifact_origins.py" reset \
  "$ARTIFACTS_DIR" \
  generated-upstream

echo "=== SYNC DONE ==="
