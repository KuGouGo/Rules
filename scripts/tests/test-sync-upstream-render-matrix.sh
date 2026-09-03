#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import re
from pathlib import Path

script = Path("scripts/commands/sync-upstream.sh").read_text(encoding="utf-8")
rules = Path("scripts/lib/rules.sh").read_text(encoding="utf-8")
# Repository-owned lists (private, apple) are built by build-custom.sh now.
expected = ["cn", "google", "telegram", "cloudflare", "cloudfront", "fastly"]

match = re.search(r"^IP_TEXT_ARTIFACTS=\(([^)]+)\)$", script, re.MULTILINE)
if not match:
    raise SystemExit("test failed: IP_TEXT_ARTIFACTS is not declared")
actual = match.group(1).split()
if actual != expected:
    raise SystemExit(f"test failed: IP_TEXT_ARTIFACTS changed: {actual!r}")

function_match = re.search(
    r"render_ip_text_artifact\(\) \{(?P<body>.*?)\n\}",
    script,
    re.DOTALL,
)
if not function_match:
    raise SystemExit("test failed: render_ip_text_artifact function is missing")
body = function_match.group("body")

required_snippets = [
    'plain_file="$IP_BUILD_TMP_DIR/${name}.cidr.txt"',
    "render_ip_plain_to_surge_list",
    "render_ip_plain_to_quanx_list",
    "render_ip_plain_to_egern_yaml",
    '"$IP_ARTIFACTS_DIR/surge/${name}.list"',
    '"$IP_ARTIFACTS_DIR/quanx/${name}.list"',
    '"$IP_ARTIFACTS_DIR/egern/${name}.yaml"',
]
for snippet in required_snippets:
    if snippet not in body:
        raise SystemExit(f"test failed: render_ip_text_artifact missing {snippet!r}")

if 'render_ip_text_artifacts "${IP_TEXT_ARTIFACTS[@]}"' not in script:
    raise SystemExit("test failed: sync-upstream does not render the shared IP text artifact matrix")

summary_required_snippets = [
    'UPSTREAM_SUMMARY_FILE="$WORK_TMP_DIR/upstream-summary.jsonl"',
    'local json_file="$ARTIFACTS_DIR/upstream-summary.json"',
    'rm -f "$UPSTREAM_SUMMARY_FILE"',
]
for snippet in summary_required_snippets:
    if snippet not in script:
        raise SystemExit(f"test failed: sync-upstream summary lifecycle missing {snippet!r}")

ip_source_required_snippets = [
    'declare -A UPSTREAM_SETTINGS',
    'CN_CLANG_IPV4_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cn-clang-ipv4.url]}"',
    'CN_CLANG_IPV6_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cn-clang-ipv6.url]}"',
    'CN_17MON_IPV4_SOURCE_URL="${UPSTREAM_SETTINGS[ip.cn-17mon-ipv4.url]}"',
    'LOYALSOLDIER_GEOIP_CN_SOURCE_URL="${UPSTREAM_SETTINGS[ip.loyalsoldier-geoip-cn.url]}"',
    'cn-clang-ipv4 required "$CN_CLANG_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_clang_ipv4.raw.txt"',
    'cn-clang-ipv6 required "$CN_CLANG_IPV6_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_clang_ipv6.raw.txt"',
    'cn-17mon-ipv4 required "$CN_17MON_IPV4_SOURCE_URL" "$IP_BUILD_TMP_DIR/cn_17mon_ipv4.raw.txt"',
    'loyalsoldier-geoip-cn required "$LOYALSOLDIER_GEOIP_CN_SOURCE_URL" "$IP_BUILD_TMP_DIR/loyalsoldier-geoip-cn.raw.txt"',
    '"$IP_BUILD_TMP_DIR/cn_clang_ipv4.cidr.txt"',
    '"$IP_BUILD_TMP_DIR/cn_clang_ipv6.cidr.txt"',
    '"$IP_BUILD_TMP_DIR/cn_ipv46_apnic.cidr.txt"',
    '"$IP_BUILD_TMP_DIR/cn_17mon_ipv4.cidr.txt"',
    '"$IP_BUILD_TMP_DIR/loyalsoldier-geoip-cn.cidr.txt"',
    'cn-17mon-ipv4|$CN_17MON_IPV4_SOURCE_URL|cn_17mon_ipv4.raw.txt|cn_17mon_ipv4.cidr.txt|0',
    'loyalsoldier-geoip-cn|$LOYALSOLDIER_GEOIP_CN_SOURCE_URL|loyalsoldier-geoip-cn.raw.txt|loyalsoldier-geoip-cn.cidr.txt|0',
    'download_files_parallel',
    'verify_and_record_upstream_health',
    'prepare_ripe_stat_asns()',
    'raw_json="$IP_BUILD_TMP_DIR/ripe_as${asn}.raw.json"',
    'cidr_txt="$IP_BUILD_TMP_DIR/ripe_as${asn}.cidr.txt"',
    'download_args+=("ripe-stat-as${asn}" required "${RIPE_STAT_BASE_URL}${asn}" "$raw_json")',
    'download_files_parallel "${download_args[@]}"',
    'prepare_ripe_stat_asns \\',
]
for snippet in ip_source_required_snippets:
    if snippet not in script:
        raise SystemExit(f"test failed: sync-upstream missing optimized IP source snippet {snippet!r}")

