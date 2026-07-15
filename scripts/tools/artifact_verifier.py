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


def normalized_semantic_entries(entries: Counter[RuleEntry]) -> Counter[RuleEntry]:
    kinds = {kind for kind, _ in entries}
    if kinds and kinds <= {"IP-CIDR", "IP-CIDR6"}:
        result: Counter[RuleEntry] = Counter()
        for version in (4, 6):
            networks = [
                ipaddress.ip_network(value)
                for (kind, value) in entries
                if (kind == "IP-CIDR6") == (version == 6)
            ]
            for network in ipaddress.collapse_addresses(networks):
                kind = "IP-CIDR6" if network.version == 6 else "IP-CIDR"
                result[(kind, str(network))] = 1
        return result

    suffixes = {value for (kind, value) in entries if kind == "DOMAIN-SUFFIX"}

    def has_suffix_ancestor(value: str, candidates: set[str]) -> bool:
        while "." in value:
            value = value.split(".", 1)[1]
            if value in candidates:
                return True
        return False

    def covered_by_suffix(value: str, candidates: set[str]) -> bool:
        return value in candidates or has_suffix_ancestor(value, candidates)

    minimal_suffixes = {
        suffix
        for suffix in suffixes
        if not has_suffix_ancestor(suffix, suffixes)
    }
    result = Counter({("DOMAIN-SUFFIX", suffix): 1 for suffix in minimal_suffixes})
    for (kind, value), count in entries.items():
        if kind == "DOMAIN-SUFFIX":
            continue
        if kind == "DOMAIN" and covered_by_suffix(value, minimal_suffixes):
            continue
        result[(kind, value)] = 1 if count else 0
    return +result


def semantic_digest(entries: Counter[RuleEntry]) -> str:
    normalized = normalized_semantic_entries(entries)
    payload = [[kind, value, count] for (kind, value), count in sorted(normalized.items())]
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def canonical_file_entries(path: Path, kind: str) -> Counter[RuleEntry]:
    if not path.is_file():
        raise ValueError(f"canonical rule source is missing: {path}")
    result: Counter[RuleEntry] = Counter()
    if kind == "domain":
        rules, errors = parse_classical_domain_file(
            path,
            require_canonical=True,
            allow_single_label_suffix=True,
        )
    else:
        rules, errors = parse_classical_ip_file(path, require_canonical=True)
    if errors:
        raise ValueError(f"canonical rule source is invalid: {'; '.join(errors)}")
    for rule in rules:
        result[(rule.kind, rule.value)] += 1
    if not result:
        raise ValueError(f"canonical rule source is empty: {path}")
    return result


def canonical_source_entries(root: Path, kind: str, stem: str) -> Counter[RuleEntry] | None:
    source = root / "sources" / "custom" / kind / f"{stem}.list"
    if not source.is_file():
        return None
    return canonical_file_entries(source, kind)


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


def artifact_root_for(path: Path, artifact_type: str, platform: str) -> Path:
    if path.parent.name != platform or path.parent.parent.name != artifact_type:
        raise ValueError(
            f"artifact path is outside the expected {artifact_type}/{platform} layout: {path}"
        )
    return path.parent.parent.parent


def canonical_artifact_entries(
    root: Path,
    path: Path,
    artifact_type: str,
    platform: str,
    capabilities: Any,
) -> tuple[Counter[RuleEntry], str]:
    target = getattr(capabilities.platforms[platform], artifact_type)
    supported_kinds = set(target.rule_mappings)
    artifact_root = artifact_root_for(path, artifact_type, platform)
    canonical_path = artifact_root / ".canonical" / artifact_type / f"{path.stem}.list"
    canonical = canonical_file_entries(canonical_path, artifact_type)

    custom = canonical_source_entries(root, artifact_type, path.stem)
    if custom is not None and normalized_semantic_entries(custom) != normalized_semantic_entries(canonical):
        raise ValueError(
            "internal canonical rules differ from custom source: "
            f"canonical_sha256={semantic_digest(canonical)}, custom_sha256={semantic_digest(custom)}"
        )

    filtered = Counter(
        {entry: count for entry, count in canonical.items() if entry[0] in supported_kinds}
    )
    if not filtered:
        raise ValueError(
            f"artifact exists although canonical rules contain no kinds supported by {platform}"
        )
    return filtered, canonical_path.relative_to(artifact_root).as_posix()


