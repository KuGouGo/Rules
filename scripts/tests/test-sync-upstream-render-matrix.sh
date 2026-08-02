#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import re
from pathlib import Path

script = Path("scripts/commands/sync-upstream.sh").read_text(encoding="utf-8")
expected = ["cn", "private", "google", "telegram", "cloudflare", "cloudfront", "aws", "fastly", "github", "apple"]

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
    '"$IP_ARTIFACTS_DIR/surge/${name}.list"',
    '"$IP_ARTIFACTS_DIR/quanx/${name}.list"',
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
    'mapfile -t UPSTREAM_SETTINGS',
    'BUILTIN_PRIVATE_SOURCE_FILE="$ROOT_DIR/sources/builtin/ip/private.list"',
    'download_files_parallel',
    'SUKKA_MARKER_DOMAIN="7h15_ru1353t_1s_m4d3_by_5ukk4w.skk.moe"',
    '"$BUILTIN_PRIVATE_SOURCE_FILE"',
    '"$IP_BUILD_TMP_DIR/private.cidr.txt"',
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
    "LOYALSOLDIER_GEOIP_CN_SOURCE_URL",
    "loyalsoldier_geoip_cn",
    "SUKKA_CHINA_IPV4_SOURCE_URL",
    "SUKKA_CHINA_IPV6_SOURCE_URL",
    "sukka_china_ipv4",
    "sukka_china_ipv6",
):
    if excluded in script:
        raise SystemExit(f"test failed: low-marginal China GeoIP source was reintroduced: {excluded}")

domain_required_snippets = [
    'clone_repository_shallow "$DOMAIN_SOURCE_REPO_URL" "$WORK_TMP_DIR/domain-list-community"',
    'LOYALSOLDIER_CHINA_LIST_SOURCE_URL="${UPSTREAM_SETTINGS[1]}"',
    'loyalsoldier-china-list required "$LOYALSOLDIER_CHINA_LIST_SOURCE_URL" "$WORK_TMP_DIR/loyalsoldier-china-list.raw.txt"',
    ': > "$DOMAIN_RULE_TMP_DIR/china-list.list"',
    '"$DOMAIN_RULE_TMP_DIR/china-list.list"',
    '--normalized-output "$WORK_TMP_DIR/loyalsoldier-china-list.normalized.list"',
    'sukka-apple-intelligence|$SUKKA_APPLE_INTELLIGENCE_SOURCE_URL|classical|apple-intelligence',
    'sukka-icloud-private-relay|$SUKKA_ICLOUD_PRIVATE_RELAY_SOURCE_URL|domain-set|icloudprivaterelay',
    'sukka-game-download|$SUKKA_GAME_DOWNLOAD_SOURCE_URL|domain-set|category-game-platforms-download',
    'sukka-domestic required "$SUKKA_DOMESTIC_SOURCE_URL" "$WORK_TMP_DIR/sukka-domestic.raw.conf"',
    'sukka-ai required "$SUKKA_AI_SOURCE_URL" "$WORK_TMP_DIR/sukka-ai.raw.conf"',
    'sukka-apple-cdn|$SUKKA_APPLE_CDN_SOURCE_URL|domain-set|apple@cn',
    'sukka-apple-cn|$SUKKA_APPLE_CN_SOURCE_URL|classical|apple@cn',
    'sukka-microsoft-cdn|$SUKKA_MICROSOFT_CDN_SOURCE_URL|classical|microsoft@cn',
    '--allow-unsupported-rule DOMAIN-KEYWORD,openai',
    '--allow-unsupported-rule DOMAIN-KEYWORD,alkalimakersuite-pa.clients6.google.com',
    '"$DOMAIN_RULE_TMP_DIR/cn.list"',
    "--allow-unsupported-rule 'DOMAIN-WILDCARD,*.qhimgs?.com'",
    '--exclude-file "$DOMAIN_RULE_TMP_DIR/category-ads-all.list"',
    'sukka-apple-services required "$SUKKA_APPLE_SERVICES_SOURCE_URL" "$IP_BUILD_TMP_DIR/sukka_apple_services.raw.txt"',
    '--ignore-domain "$SUKKA_MARKER_DOMAIN"',
    '"$IP_BUILD_TMP_DIR/sukka_apple_services.cidr.txt"',
    '"$WORK_TMP_DIR/domain-list-community/data"',
    'assert_domain_attr_derivatives "$DOMAIN_RULE_MANIFEST_FILE"',
    '"apple@cn"',
    '"apple@ads"',
    '"geolocation-!cn@cn"',
    '"alibaba@!cn"',
    '"speedtest@ads"',
    '"missing geolocation -cn/-!cn regional pair"',
]
for snippet in domain_required_snippets:
    if snippet not in script:
        raise SystemExit(f"test failed: sync-upstream missing domain derivative guard snippet {snippet!r}")

