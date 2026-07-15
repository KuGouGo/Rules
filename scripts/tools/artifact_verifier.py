#!/usr/bin/env python3
"""Verify publishable artifacts using capability-selected implementations."""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import subprocess
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any

from domain_rules import domain_value_errors, parse_classical_domain_file
from ip_rules import parse_classical_ip_file
from platform_capabilities import load_platform_capabilities


RuleEntry = tuple[str, str]


def noncomment_lines(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def summarize_entries(entries: Counter[RuleEntry]) -> Counter[str]:
    return Counter({kind: sum(count for (entry_kind, _), count in entries.items() if entry_kind == kind)
                    for kind in sorted({entry_kind for entry_kind, _ in entries})})


def semantic_digest(entries: Counter[RuleEntry]) -> str:
    payload = [[kind, value, count] for (kind, value), count in sorted(entries.items())]
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def canonical_source_entries(
    root: Path,
    kind: str,
    stem: str,
    supported_kinds: set[str],
) -> Counter[RuleEntry] | None:
    source = root / "sources" / "custom" / kind / f"{stem}.list"
    if not source.is_file():
        return None
    result: Counter[RuleEntry] = Counter()
    if kind == "domain":
        rules, errors = parse_classical_domain_file(
            source,
            require_canonical=True,
            allow_single_label_suffix=True,
        )
    else:
        rules, errors = parse_classical_ip_file(source, require_canonical=True)
    if errors:
        raise ValueError(f"canonical custom source is invalid: {'; '.join(errors)}")
    for rule in rules:
        if rule.kind in supported_kinds:
            result[(rule.kind, rule.value)] += 1
    return result


def singbox_entries(data: dict[str, Any], kind: str) -> Counter[RuleEntry]:
    mappings = {
        "domain": {"domain": "DOMAIN", "domain_suffix": "DOMAIN-SUFFIX", "domain_keyword": "DOMAIN-KEYWORD", "domain_regex": "DOMAIN-REGEX"},
        "ip": {"ip_cidr": "IP-CIDR"},
    }[kind]
    entries: Counter[RuleEntry] = Counter()
    allowed_fields = set(mappings)
    for index, rule in enumerate(data.get("rules", []), 1):
        if not isinstance(rule, dict):
            raise ValueError(f"sing-box decompile returned non-object rule #{index}")
        unknown_fields = set(rule) - allowed_fields
        if unknown_fields:
            raise ValueError(
                f"sing-box decompile rule #{index} contains unsupported fields: {sorted(unknown_fields)}"
            )
        matched_field = False
        for field, canonical in mappings.items():
            raw_values = rule.get(field)
            if raw_values is None:
                continue
            matched_field = True
            values = raw_values if isinstance(raw_values, list) else [raw_values]
            if not values or any(not isinstance(value, str) for value in values):
                raise ValueError(f"sing-box decompile returned invalid {field} values")
            if kind == "ip" and field == "ip_cidr":
                for value in values:
                    try:
                        network = ipaddress.ip_network(value, strict=False)
                    except ValueError as exc:
                        raise ValueError(f"sing-box decompile returned invalid CIDR {value!r}: {exc}") from exc
                    entries[("IP-CIDR6" if network.version == 6 else "IP-CIDR", str(network))] += 1
            else:
                for value in values:
                    entries[(canonical, value)] += 1
        if not matched_field:
            raise ValueError(f"sing-box decompile rule #{index} contains no {kind} values")
    return entries


def singbox_counts(data: dict[str, Any], kind: str) -> Counter[str]:
    return summarize_entries(singbox_entries(data, kind))


def verify_singbox(path: Path, kind: str, tool: Path) -> tuple[str, Counter[RuleEntry]]:
    with tempfile.TemporaryDirectory() as temporary:
        decoded = Path(temporary) / "decoded.json"
        subprocess.run([str(tool), "rule-set", "decompile", str(path), "--output", str(decoded)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        data = json.loads(decoded.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        raise ValueError("sing-box decompile did not produce a rule-set object")
    return "sing-box-rule-set-decompile", singbox_entries(data, kind)


def verify_mihomo(path: Path, kind: str, tool: Path) -> tuple[str, Counter[RuleEntry]]:
    behavior = "domain" if kind == "domain" else "ipcidr"
    with tempfile.TemporaryDirectory() as temporary:
        decoded = Path(temporary) / "decoded.txt"
        subprocess.run([str(tool), "convert-ruleset", behavior, "mrs", str(path), str(decoded)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        values = noncomment_lines(decoded)
    if not values:
        raise ValueError("mihomo MRS readback produced no rules")
    entries: Counter[RuleEntry] = Counter()
    if kind == "domain":
        for value in values:
            if value.startswith("+."):
                entries[("DOMAIN-SUFFIX", value[2:])] += 1
            elif value.startswith("."):
                entries[("DOMAIN-SUFFIX", value[1:])] += 1
            else:
                entries[("DOMAIN", value)] += 1
    else:
        for value in values:
            try:
                network = ipaddress.ip_network(value, strict=False)
            except ValueError as exc:
                raise ValueError(f"mihomo MRS readback returned invalid CIDR {value!r}: {exc}") from exc
            entries[("IP-CIDR6" if network.version == 6 else "IP-CIDR", str(network))] += 1
    return "mihomo-convert-ruleset-mrs-to-text", entries


def verify_classical(path: Path, capability: Any, platform: str, artifact_type: str) -> Counter[RuleEntry]:
    lines = noncomment_lines(path)
    if not lines:
        raise ValueError("text artifact contains no rules")
    targets = {target: kind for kind, target in capability.rule_mappings.items()}
    entries: Counter[RuleEntry] = Counter()
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
        if platform == "quanx" and fields[2] != path.stem:
            raise ValueError(f"line {line_number} policy must match artifact name {path.stem!r}")
        canonical_kind = targets[target]
        value = fields[1]
        if artifact_type == "domain":
            errors = domain_value_errors(
                canonical_kind,
                value,
                require_canonical=True,
                allow_single_label_suffix=True,
            )
            if errors:
                raise ValueError(f"line {line_number} {errors[0]}")
        else:
            try:
                network = ipaddress.ip_network(value, strict=False)
            except ValueError as exc:
                raise ValueError(f"line {line_number} has invalid CIDR {value!r}: {exc}") from exc
            value = str(network)
            expected_kind = "IP-CIDR6" if network.version == 6 else "IP-CIDR"
            if canonical_kind != expected_kind or fields[1] != value:
                raise ValueError(f"line {line_number} has non-canonical CIDR kind or value")
        entries[(canonical_kind, value)] += 1
    return entries


def parse_egern_yaml(path: Path, capability: Any, artifact_type: str) -> Counter[RuleEntry]:
    allowed = {target: kind for kind, target in capability.rule_mappings.items()}
    entries: Counter[RuleEntry] = Counter()
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
            canonical_kind = allowed[current]
            if artifact_type == "domain":
                errors = domain_value_errors(
                    canonical_kind,
                    value,
                    require_canonical=True,
                    allow_single_label_suffix=True,
                )
                if errors:
                    raise ValueError(f"line {line_number} {errors[0]}")
            else:
                try:
                    network = ipaddress.ip_network(value, strict=False)
                except ValueError as exc:
                    raise ValueError(f"line {line_number} has invalid CIDR {value!r}: {exc}") from exc
                value = str(network)
                expected_kind = "IP-CIDR6" if network.version == 6 else "IP-CIDR"
                if canonical_kind != expected_kind or quoted.replace("''", "'") != value:
                    raise ValueError(f"line {line_number} has non-canonical CIDR kind or value")
            entries[(canonical_kind, value)] += 1
            continue
        raise ValueError(f"line {line_number} has unsupported YAML indentation or structure")
    if not entries:
        raise ValueError("Egern YAML artifact contains no rules")
    if artifact_type == "ip" and "no_resolve" not in seen:
        raise ValueError("Egern IP YAML must declare no_resolve: true")
    return entries


def canonical_binary_entries(
    root: Path,
    path: Path,
    artifact_type: str,
    platform: str,
    capabilities: Any,
) -> tuple[Counter[RuleEntry] | None, str | None]:
    target = getattr(capabilities.platforms[platform], artifact_type)
    supported_kinds = set(target.rule_mappings)
    custom = canonical_source_entries(root, artifact_type, path.stem, supported_kinds)
    if custom is not None:
        return custom, f"sources/custom/{artifact_type}/{path.stem}.list"

    artifact_root = path.parents[2]
    reference_platform = "surge"
    if artifact_type == "domain" and platform == "sing-box":
        reference_platform = "egern"
    reference_capability = getattr(capabilities.platforms[reference_platform], artifact_type)
    reference = artifact_root / artifact_type / reference_platform / f"{path.stem}.{reference_capability.extension}"
    if not reference.is_file():
        return None, None
    if reference_capability.verifier.startswith("classical-"):
        entries = verify_classical(reference, reference_capability, reference_platform, artifact_type)
    elif reference_capability.verifier == "egern-yaml":
        entries = parse_egern_yaml(reference, reference_capability, artifact_type)
    else:
        raise ValueError(f"unsupported canonical reference verifier: {reference_capability.verifier}")
    filtered = Counter({entry: count for entry, count in entries.items() if entry[0] in supported_kinds})
    return filtered, reference.relative_to(artifact_root).as_posix()


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
    canonical: Counter[RuleEntry] | None = None
    canonical_source: str | None = None
    if verifier in {"sing-box", "mihomo"}:
        canonical, canonical_source = canonical_binary_entries(
            root,
            path,
            artifact_type,
            platform,
            capabilities,
        )
        if canonical is None or canonical_source is None:
            raise ValueError("binary artifact has no canonical custom source or same-build text counterpart")
    linkage: dict[str, Any] = {"status": "unavailable", "reason": "canonical binary compiler input is not retained or not applicable"}
    if canonical is not None:
        if decoded != canonical:
            raise ValueError(
                "decoded rule values differ from canonical source: "
                f"decoded_sha256={semantic_digest(decoded)}, canonical_sha256={semantic_digest(canonical)}"
            )
        linkage = {
            "status": "matched",
            "source": canonical_source,
            "counts": dict(sorted(summarize_entries(canonical).items())),
            "semantic_sha256": semantic_digest(canonical),
        }
    decoded_counts = summarize_entries(decoded)
    return {
        "status": "verified",
        "method": method,
        "decoded_counts": dict(sorted(decoded_counts.items())),
        "decoded_count": sum(decoded_counts.values()),
        "decoded_semantic_sha256": semantic_digest(decoded),
        "canonical_linkage": linkage,
    }


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