def write_canonical_entries(path: Path, artifact_type: str, entries: Counter[RuleEntry]) -> None:
    kind_order = {
        "domain": ("DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX"),
        "ip": ("IP-CIDR", "IP-CIDR6"),
    }[artifact_type]
    order = {kind: index for index, kind in enumerate(kind_order)}
    lines: list[str] = []
    for (kind, value), count in sorted(entries.items(), key=lambda item: (order[item[0][0]], item[0][1])):
        if count != 1:
            raise ValueError(f"canonical seed contains duplicate rule: {kind},{value}")
        lines.append(f"{kind},{value}")
    if not lines:
        raise ValueError(f"refusing to write empty canonical rule source: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def seed_canonical_from_egern(root: Path, artifact_root: Path, output: Path) -> None:
    capabilities = load_platform_capabilities(root / "config" / "domain-platform-capabilities.json")
    if output.exists():
        raise ValueError(f"canonical seed output already exists: {output}")
    seeded = 0
    for artifact_type in ("domain", "ip"):
        capability = getattr(capabilities.platforms["egern"], artifact_type)
        source_dir = artifact_root / artifact_type / "egern"
        if not source_dir.is_dir():
            continue
        for path in sorted(source_dir.glob(f"*.{capability.extension}")):
            entries = parse_egern_yaml(path, capability, artifact_type)
            write_canonical_entries(output / artifact_type / f"{path.stem}.list", artifact_type, entries)
            seeded += 1
    if seeded == 0:
        raise ValueError(f"no Egern artifacts are available to seed canonical audit rules: {artifact_root}")


def verify_canonical_inventory(root: Path, artifact_root: Path) -> None:
    capabilities = load_platform_capabilities(root / "config" / "domain-platform-capabilities.json")
    errors: list[str] = []
    for artifact_type in ("domain", "ip"):
        canonical_dir = artifact_root / ".canonical" / artifact_type
        if not canonical_dir.is_dir():
            errors.append(f"canonical {artifact_type} directory is missing: {canonical_dir}")
            continue
        canonical_paths = sorted(canonical_dir.glob("*.list"))
        if not canonical_paths:
            errors.append(f"canonical {artifact_type} directory is empty: {canonical_dir}")
            continue
        unexpected_canonical = sorted(
            path.relative_to(canonical_dir).as_posix()
            for path in canonical_dir.rglob("*")
            if path.is_file() and (path.parent != canonical_dir or path.suffix != ".list")
        )
        if unexpected_canonical:
            errors.extend(
                f"unexpected canonical audit file: {artifact_type}/{relative}"
                for relative in unexpected_canonical
            )

        canonical: dict[str, Counter[RuleEntry]] = {}
        for path in canonical_paths:
            try:
                canonical[path.stem] = canonical_file_entries(path, artifact_type)
            except ValueError as exc:
                errors.append(str(exc))

        for platform, details in capabilities.platforms.items():
            capability = getattr(details, artifact_type)
            supported_kinds = set(capability.rule_mappings)
            platform_dir = artifact_root / artifact_type / platform
            for stem, entries in canonical.items():
                supported = Counter(
                    {entry: count for entry, count in entries.items() if entry[0] in supported_kinds}
                )
                expected = bool(normalized_semantic_entries(supported))
                artifact = platform_dir / f"{stem}.{capability.extension}"
                if expected and not artifact.is_file():
                    errors.append(
                        f"canonical counterpart missing: {artifact_type}/{platform}/{artifact.name}"
                    )
                elif not expected and artifact.exists():
                    errors.append(
                        f"unsupported-only canonical rules must not publish: "
                        f"{artifact_type}/{platform}/{artifact.name}"
                    )

            if platform_dir.is_dir():
                for artifact in sorted(platform_dir.glob(f"*.{capability.extension}")):
                    if artifact.stem not in canonical:
                        errors.append(
                            f"artifact has no canonical audit source: "
                            f"{artifact_type}/{platform}/{artifact.name}"
                        )
    if errors:
        raise ValueError("canonical artifact inventory failed: " + "; ".join(errors))


def verify_one(
    root: Path,
    path: Path,
    artifact_type: str,
    platform: str,
    *,
    require_canonical_linkage: bool = True,
) -> dict[str, Any]:
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
    if require_canonical_linkage:
        canonical, canonical_source = canonical_artifact_entries(
            root,
            path,
            artifact_type,
            platform,
            capabilities,
        )
    linkage: dict[str, Any] = {
        "status": "unavailable",
        "reason": "syntax-only verification does not require canonical linkage",
    }
    if canonical is not None:
        if normalized_semantic_entries(decoded) != normalized_semantic_entries(canonical):
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
    parser.add_argument("--path", type=Path)
    parser.add_argument("--type", choices=("domain", "ip"))
    parser.add_argument("--platform")
    parser.add_argument("--syntax-only", action="store_true")
    parser.add_argument("--seed-canonical-from", type=Path)
    parser.add_argument("--canonical-output", type=Path)
    parser.add_argument("--verify-canonical-inventory", type=Path)
    args = parser.parse_args()
    try:
        if args.verify_canonical_inventory is not None:
            if any(
                value is not None
                for value in (
                    args.path,
                    args.type,
                    args.platform,
                    args.seed_canonical_from,
                    args.canonical_output,
                )
            ) or args.syntax_only:
                parser.error("canonical inventory verification cannot be combined with other operations")
            verify_canonical_inventory(args.root.resolve(), args.verify_canonical_inventory.resolve())
            return
        if args.seed_canonical_from is not None or args.canonical_output is not None:
            if args.seed_canonical_from is None or args.canonical_output is None:
                parser.error("--seed-canonical-from and --canonical-output must be used together")
            if args.path is not None or args.type is not None or args.platform is not None or args.syntax_only:
                parser.error("canonical seeding cannot be combined with artifact verification options")
            seed_canonical_from_egern(
                args.root.resolve(),
                args.seed_canonical_from.resolve(),
                args.canonical_output.resolve(),
            )
            return
        if args.path is None or args.type is None or args.platform is None:
            parser.error("--path, --type, and --platform are required for artifact verification")
        result = verify_one(
            args.root.resolve(),
            args.path.resolve(),
            args.type,
            args.platform,
            require_canonical_linkage=not args.syntax_only,
        )
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        operation = args.path or args.seed_canonical_from or args.verify_canonical_inventory
        raise SystemExit(f"artifact verification failed for {operation}: {exc}")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
