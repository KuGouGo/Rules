#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import re
from pathlib import Path

script = Path("scripts/commands/sync-upstream.sh").read_text(encoding="utf-8")
rules = Path("scripts/lib/rules.sh").read_text(encoding="utf-8")
expected = ["cn", "google", "telegram", "apple"]

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

config_driven_snippets = [
    "declare -A UPSTREAM_SETTINGS",
    'IP_TEXT_SOURCE_NAMES+=("$name")',
    'IP_ASN_SOURCE_NAMES+=("$name")',
    'IP_SOURCE_EXTENSIONS["$name"]="tsv.gz"',
    "download_ip_sources()",
    'download_files_parallel "${download_args[@]}"',
    "generate_ip_normalize_manifest()",
    'triplets+=(',
    "check_ip_text_source_health()",
    'check_upstream_health ip "$name"',
    "merge_cn_cidr_sources()",
    'merge_cidr_plain_files "$IP_BUILD_TMP_DIR/cn.cidr.txt" "${merge_inputs[@]}"',
    "check_asn_source_gates()",
    "${UPSTREAM_SETTINGS[ip.${name}.min_entries]}",
    "slug_of()",
    'ASN_GROUP_SPECS+=(',
    'sync_pure_asn_ip_list "${ASN_GROUP_NAMES[@]}"',
]
for snippet in config_driven_snippets:
    if snippet not in script:
        raise SystemExit(f"test failed: sync-upstream missing config-driven snippet {snippet!r}")

for hardcoded_threshold in ("600000", "380000"):
    if hardcoded_threshold in script:
        raise SystemExit(
            f"test failed: ASN source health threshold {hardcoded_threshold} is hardcoded; "
            "read it from config/upstreams.json instead"
        )

for retired in ("geoip-asn-csv", "asn-csv", "geoip_asn", "GeoLite", "goog-json", "goog-ranges"):
    if retired in script:
        raise SystemExit(f"test failed: retired ASN source reference reintroduced: {retired}")

for hardcoded_source_line in (
    "cn-clang-ipv4 required",
    "cn-clang-ipv6 required",
    "cn-17mon-ipv4 required",
    "gaoyifan-cn-ipv4 required",
    "gaoyifan-cn-ipv6 required",
    "chnroutes-bgp-ipv4 required",
    "cn-clang-ipv4|",
    "gaoyifan-cn-ipv4|",
    "chnroutes-bgp-ipv4|",
):
    if hardcoded_source_line in script:
        raise SystemExit(
            f"test failed: per-source enumeration reintroduced: {hardcoded_source_line!r}; "
            "drive the pipeline from UPSTREAM_SETTINGS instead"
        )

domain_required_snippets = [
    'clone_repository_shallow "${UPSTREAM_SETTINGS[domain.dlc.url]}" "$WORK_TMP_DIR/domain-list-community"',
    'shellcrash-fakeip "${UPSTREAM_SETTINGS[domain.shellcrash-fakeip.url]}" "$WORK_TMP_DIR/shellcrash-fakeip.raw.list"',
    '"$WORK_TMP_DIR/shellcrash-fakeip.raw.list"',
    '"$DOMAIN_RULE_TMP_DIR/fakeip-filter.list"',
    '"$WORK_TMP_DIR/domain-list-community/data"',
    'verify-domain-derivatives.py',
]
for snippet in domain_required_snippets:
    if snippet not in script:
        raise SystemExit(f"test failed: sync-upstream missing domain derivative guard snippet {snippet!r}")

if "apple.cidr.txt" in script or "private.cidr.txt" in script:
    raise SystemExit("test failed: repository-owned IP lists moved back into the sync stage")
if "apple.raw.html" in script or "APPLE_IP_SOURCE_URL" in script:
    raise SystemExit("test failed: Apple IP must not be fetched from a remote page")

for excluded in ("merge-domain-suffixes.py",):
    if excluded in script:
        raise SystemExit(f"test failed: DNS-only China List was reintroduced: {excluded}")

asn_pure_function_match = re.search(
    r"sync_pure_asn_ip_list\(\) \{(?P<body>.*?)\n\}",
    script,
    re.DOTALL,
)
if not asn_pure_function_match:
    raise SystemExit("test failed: sync_pure_asn_ip_list function is missing")
if "merge_cidr_plain_files" not in asn_pure_function_match.group("body"):
    raise SystemExit("test failed: sync_pure_asn_ip_list must merge per-family CIDR outputs")

asn_cidr_function_match = re.search(
    r"extract_asn_group_cidrs\(\) \{(?P<body>.*?)\n\}",
    script,
    re.DOTALL,
)
if not asn_cidr_function_match:
    raise SystemExit("test failed: extract_asn_group_cidrs helper is missing")
asn_body = asn_cidr_function_match.group("body")
if "render_ip_text_artifact" in asn_body:
    raise SystemExit("test failed: private ASN CIDR helper must not render public artifacts")
for snippet in ("iptoasn-tsv-multi", "{name}_asn_${family}.cidr.txt"):
    if snippet not in asn_body:
        raise SystemExit(
            f"test failed: ASN extraction must extract all groups in one pass per snapshot: {snippet!r}"
        )

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
    "normalize_first_batch_source",
    "sync_merged_asn_ip_list",
):
    if removed_helper in script:
        raise SystemExit(f"test failed: redundant helper was reintroduced: {removed_helper}")

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