for excluded in (
    "BUILTIN_PRIVATE_SOURCE_FILE",
    "BUILTIN_APPLE_SOURCE_FILE",
    "sources/builtin",
    "CN_IPV46_SOURCE_URL",
    "cn_ipv46.raw.txt",
    "cn_ipv46.cidr.txt",
    "CN_GEOIP_SOURCE_URL",
    "cn_geoip.raw.txt",
    "cn_geoip.cidr.txt",
    "APPLE_IP_SOURCE_URL",
    "AWS_IP_SOURCE_URL",
):
    if excluded in script:
        raise SystemExit(f"test failed: trimmed IP source was reintroduced: {excluded}")

domain_required_snippets = [
    'clone_repository_shallow "$DOMAIN_SOURCE_REPO_URL" "$WORK_TMP_DIR/domain-list-community"',
    'require_upstream_settings',
    'shellcrash-fakeip required "$SHELLCRASH_FAKEIP_SOURCE_URL" "$WORK_TMP_DIR/shellcrash-fakeip.raw.list"',
    '"$WORK_TMP_DIR/shellcrash-fakeip.raw.list"',
    '"$DOMAIN_RULE_TMP_DIR/fakeip-filter.list"',
    '"$WORK_TMP_DIR/domain-list-community/data"',
    'assert_domain_attr_derivatives "$DOMAIN_RULE_MANIFEST_FILE"',
]
for snippet in domain_required_snippets:
    if snippet not in script:
        raise SystemExit(f"test failed: sync-upstream missing domain derivative guard snippet {snippet!r}")

# Repository-owned IP lists (apple, private) are built by build-custom.sh
# from sources/custom/ip; the sync stage must not reference them.
if "apple.cidr.txt" in script or "private.cidr.txt" in script:
    raise SystemExit("test failed: repository-owned IP lists moved back into the sync stage")
if "apple.raw.html" in script or "APPLE_IP_SOURCE_URL" in script:
    raise SystemExit("test failed: Apple IP must not be fetched from a remote page")

for excluded in ("loyalsoldier-china-list", "china-list.list", "merge-domain-suffixes.py", "LOYALSOLDIER_CHINA_LIST_SOURCE_URL"):
    if excluded in script:
        raise SystemExit(f"test failed: DNS-only China List was reintroduced: {excluded}")

asn_merged_function_match = re.search(
    r"sync_merged_asn_ip_list\(\) \{(?P<body>.*?)\n\}",
    script,
    re.DOTALL,
)
if not asn_merged_function_match:
    raise SystemExit("test failed: sync_merged_asn_ip_list function is missing")
if 'render_ip_text_artifact "$name"' not in asn_merged_function_match.group("body"):
    raise SystemExit("test failed: sync_merged_asn_ip_list does not share the IP text render entrypoint")

asn_cidr_function_match = re.search(
    r"sync_asn_ip_cidrs\(\) \{(?P<body>.*?)\n\}",
    script,
    re.DOTALL,
)
if not asn_cidr_function_match:
    raise SystemExit("test failed: private sync_asn_ip_cidrs helper is missing")
if "render_ip_text_artifact" in asn_cidr_function_match.group("body"):
    raise SystemExit("test failed: private ASN CIDR helper must not render public artifacts")
if "sync_asn_ip_list" in script:
    raise SystemExit("test failed: unused sync_asn_ip_list helper was reintroduced")
if "telegram_asn.list" in script or "telegram_asn.yaml" in script:
    raise SystemExit("test failed: telegram_asn intermediate artifact leaked into sync script")
for removed_helper in (
    "merge_cidr_plain_files_dedup",
    "generate_normalize_manifest",
    "first_batch_status",
    "first_batch_reason",
    "first_batch_raw_file",
    "first_batch_source_type",
    "first_batch_config_name",
    "first_batch_source_url",
):
    if removed_helper in script:
        raise SystemExit(f"test failed: redundant helper was reintroduced: {removed_helper}")
if "declare -A FIRST_BATCH_RAW_FILE" not in script:
    raise SystemExit("test failed: first-batch source metadata is not table-driven")

if "compile_ip_plain_to_binary_artifacts" in rules:
    raise SystemExit("test failed: serial IP binary compiler was reintroduced")
if "build_ip_egern_artifacts_from_surge_dir" in rules:
    raise SystemExit("test failed: redundant Surge-to-Egern render path was reintroduced")
binary_builder = re.search(
    r"build_ip_artifacts_from_surge_dir\(\) \{(?P<body>.*?)\n\}",
    rules,
    re.DOTALL,
)
if not binary_builder:
    raise SystemExit("test failed: IP binary builder is missing")
for snippet in ("detect_compile_jobs", "compile_ip_binary_dirs"):
    if snippet not in binary_builder.group("body"):
        raise SystemExit(f"test failed: batch IP binary builder missing {snippet!r}")
if '"$IP_BUILD_TMP_DIR/binary-compile"' not in script:
    raise SystemExit("test failed: IP binary compiler does not use an isolated staging directory")
PY

echo "sync upstream render matrix tests passed"