expected_sukka_merge_targets = {
    "sukka-apple-intelligence": "apple-intelligence",
    "sukka-icloud-private-relay": "icloudprivaterelay",
    "sukka-game-download": "category-game-platforms-download",
    "sukka-apple-cdn": "apple@cn",
    "sukka-apple-cn": "apple@cn",
    "sukka-microsoft-cdn": "microsoft@cn",
}
actual_sukka_merge_targets = dict(
    re.findall(r"^(sukka-[^|]+)\|\$[^|]+\|[^|]+\|([^|\n]+)$", script, re.MULTILINE)
)
if actual_sukka_merge_targets != expected_sukka_merge_targets:
    raise SystemExit(
        "test failed: focused Sukka sources must merge into existing domain targets: "
        f"{actual_sukka_merge_targets!r}"
    )

for source_file, target_file in (
    ("sukka-ai.raw.conf", "category-ai-!cn.list"),
    ("sukka-domestic.raw.conf", "cn.list"),
):
    merge_pattern = re.compile(
        r'merge-domain-rule-source\.py"(?P<body>.*?)verify_and_record_upstream_health',
        re.DOTALL,
    )
    if not any(
        source_file in match.group("body") and target_file in match.group("body")
        for match in merge_pattern.finditer(script)
    ):
        raise SystemExit(f"test failed: {source_file} is not merged into existing target {target_file}")

if re.search(r'\$DOMAIN_RULE_TMP_DIR/(?:\$\{)?sukka[-_][^"}]*\.list', script):
    raise SystemExit("test failed: a focused Sukka source is published as a standalone domain artifact")

apple_ip_merge_start = script.index('"$IP_BUILD_TMP_DIR/apple.merged.cidr.txt"')
apple_ip_merge_body = script[apple_ip_merge_start : apple_ip_merge_start + 300]
if "sukka_apple_services.cidr.txt" not in apple_ip_merge_body:
    raise SystemExit("test failed: Sukka Apple IP source must merge into the existing apple artifact")

china_merge = re.search(
    r'merge-domain-suffixes\.py"(?P<body>.*?)--normalized-output',
    script,
    re.DOTALL,
)
if not china_merge or 'china-list.list' not in china_merge.group("body"):
    raise SystemExit("test failed: China List must produce its independent DNS artifact")
for routing_target in ('cn.list', 'geolocation-cn.list'):
    if routing_target in china_merge.group("body"):
        raise SystemExit(f"test failed: DNS-only China List leaked into routing target {routing_target}")

asn_function_match = re.search(
    r"sync_asn_ip_list\(\) \{(?P<body>.*?)\n\}",
    script,
    re.DOTALL,
)
if not asn_function_match:
    raise SystemExit("test failed: sync_asn_ip_list function is missing")
if 'render_ip_text_artifact "$name"' not in asn_function_match.group("body"):
    raise SystemExit("test failed: sync_asn_ip_list does not share the IP text render entrypoint")

asn_cidr_function_match = re.search(
    r"sync_asn_ip_cidrs\(\) \{(?P<body>.*?)\n\}",
    script,
    re.DOTALL,
)
if not asn_cidr_function_match:
    raise SystemExit("test failed: private sync_asn_ip_cidrs helper is missing")
if "render_ip_text_artifact" in asn_cidr_function_match.group("body"):
    raise SystemExit("test failed: private ASN CIDR helper must not render public artifacts")
if 'sync_asn_ip_list "${name}_asn"' in script:
    raise SystemExit("test failed: merged ASN sources must not render private *_asn artifacts")
if "telegram_asn.list" in script or "telegram_asn.yaml" in script:
    raise SystemExit("test failed: telegram_asn intermediate artifact leaked into sync script")
PY

echo "sync upstream render matrix tests passed"
