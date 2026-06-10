#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import re
from pathlib import Path

script = Path("scripts/commands/sync-upstream.sh").read_text(encoding="utf-8")
expected = ["cn", "google", "telegram", "cloudflare", "cloudfront", "aws", "fastly", "github", "apple"]

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

domain_required_snippets = [
    'clone_repository_shallow "$DOMAIN_SOURCE_REPO_URL" "$WORK_TMP_DIR/domain-list-community"',
    '"$WORK_TMP_DIR/domain-list-community/data"',
    'assert_domain_attr_derivatives "$DOMAIN_RULE_MANIFEST_FILE"',
    '"apple@cn"',
    '"apple@ads"',
    '"geolocation-cn@!cn"',
    '"geolocation-!cn@cn"',
    '"alibaba@!cn"',
    '"speedtest@ads"',
    '"missing geolocation -cn/-!cn regional pair"',
]
for snippet in domain_required_snippets:
    if snippet not in script:
        raise SystemExit(f"test failed: sync-upstream missing domain derivative guard snippet {snippet!r}")

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
