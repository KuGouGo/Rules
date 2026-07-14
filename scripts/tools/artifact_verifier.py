#!/usr/bin/env python3
"""Verify publishable artifacts using capability-selected implementations."""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any

from platform_capabilities import load_platform_capabilities


def noncomment_lines(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def canonical_counts(root: Path, kind: str, stem: str, platform: str) -> Counter[str] | None:
    source = root / "sources" / "custom" / kind / f"{stem}.list"
    if not source.is_file():
        return None
    result: Counter[str] = Counter()
    if kind == "domain":
        for line in noncomment_lines(source):
            parts = [part.strip() for part in line.split(",")]
            if len(parts) >= 2:
                rule_kind = parts[0]
                if platform != "mihomo" or rule_kind in {"DOMAIN", "DOMAIN-SUFFIX"}:
                    result[rule_kind] += 1
    else:
        for line in noncomment_lines(source):
            value = line.split(",", 2)
            if value[0] in {"IP-CIDR", "IP-CIDR6"} and len(value) > 1:
                result[value[0]] += 1
    return result


def singbox_counts(data: dict[str, Any], kind: str) -> Counter[str]:
    mappings = {
        "domain": {"domain": "DOMAIN", "domain_suffix": "DOMAIN-SUFFIX", "domain_keyword": "DOMAIN-KEYWORD", "domain_regex": "DOMAIN-REGEX"},
        "ip": {"ip_cidr": "IP-CIDR"},
    }[kind]
    counts: Counter[str] = Counter()
    for rule in data.get("rules", []):
        if not isinstance(rule, dict):
            continue
        for field, canonical in mappings.items():
            values = rule.get(field, [])
            if isinstance(values, list) and values:
                if kind == "ip" and field == "ip_cidr":
                    for value in values:
                        counts["IP-CIDR6" if ":" in value else "IP-CIDR"] += 1
                else:
                    counts[canonical] += len(values)
    return counts


def verify_singbox(path: Path, kind: str, tool: Path) -> tuple[str, Counter[str]]:
    with tempfile.TemporaryDirectory() as temporary:
        decoded = Path(temporary) / "decoded.json"
        subprocess.run([str(tool), "rule-set", "decompile", str(path), "--output", str(decoded)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        data = json.loads(decoded.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        raise ValueError("sing-box decompile did not produce a rule-set object")
    return "sing-box-rule-set-decompile", singbox_counts(data, kind)


def verify_mihomo(path: Path, kind: str, tool: Path) -> tuple[str, Counter[str]]:
    behavior = "domain" if kind == "domain" else "ipcidr"
    with tempfile.TemporaryDirectory() as temporary:
        decoded = Path(temporary) / "decoded.txt"
        subprocess.run([str(tool), "convert-ruleset", behavior, "mrs", str(path), str(decoded)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        values = noncomment_lines(decoded)
    if not values:
        raise ValueError("mihomo MRS readback produced no rules")
    counts: Counter[str] = Counter()
    if kind == "domain":
        for value in values:
            counts["DOMAIN-SUFFIX" if value.startswith("+.") or value.startswith(".") else "DOMAIN"] += 1
    else:
        for value in values:
            counts["IP-CIDR6" if ":" in value else "IP-CIDR"] += 1
    return "mihomo-convert-ruleset-mrs-to-text", counts


def verify_classical(path: Path, capability: Any, platform: str, artifact_type: str) -> Counter[str]:
    lines = noncomment_lines(path)
    if not lines:
        raise ValueError("text artifact contains no rules")
    targets = {target: kind for kind, target in capability.rule_mappings.items()}
    counts: Counter[str] = Counter()
    for line_number, line in enumerate(lines, 1):
        fields = [field.strip() for field in line.split(",")]
        if any(not field for field in fields):
            raise ValueError(f"line {line_number} contains an empty field")
        target = fields[0]
        if target not in targets:
            raise ValueError(f"line {line_number} has unknown rule kind {target!r}")
        expected_fields = 3 if platform == "quanx" or (platform == "surge" and artifact_type == "ip") else 2
        if len(fields) != expected_fields:
            raise ValueError(f"line {line_number} has {len(fields)} fields; expected {expected_fields}")
        if platform == "surge" and artifact_type == "ip" and fields[2] != "no-resolve":
            raise ValueError(f"line {line_number} must end with no-resolve")
        counts[targets[target]] += 1
    return counts


def parse_egern_yaml(path: Path, capability: Any, artifact_type: str) -> Counter[str]:
    allowed = {target: kind for kind, target in capability.rule_mappings.items()}
    counts: Counter[str] = Counter()
    current: str | None = None
    seen: set[str] = set()
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if not raw.startswith((" ", "\t")):
            if ":" not in raw or raw.count(":") != 1:
                raise ValueError(f"line {line_number} is not a supported YAML key")
            key, value = (part.strip() for part in raw.split(":", 1))
            if key == "no_resolve" and artifact_type == "ip":
                if value != "true" or key in seen:
                    raise ValueError(f"line {line_number} must declare no_resolve: true once")
                seen.add(key); current = None
                continue
            if key not in allowed or value:
                raise ValueError(f"line {line_number} has unknown or non-sequence field {key!r}")
            if key in seen:
                raise ValueError(f"line {line_number} duplicates field {key!r}")
            seen.add(key); current = key
            continue
        if raw.startswith("  - ") and current:
            value = raw[4:].strip()
            if len(value) < 2 or value[0] != "'" or value[-1] != "'":
                raise ValueError(f"line {line_number} must be a single-quoted sequence scalar")
            quoted = value[1:-1]
            if "'" in quoted.replace("''", ""):
                raise ValueError(f"line {line_number} contains an invalid single-quoted scalar")
            value = quoted.replace("''", "'")
            if not value:
                raise ValueError(f"line {line_number} contains an empty value")
            counts[allowed[current]] += 1
            continue
        raise ValueError(f"line {line_number} has unsupported YAML indentation or structure")
    if not counts:
        raise ValueError("Egern YAML artifact contains no rules")
    if artifact_type == "ip" and "no_resolve" not in seen:
        raise ValueError("Egern IP YAML must declare no_resolve: true")
    return counts


def verify_one(root: Path, path: Path, artifact_type: str, platform: str) -> dict[str, Any]:
    capabilities = load_platform_capabilities(root / "config" / "domain-platform-capabilities.json")
    capability = getattr(capabilities.platforms[platform], artifact_type)
    verifier = capability.verifier
    if verifier == "sing-box":
        method, decoded = verify_singbox(path, artifact_type, root / ".bin" / "sing-box")
    elif verifier == "mihomo":
        method, decoded = verify_mihomo(path, artifact_type, root / ".bin" / "mihomo")
    elif verifier.startswith("classical-"):
        method, decoded = verifier, verify_classical(path, capability, platform, artifact_type)
    elif verifier == "egern-yaml":
        method, decoded = verifier, parse_egern_yaml(path, capability, artifact_type)
    else:
        raise ValueError(f"unsupported verifier implementation: {verifier}")
    canonical = canonical_counts(root, artifact_type, path.stem, platform) if verifier in {"sing-box", "mihomo"} else None
    linkage: dict[str, Any] = {"status": "unavailable", "reason": "canonical binary compiler input is not retained or not applicable"}
    if canonical is not None:
        if decoded != canonical:
            raise ValueError(f"decoded rule counts differ from canonical custom source: decoded={dict(decoded)}, canonical={dict(canonical)}")
        linkage = {"status": "matched", "source": f"sources/custom/{artifact_type}/{path.stem}.list", "counts": dict(sorted(canonical.items()))}
    return {"status": "verified", "method": method, "decoded_counts": dict(sorted(decoded.items())),
            "decoded_count": sum(decoded.values()), "canonical_linkage": linkage}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--path", type=Path, required=True)
    parser.add_argument("--type", choices=("domain", "ip"), required=True)
    parser.add_argument("--platform", required=True)
    args = parser.parse_args()
    try:
        result = verify_one(args.root.resolve(), args.path.resolve(), args.type, args.platform)
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f"artifact verification failed for {args.path}: {exc}")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
