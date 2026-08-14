#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

from domain_rules import (
    GEOGRAPHIC_BASE_EXCLUDED_ATTRS,
    ParsedDomainRule,
    compact_domain_rules,
    domain_rule_is_covered,
    domain_value_errors,
    normalize_domain_value,
    parse_classical_domain_file,
)
from domain_publish_policy import (
    GEO_CN,
    GEO_NOT_CN,
    PublishPolicy,
    load_publish_policy,
)
from platform_capabilities import PlatformCapabilities, load_platform_capabilities


ROOT = Path(__file__).resolve().parents[2]
CAPABILITIES_FILE = ROOT / "config" / "domain-platform-capabilities.json"


RULE_KIND_MAP = {
    "domain": "DOMAIN-SUFFIX",
    "full": "DOMAIN",
    "keyword": "DOMAIN-KEYWORD",
    "regexp": "DOMAIN-REGEX",
}

RULE_KIND_ALIASES = {
    "domain": "domain",
    "domain-suffix": "domain",
    "domain_suffix": "domain",
    "suffix": "domain",
    "full": "full",
    "domain-full": "full",
    "domain_full": "full",
    "keyword": "keyword",
    "domain-keyword": "keyword",
    "domain_keyword": "keyword",
    "regexp": "regexp",
    "regex": "regexp",
    "domain-regex": "regexp",
    "domain_regex": "regexp",
}

REGIONAL_ATTRS = ("!cn", "cn")
# Selected high-traffic categories also ship their own @cn derivative for
# front-loaded direct routing (China-accessible endpoints such as CDNs).
# Kept alongside the geolocation-!cn@cn aggregate; duplicate rules between
# the derivative and the aggregate are harmless under ordered rule matching.
PER_CATEGORY_CN_DERIVATIVES = {"apple", "google", "microsoft", "steam"}
# Only the geolocation-!cn@cn aggregate is shipped as a standalone derivative;
# per-category regional derivatives are folded into the geographic partition.
# The @ads attribute still drives base-list filtering (e.g. cn excludes ad
# entries) but its derivatives are never shipped.
PUBLISHED_ATTRS = REGIONAL_ATTRS
# Ads category lists are collapsed into a single flat aggregate list. The
# plain category-ads* source lists (category-ads, category-ads-ir, ...) are not
# shipped, and the aggregate list is published without regional derivatives.
AGGREGATE_ADS_LIST = "category-ads-all"
ADS_LIST_PREFIX = "category-ads"
ALWAYS_PUBLISHED_DLC_LISTS = {"cn", "private"}
CAPABILITY_SCHEMA: PlatformCapabilities = load_platform_capabilities(CAPABILITIES_FILE)
PLATFORM_CAPABILITIES = CAPABILITY_SCHEMA.platforms
SURGE_KIND_MAP = PLATFORM_CAPABILITIES["surge"].domain.rule_mappings
QUANX_KIND_MAP = PLATFORM_CAPABILITIES["quanx"].domain.rule_mappings
EGERN_KIND_MAP = PLATFORM_CAPABILITIES["egern"].domain.rule_mappings
SINGBOX_KIND_MAP = PLATFORM_CAPABILITIES["sing-box"].domain.rule_mappings
MIHOMO_KIND_MAP = PLATFORM_CAPABILITIES["mihomo"].domain.rule_mappings
SURGE_KIND_SET = set(SURGE_KIND_MAP)
MIHOMO_MRS_KIND_SET = set(MIHOMO_KIND_MAP)


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        raise SystemExit(f"invalid {name} environment value: {value!r}") from None


MIHOMO_MRS_SKIP_WARN_PERCENT = env_int("MIHOMO_MRS_SKIP_WARN_PERCENT", 30)
DEFAULT_SINGBOX_RULE_SET_VERSION = 4
SINGBOX_RULE_SET_VERSION = env_int("SINGBOX_RULE_SET_VERSION", DEFAULT_SINGBOX_RULE_SET_VERSION)


def count_rule_kinds(rules: list[Rule]) -> dict[str, int]:
    counts = {kind: 0 for kind in SINGBOX_KIND_MAP}
    for rule in rules:
        counts[rule.kind] = counts.get(rule.kind, 0) + 1
    return counts


def print_platform_skip_summary(name: str, rules: list[Rule], platform: str | None = None) -> None:
    counts = count_rule_kinds(rules)
    capabilities = (
        {platform: PLATFORM_CAPABILITIES[platform]}
        if platform is not None
        else PLATFORM_CAPABILITIES
    )
    for platform_name, capability in capabilities.items():
        skipped = {
            kind: count
            for kind, count in counts.items()
            if count and kind in capability.domain.unsupported_kinds
        }
        if skipped:
            details = ", ".join(f"{kind}={count}" for kind, count in sorted(skipped.items()))
            print(
                f"domain summary: {name} skips unsupported rules for {platform_name}: {details}",
                file=sys.stderr,
            )


def add_platform_skip_counts(
    totals: dict[str, dict[str, int]],
    affected: dict[str, set[str]],
    name: str,
    rules: list[Rule],
    platforms: tuple[str, ...] | None = None,
) -> None:
    counts = count_rule_kinds(rules)
    for platform_name in platforms or tuple(PLATFORM_CAPABILITIES):
        unsupported = PLATFORM_CAPABILITIES[platform_name].domain.unsupported_kinds
        skipped = {kind: count for kind, count in counts.items() if count and kind in unsupported}
        if not skipped:
            continue
        affected.setdefault(platform_name, set()).add(name)
        platform_totals = totals.setdefault(platform_name, {})
        for kind, count in skipped.items():
            platform_totals[kind] = platform_totals.get(kind, 0) + count


def print_platform_batch_skip_summary(
    totals: dict[str, dict[str, int]], affected: dict[str, set[str]]
) -> None:
    for platform_name in sorted(totals):
        details = ", ".join(
            f"{kind}={count}" for kind, count in sorted(totals[platform_name].items())
        )
        print(
            f"domain batch summary: {platform_name} skips unsupported rules in "
            f"{len(affected[platform_name])} list(s): {details}",
            file=sys.stderr,
        )


def print_mihomo_mrs_skip_summary(input_file: Path, rules: list[Rule]) -> None:
    skipped = {
        kind: count
        for kind, count in count_rule_kinds(rules).items()
        if count and kind not in MIHOMO_MRS_KIND_SET
    }
    if skipped:
        details = ", ".join(f"{kind}={count}" for kind, count in sorted(skipped.items()))
        skipped_total = sum(skipped.values())
        total = len(rules)
        skipped_percent = skipped_total * 100 // total if total else 0
        print(f"mihomo mrs summary: {input_file.name} skips unsupported rules: {details}", file=sys.stderr)
        if skipped_percent > MIHOMO_MRS_SKIP_WARN_PERCENT:
            print(
                f"mihomo mrs warning: {input_file.name} skips {skipped_percent}% unsupported rules "
                f"(threshold {MIHOMO_MRS_SKIP_WARN_PERCENT}%)",
                file=sys.stderr,
            )


@dataclass(frozen=True)
class Rule:
    kind: str
    value: str
    attrs: tuple[str, ...]


@dataclass(frozen=True)
class Include:
    target: str
    filters: tuple[str, ...]


def strip_comment(line: str) -> str:
    return line.split("#", 1)[0].strip()


def parse_rule_token(token: str) -> tuple[str, str]:
    if ":" in token:
        prefix, value = token.split(":", 1)
        kind = RULE_KIND_ALIASES.get(prefix.lower())
        if kind:
            return kind, value
        raise ValueError(f"unsupported rule prefix: {prefix}")
    return "domain", token


def normalize_rule_value(kind: str, value: str) -> str:
    mapped = {
        "domain": "DOMAIN-SUFFIX",
        "full": "DOMAIN",
        "keyword": "DOMAIN-KEYWORD",
    }.get(kind)
    if mapped:
        return normalize_domain_value(mapped, value)
    return value.strip()


def parse_data_file(path: Path) -> tuple[list[Rule], list[Include], list[tuple[str, Rule]]]:
    rules: list[Rule] = []
    includes: list[Include] = []
    affiliations: list[tuple[str, Rule]] = []

    with path.open("r", encoding="utf-8") as fh:
        for line_no, raw_line in enumerate(fh, start=1):
            line = strip_comment(raw_line)
            if not line:
                continue

            head, _, tail_text = line.partition(" ")
            tail_tokens = tail_text.split() if tail_text else []
            attrs: list[str] = []
            affiliate_targets: list[str] = []
            for token in tail_tokens:
                if token.startswith("@") and len(token) > 1:
                    attrs.append(token[1:])
                elif token.startswith("&") and len(token) > 1:
                    affiliate_targets.append(token[1:])
                else:
                    raise ValueError(f"{path}:{line_no} unsupported trailing token: {token}")

            if head.startswith("include:"):
                includes.append(Include(head.split(":", 1)[1], tuple(attrs)))
                continue

            try:
                kind, value = parse_rule_token(head)
            except ValueError as exc:
                raise ValueError(f"{path}:{line_no} {exc}") from exc
            value = normalize_rule_value(kind, value)
            canonical_kind = RULE_KIND_MAP[kind]
            validation_errors = domain_value_errors(
                canonical_kind,
                value,
                require_canonical=False,
                allow_single_label_suffix=True,
            )
            if validation_errors:
                raise ValueError(f"{path}:{line_no} {validation_errors[0]}")
            rule = Rule(kind=canonical_kind, value=value, attrs=tuple(attrs))
            rules.append(rule)

            for target in affiliate_targets:
                # &name is the v2fly affiliation extension: the rule is also added
                # to the list named <name>, enabling cross-list rule sharing without
                # explicit include: directives.
                affiliations.append((target, rule))

    return rules, includes, affiliations


def include_matches(rule: Rule, filters: tuple[str, ...]) -> bool:
    attrs = set(rule.attrs)
    for item in filters:
        if item.startswith("-"):
            if item[1:] in attrs:
                return False
            continue
        if item not in attrs:
            return False
    return True


def render_rule(rule: Rule) -> str:
    return f"{rule.kind},{rule.value}"


def compact_rules(rules: list[Rule]) -> tuple[list[Rule], int]:
    """Drop DOMAIN/DOMAIN-SUFFIX rules covered by a sibling DOMAIN-SUFFIX."""
    first_by_key: dict[tuple[str, str], Rule] = {}
    for rule in rules:
        first_by_key.setdefault((rule.kind, rule.value), rule)
    parsed = [
        ParsedDomainRule(rule.kind, rule.value, index)
        for index, rule in enumerate(rules)
    ]
    compacted, removed = compact_domain_rules(parsed)
    return [first_by_key[(rule.kind, rule.value)] for rule in compacted], removed


@dataclass(frozen=True)
class RuleSetOutput:
    rules: list[Rule]
    rules_by_attr: dict[str, list[Rule]]


def collect_rule_set_output(rules: list[Rule]) -> RuleSetOutput:
    unique_rules: list[Rule] = []
    rules_by_attr: dict[str, list[Rule]] = {}
    seen_rules: set[tuple[str, str]] = set()
    seen_by_attr: dict[str, set[tuple[str, str]]] = {}

    for rule in rules:
        key = (rule.kind, rule.value)
        if key not in seen_rules:
            seen_rules.add(key)
            unique_rules.append(rule)

        for attr in rule.attrs:
            attr_seen = seen_by_attr.setdefault(attr, set())
            if key in attr_seen:
                continue
            attr_seen.add(key)
            rules_by_attr.setdefault(attr, []).append(rule)

    return RuleSetOutput(unique_rules, rules_by_attr)


def filter_base_rule_set(name: str, rules: list[Rule]) -> list[Rule]:
    excluded_attrs = GEOGRAPHIC_BASE_EXCLUDED_ATTRS.get(name)
    if not excluded_attrs:
        return rules
    return [rule for rule in rules if excluded_attrs.isdisjoint(rule.attrs)]


def is_plain_ads_category_list(name: str) -> bool:
    """True for the per-provider ads lists that are collapsed into the aggregate."""
    return name.startswith(ADS_LIST_PREFIX) and name != AGGREGATE_ADS_LIST


def regional_suffix_for_rule_set_name(name: str) -> str | None:
    if name == "cn":
        return "cn"
    for suffix in REGIONAL_ATTRS:
        if name.endswith(f"-{suffix}"):
            return suffix
    return None


def regional_base_for_rule_set_name(name: str) -> str | None:
    suffix = regional_suffix_for_rule_set_name(name)
    if not suffix or name == suffix:
        return None
    return name[: -(len(suffix) + 1)]


def split_attr_rule_set_name(name: str) -> tuple[str, str] | None:
    if name.count("@") != 1:
        return None
    base, separator, attr = name.partition("@")
    if not separator or not base or not attr:
        return None
    return base, attr


def is_redundant_attr_rule_set_name(base: str, attr: str) -> bool:
    return regional_suffix_for_rule_set_name(base) == attr


def classify_rule_set_name(name: str) -> dict[str, str]:
    attr_parts = split_attr_rule_set_name(name)
    if attr_parts:
        base, attr = attr_parts
        base_region_suffix = regional_suffix_for_rule_set_name(base)
        classification = {
            "kind": "attr",
            "base": base,
            "attr": attr,
            "base_kind": "regional" if base_region_suffix else "base",
        }
        if base_region_suffix:
            classification["base_region_suffix"] = base_region_suffix
            base_region_base = regional_base_for_rule_set_name(base)
            if base_region_base:
                classification["base_region_base"] = base_region_base
        return classification
    region_suffix = regional_suffix_for_rule_set_name(name)
    if region_suffix:
        classification = {"kind": "regional", "region_suffix": region_suffix}
        region_base = regional_base_for_rule_set_name(name)
        if region_base:
            classification["region_base"] = region_base
        return classification
    return {"kind": "base"}


def region_pairs_for_rule_set_names(names: set[str]) -> dict[str, list[str]]:
    pairs: dict[str, set[str]] = {}
    for name in names:
        region_suffix = regional_suffix_for_rule_set_name(name)
        region_base = regional_base_for_rule_set_name(name)
        if not region_suffix or not region_base:
            continue
        pairs.setdefault(region_base, set()).add(region_suffix)
    return {base: sorted(suffixes) for base, suffixes in sorted(pairs.items())}


def parse_classical_domain_rules(input_file: Path) -> list[Rule]:
    parsed, errors = parse_classical_domain_file(
        input_file,
        require_canonical=True,
        allow_single_label_suffix=True,
    )
    if errors:
        raise ValueError("\n".join(errors))
    return [Rule(kind=rule.kind, value=rule.value, attrs=tuple()) for rule in parsed]


def parse_plain_yaml_quoted_value(raw_value: str) -> str:
    value = raw_value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return bytes(value[1:-1], "utf-8").decode("unicode_escape")
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    return value


def export_plain_yaml_lists(input_file: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    current_name = ""
    current_rules: list[Rule] = []

    def flush_current() -> None:
        if not current_name or not current_rules:
            return
        print_platform_skip_summary(current_name, current_rules)
        compacted, _ = compact_rules(collect_rule_set_output(current_rules).rules)
        rendered = [render_rule(rule) for rule in compacted]
        (output_dir / f"{current_name}.list").write_text("\n".join(rendered) + "\n", encoding="utf-8")

    for line_no, raw_line in enumerate(input_file.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped == "lists:":
            continue

        if stripped.startswith("- name: "):
            flush_current()
            current_name = parse_plain_yaml_quoted_value(stripped.removeprefix("- name: "))
            if (
                not current_name
                or current_name in {".", ".."}
                or "/" in current_name
                or "\\" in current_name
                or "\x00" in current_name
            ):
                raise ValueError(f"{input_file}:{line_no} invalid list name: {current_name!r}")
            current_rules = []
            continue

        if stripped in {"rules:"} or stripped.startswith("length: "):
            continue

        if stripped.startswith("- "):
            token = parse_plain_yaml_quoted_value(stripped.removeprefix("- "))
            try:
                kind, value = parse_rule_token(token)
            except ValueError as exc:
                raise ValueError(f"{input_file}:{line_no} {exc}") from exc
            value = normalize_rule_value(kind, value)
            if value:
                current_rules.append(Rule(kind=RULE_KIND_MAP[kind], value=value, attrs=tuple()))
            continue

        raise ValueError(f"{input_file}:{line_no} unsupported plain YAML line: {stripped}")

    flush_current()


def write_text_lines(lines: list[str], output_file: Path) -> None:
    if lines:
        output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return
    output_file.write_text("", encoding="utf-8")


def write_text_lines_if_nonempty(lines: list[str], output_file: Path) -> bool:
    if not lines:
        return False
    write_text_lines(lines, output_file)
    return True


def write_normalized_classical_rules(input_file: Path, output_file: Path) -> None:
    write_text_lines([render_rule(rule) for rule in parse_classical_domain_rules(input_file)], output_file)


def build_surge_lines(rules: list[Rule]) -> list[str]:
    return [
        f"{SURGE_KIND_MAP[rule.kind]},{rule.value}"
        for rule in rules
        if rule.kind in SURGE_KIND_SET
    ]


def build_surge_list(input_file: Path, output_file: Path) -> None:
    rules = parse_classical_domain_rules(input_file)
    print_platform_skip_summary(input_file.stem, rules, "surge")
    write_text_lines(build_surge_lines(rules), output_file)


def build_quanx_lines(rules: list[Rule], policy_tag: str) -> list[str]:
    return [
        f"{QUANX_KIND_MAP[rule.kind]},{rule.value},{policy_tag}"
        for rule in rules
        if rule.kind in QUANX_KIND_MAP
    ]


def build_quanx_list(input_file: Path, output_file: Path, policy_tag: str) -> None:
    rules = parse_classical_domain_rules(input_file)
    print_platform_skip_summary(input_file.stem, rules, "quanx")
    write_text_lines(build_quanx_lines(rules, policy_tag), output_file)


def yaml_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def build_egern_yaml_text(rules: list[Rule]) -> str:
    sections: dict[str, list[str]] = {key: [] for key in EGERN_KIND_MAP.values()}
    seen: dict[str, set[str]] = {key: set() for key in EGERN_KIND_MAP.values()}

    for rule in rules:
        target = EGERN_KIND_MAP.get(rule.kind)
        if not target or rule.value in seen[target]:
            continue
        seen[target].add(rule.value)
        sections[target].append(rule.value)

    chunks: list[str] = []
    for key in ("domain_set", "domain_suffix_set", "domain_keyword_set", "domain_regex_set"):
        values = sections[key]
        if not values:
            continue
        lines = [f"{key}:"]
        lines.extend(f"  - {yaml_quote(value)}" for value in values)
        chunks.append("\n".join(lines))

    if chunks:
        return "\n\n".join(chunks) + "\n"
    return ""


def build_egern_yaml(input_file: Path, output_file: Path) -> None:
    output_file.write_text(build_egern_yaml_text(parse_classical_domain_rules(input_file)), encoding="utf-8")


def build_mihomo_lines(input_file: Path, rules: list[Rule], print_summary: bool = True) -> list[str]:
    entries: list[str] = []
    seen: set[str] = set()
    if print_summary:
        print_mihomo_mrs_skip_summary(input_file, rules)

    for rule in rules:
        implementation = MIHOMO_KIND_MAP.get(rule.kind)
        if implementation is None:
            if rule.kind in PLATFORM_CAPABILITIES["mihomo"].domain.unsupported_kinds:
                continue
            raise ValueError(f"unsupported mihomo domain mapping implementation for {rule.kind}")
        if implementation == "plain":
            normalized = rule.value
        elif implementation == "leading-dot":
            normalized = f".{rule.value}"
        else:
            raise ValueError(f"unsupported mihomo domain mapping implementation: {implementation}")

        if normalized in seen:
            continue
        seen.add(normalized)
        entries.append(normalized)

    return entries


def build_mihomo_text(input_file: Path, output_file: Path) -> None:
    rules = parse_classical_domain_rules(input_file)
    write_text_lines(build_mihomo_lines(input_file, rules), output_file)


def reachable_rule_set_names(
    include_rules: dict[str, list[Include]],
    root: str,
) -> set[str]:
    seen: set[str] = set()
    stack = [root]
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        stack.extend(include.target for include in include_rules.get(name, []))
    return seen


def selected_rule_set_names(
    all_names: set[str],
    include_rules: dict[str, list[Include]],
    policy: PublishPolicy | None,
    profile: str | None = None,
) -> set[str]:
    if policy is None:
        return all_names

    selected_profile = profile or policy.default_profile
    if selected_profile not in {"common", "extended"}:
        raise ValueError(f"unsupported publish profile: {selected_profile}")
    common_not_cn = policy.geolocation_not_cn(selected_profile)
    configured_not_cn = policy.geolocation_not_cn("extended")
    geographic_roots = policy.geographic_roots(selected_profile)
    missing_roots = sorted(policy.geographic_roots("extended") - all_names)
    if missing_roots:
        raise ValueError(
            "publish policy geographic roots were removed or renamed upstream: "
            + ", ".join(missing_roots)
        )

    missing = sorted(configured_not_cn - all_names)
    if missing:
        raise ValueError(
            "publish policy geographic lists were removed or renamed upstream: "
            + ", ".join(missing)
        )
    not_cn_reachable = reachable_rule_set_names(include_rules, GEO_NOT_CN)
    invalid = sorted(configured_not_cn - not_cn_reachable)
    if invalid:
        raise ValueError(
            "publish policy geographic lists changed classification and are no longer "
            "reachable from geolocation-!cn: "
            + ", ".join(invalid)
        )

    geographic_children = (
        reachable_rule_set_names(include_rules, GEO_CN)
        | not_cn_reachable
    ) - {GEO_CN, GEO_NOT_CN}
    core = all_names & ALWAYS_PUBLISHED_DLC_LISTS
    standalone = all_names - geographic_children - {GEO_CN, GEO_NOT_CN} - core
    missing_standalone = sorted(policy.common_standalone - all_names)
    moved_not_cn = sorted(policy.common_standalone & not_cn_reachable)
    moved_cn = sorted(
        policy.common_standalone & reachable_rule_set_names(include_rules, GEO_CN)
    )
    if missing_standalone or moved_not_cn or moved_cn:
        details = []
        if missing_standalone:
            details.append("removed/renamed=" + ",".join(missing_standalone))
        if moved_not_cn:
            details.append("now-geolocation-!cn=" + ",".join(moved_not_cn))
        if moved_cn:
            details.append("now-geolocation-cn=" + ",".join(moved_cn))
        raise ValueError(
            "publish policy standalone lists changed upstream classification: "
            + "; ".join(details)
        )
    selected_standalone = standalone if selected_profile == "extended" else set(policy.common_standalone)
    return selected_standalone | common_not_cn | core | geographic_roots


def export_data_dir_lists(
    data_dir: Path,
    output_dir: Path,
    publish_policy: Path | None = None,
    publish_profile: str | None = None,
) -> None:
    direct_rules: dict[str, list[Rule]] = {}
    include_rules: dict[str, list[Include]] = {}
    affiliated_rules: dict[str, list[Rule]] = {}

    for path in sorted(data_dir.iterdir(), key=lambda item: item.name):
        if not path.is_file():
            continue
        rules, includes, affiliations = parse_data_file(path)
        direct_rules[path.name] = rules
        include_rules[path.name] = includes
        for target, rule in affiliations:
            affiliated_rules.setdefault(target, []).append(rule)

    missing_includes = sorted(
        {include.target for includes in include_rules.values() for include in includes}
        - set(direct_rules)
        - set(affiliated_rules)
    )
    if missing_includes:
        raise ValueError("missing included DLC rule sets: " + ", ".join(missing_includes))

    cache: dict[str, list[Rule]] = {}
    visiting: set[str] = set()

    def resolve(name: str) -> list[Rule]:
        if name in cache:
            return cache[name]
        if name in visiting:
            raise RuntimeError(f"cyclic include detected for {name}")

        visiting.add(name)
        combined: list[Rule] = []
        combined.extend(direct_rules.get(name, []))
        combined.extend(affiliated_rules.get(name, []))

        for include in include_rules.get(name, []):
            for rule in resolve(include.target):
                if include_matches(rule, include.filters):
                    combined.append(rule)

        visiting.remove(name)
        cache[name] = combined
        return combined

    # Close the geographic partition with global regional attributes. v2fly
    # marks Chinese entities serving only overseas with @!cn and foreign
    # entities with a mainland access point with @cn; some of these rules are
    # not reachable from the geolocation roots, so they are folded into
    # geolocation-!cn to guarantee proxy/direct coverage for every rule.
    global_cn: dict[tuple[str, str], Rule] = {}
    global_not_cn: dict[tuple[str, str], Rule] = {}
    for rules in list(direct_rules.values()) + list(affiliated_rules.values()):
        for rule in rules:
            if "cn" in rule.attrs:
                global_cn.setdefault((rule.kind, rule.value), rule)
            if "!cn" in rule.attrs:
                global_not_cn.setdefault((rule.kind, rule.value), rule)
    cn_base_keys = {
        (rule.kind, rule.value)
        for rule in filter_base_rule_set("cn", resolve("cn"))
    }
    folded_cn = [
        rule
        for rule in global_cn.values()
        if not domain_rule_is_covered(rule.kind, rule.value, cn_base_keys)
    ]
    folded_not_cn = list(global_not_cn.values())
    geo_cn_base_keys = {
        (rule.kind, rule.value)
        for rule in filter_base_rule_set(GEO_CN, resolve(GEO_CN))
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    all_names = set(direct_rules) | set(affiliated_rules)
    policy = load_publish_policy(publish_policy) if publish_policy else None
    if policy:
        common_selected = selected_rule_set_names(all_names, include_rules, policy, "common")
        extended_selected = selected_rule_set_names(all_names, include_rules, policy, "extended")
        for alias, target in policy.compatibility_replacements.items():
            if alias not in all_names or target not in all_names:
                raise ValueError(
                    f"compatibility replacement references missing DLC list: {alias} -> {target}"
                )
            if alias in common_selected or target not in common_selected or alias not in extended_selected:
                raise ValueError(
                    "compatibility replacement must omit the alias from common, publish its "
                    f"target in common, and restore the alias in extended: {alias} -> {target}"
                )
            target_keys = {
                (rule.kind, rule.value)
                for rule in collect_rule_set_output(resolve(target)).rules
            }
            uncovered = [
                rule
                for rule in collect_rule_set_output(resolve(alias)).rules
                if not domain_rule_is_covered(rule.kind, rule.value, target_keys)
            ]
            if uncovered:
                sample = ", ".join(render_rule(rule) for rule in uncovered[:5])
                raise ValueError(
                    f"compatibility replacement is no longer semantically safe: {alias} -> "
                    f"{target}; uncovered={len(uncovered)} ({sample})"
                )
    selected = selected_rule_set_names(all_names, include_rules, policy, publish_profile)
    names = sorted(selected)
    skip_totals: dict[str, dict[str, int]] = {}
    skip_affected: dict[str, set[str]] = {}

    def write_rule_set(name: str, rules: list[Rule]) -> None:
        if not rules:
            return
        add_platform_skip_counts(skip_totals, skip_affected, name, rules)
        compacted, _ = compact_rules(rules)
        rendered = [render_rule(rule) for rule in compacted]
        (output_dir / f"{name}.list").write_text("\n".join(rendered) + "\n", encoding="utf-8")

    for name in names:
        if is_plain_ads_category_list(name):
            continue
        resolved_rules = resolve(name)
        if name == GEO_NOT_CN:
            resolved_rules = resolved_rules + folded_cn + folded_not_cn
        rule_set_output = collect_rule_set_output(resolved_rules)
        base_rules = filter_base_rule_set(name, resolved_rules)
        if name == GEO_NOT_CN:
            # Exact untagged overlaps can arrive through broad global category
            # includes (currently hsbc -> hsbc-cn). The explicit CN root owns
            # those rules; attributed @cn rules remain available to the @cn
            # derivative through rule_set_output above.
            base_rules = [
                rule
                for rule in base_rules
                if (rule.kind, rule.value) not in geo_cn_base_keys
            ]
        base_output = (
            rule_set_output
            if base_rules is resolved_rules
            else collect_rule_set_output(base_rules)
        )
        write_rule_set(name, base_output.rules)

        if name in PER_CATEGORY_CN_DERIVATIVES:
            cn_rules = [
                rule
                for rule in rule_set_output.rules_by_attr.get("cn", [])
                if not domain_rule_is_covered(rule.kind, rule.value, cn_base_keys)
            ]
            if cn_rules:
                write_rule_set(f"{name}@cn", cn_rules)

        # Per-category regional derivatives are redundant: every @cn rule is
        # covered by the geolocation-!cn@cn aggregate (or the cn base list) and
        # every @!cn rule by the geolocation-!cn base list. Ship only the
        # geolocation-!cn@cn aggregate, kept disjoint from the cn base list so
        # the three geographic sets partition every regional rule exactly once.
        if name == GEO_NOT_CN:
            for attr, rules in sorted(rule_set_output.rules_by_attr.items()):
                if attr in PUBLISHED_ATTRS and not is_redundant_attr_rule_set_name(name, attr):
                    if attr == "cn":
                        rules = [
                            rule
                            for rule in rules
                            if not domain_rule_is_covered(rule.kind, rule.value, cn_base_keys)
                        ]
                    write_rule_set(f"{name}@{attr}", rules)

    print_platform_batch_skip_summary(skip_totals, skip_affected)



def export_lists(
    input_path: Path,
    output_dir: Path,
    publish_policy: Path | None = None,
    publish_profile: str | None = None,
) -> None:
    if input_path.is_dir():
        export_data_dir_lists(input_path, output_dir, publish_policy, publish_profile)
        return
    if publish_policy or publish_profile:
        raise ValueError("publish policy/profile is supported only for DLC data directories")
    export_plain_yaml_lists(input_path, output_dir)


def build_singbox_payload(rules: list[Rule]) -> dict[str, list[str]]:
    payload: dict[str, list[str]] = {}
    unsupported_kinds = PLATFORM_CAPABILITIES["sing-box"].domain.unsupported_kinds

    for rule in rules:
        kind = rule.kind
        if kind in unsupported_kinds:
            continue
        target = SINGBOX_KIND_MAP.get(kind)
        if target is None:
            raise ValueError(f"unsupported sing-box domain mapping for {kind}")
        payload.setdefault(target, []).append(rule.value)

    return payload


def build_singbox_json_text(rules: list[Rule]) -> str:
    data = {"version": SINGBOX_RULE_SET_VERSION, "rules": [build_singbox_payload(rules)]}
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


def build_singbox_json(input_file: Path, output_file: Path) -> None:
    output_file.write_text(
        build_singbox_json_text(parse_classical_domain_rules(input_file)),
        encoding="utf-8",
    )


def sorted_classical_rule_files(rule_dir: Path) -> list[Path]:
    return sorted(rule_dir.glob("*.list"), key=lambda item: item.name)


def domain_rule_manifest(rule_dir: Path) -> dict[str, object]:
    lists: list[dict[str, object]] = []
    by_kind: dict[str, int] = {}
    by_attr: dict[str, int] = {}
    by_region_suffix: dict[str, int] = {}
    input_files = sorted_classical_rule_files(rule_dir)
    names = {input_file.stem for input_file in input_files}
    region_pairs = region_pairs_for_rule_set_names(names)

    for input_file in input_files:
        name = input_file.stem
        rules = parse_classical_domain_rules(input_file)
        entry = {
            "name": name,
            "file": input_file.name,
            "rules": len(rules),
        }
        classification = classify_rule_set_name(name)
        entry.update(classification)
        region_base = classification.get("region_base")
        if isinstance(region_base, str):
            entry["region_siblings"] = region_pairs.get(region_base, [])
        base_region_base = classification.get("base_region_base")
        if isinstance(base_region_base, str):
            entry["base_region_siblings"] = region_pairs.get(base_region_base, [])
        lists.append(entry)

        kind = str(classification["kind"])
        by_kind[kind] = by_kind.get(kind, 0) + 1
        attr = classification.get("attr")
        if isinstance(attr, str):
            by_attr[attr] = by_attr.get(attr, 0) + 1
        region_suffix = classification.get("region_suffix")
        if isinstance(region_suffix, str):
            by_region_suffix[region_suffix] = by_region_suffix.get(region_suffix, 0) + 1

    return {
        "total": len(lists),
        "by_kind": dict(sorted(by_kind.items())),
        "by_attr": dict(sorted(by_attr.items())),
        "by_region_suffix": dict(sorted(by_region_suffix.items())),
        "region_pairs": region_pairs,
        "lists": lists,
    }


def write_domain_rule_manifest(rule_dir: Path, output_file: Path) -> None:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(
        json.dumps(domain_rule_manifest(rule_dir), ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def reset_output_dirs(*dirs: Path) -> None:
    for directory in dirs:
        try:
            if directory.exists():
                shutil.rmtree(directory)
        except OSError as exc:
            raise SystemExit(f"failed to reset output directory {directory}: {exc}") from exc
        directory.mkdir(parents=True, exist_ok=True)


def render_text_platform_dirs(rule_dir: Path, surge_dir: Path, quanx_dir: Path, egern_dir: Path) -> None:
    reset_output_dirs(surge_dir, quanx_dir, egern_dir)

    for input_file in sorted_classical_rule_files(rule_dir):
        base = input_file.stem
        rules = parse_classical_domain_rules(input_file)

        surge_lines = build_surge_lines(rules)
        write_text_lines_if_nonempty(surge_lines, surge_dir / f"{base}.list")

        quanx_lines = build_quanx_lines(rules, base)
        write_text_lines_if_nonempty(quanx_lines, quanx_dir / f"{base}.list")

        egern_text = build_egern_yaml_text(rules)
        if egern_text:
            (egern_dir / f"{base}.yaml").write_text(egern_text, encoding="utf-8")


def build_binary_input_dir(rule_dir: Path, output_dir: Path) -> None:
    reset_output_dirs(output_dir)
    skip_totals: dict[str, dict[str, int]] = {}
    skip_affected: dict[str, set[str]] = {}

    for input_file in sorted_classical_rule_files(rule_dir):
        base = input_file.stem
        rules = parse_classical_domain_rules(input_file)
        (output_dir / f"{base}.json").write_text(
            build_singbox_json_text(rules),
            encoding="utf-8",
        )
        add_platform_skip_counts(skip_totals, skip_affected, base, rules, ("mihomo",))
        write_text_lines(
            build_mihomo_lines(input_file, rules, print_summary=False),
            output_dir / f"{base}.mihomo.txt",
        )
    print_platform_batch_skip_summary(skip_totals, skip_affected)


def trace_cli_invocation(command: str) -> None:
    trace_file = os.environ.get("RULES_TRACE_DOMAIN_CLI_FILE")
    if not trace_file:
        return
    Path(trace_file).parent.mkdir(parents=True, exist_ok=True)
    with Path(trace_file).open("a", encoding="utf-8") as fh:
        fh.write(f"{command}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("data_dir")
    export_parser.add_argument("output_dir")
    export_parser.add_argument("--publish-policy")
    export_parser.add_argument("--publish-profile", choices=("common", "extended"))

    normalize_parser = subparsers.add_parser("normalize-classical")
    normalize_parser.add_argument("input_file")
    normalize_parser.add_argument("output_file")

    surge_parser = subparsers.add_parser("surge-list")
    surge_parser.add_argument("input_file")
    surge_parser.add_argument("output_file")

    quanx_parser = subparsers.add_parser("quanx-list")
    quanx_parser.add_argument("input_file")
    quanx_parser.add_argument("output_file")
    quanx_parser.add_argument("policy_tag")

    egern_parser = subparsers.add_parser("egern-yaml")
    egern_parser.add_argument("input_file")
    egern_parser.add_argument("output_file")

    mihomo_parser = subparsers.add_parser("mihomo-text")
    mihomo_parser.add_argument("input_file")
    mihomo_parser.add_argument("output_file")

    singbox_parser = subparsers.add_parser("singbox-json")
    singbox_parser.add_argument("input_file")
    singbox_parser.add_argument("output_file")

    text_dirs_parser = subparsers.add_parser("text-platform-dirs")
    text_dirs_parser.add_argument("rule_dir")
    text_dirs_parser.add_argument("surge_dir")
    text_dirs_parser.add_argument("quanx_dir")
    text_dirs_parser.add_argument("egern_dir")

    binary_input_parser = subparsers.add_parser("binary-input-dir")
    binary_input_parser.add_argument("rule_dir")
    binary_input_parser.add_argument("output_dir")

    manifest_parser = subparsers.add_parser("domain-rule-manifest")
    manifest_parser.add_argument("rule_dir")
    manifest_parser.add_argument("output_file")

    args = parser.parse_args()
    trace_cli_invocation(args.command)

    handlers = {
        "export": lambda: export_lists(
            Path(args.data_dir),
            Path(args.output_dir),
            Path(args.publish_policy) if args.publish_policy else None,
            args.publish_profile,
        ),
        "normalize-classical": lambda: write_normalized_classical_rules(
            Path(args.input_file), Path(args.output_file)
        ),
        "surge-list": lambda: build_surge_list(Path(args.input_file), Path(args.output_file)),
        "quanx-list": lambda: build_quanx_list(
            Path(args.input_file), Path(args.output_file), args.policy_tag
        ),
        "egern-yaml": lambda: build_egern_yaml(Path(args.input_file), Path(args.output_file)),
        "mihomo-text": lambda: build_mihomo_text(Path(args.input_file), Path(args.output_file)),
        "singbox-json": lambda: build_singbox_json(Path(args.input_file), Path(args.output_file)),
        "text-platform-dirs": lambda: render_text_platform_dirs(
            Path(args.rule_dir), Path(args.surge_dir),
            Path(args.quanx_dir), Path(args.egern_dir),
        ),
        "binary-input-dir": lambda: build_binary_input_dir(
            Path(args.rule_dir), Path(args.output_dir)
        ),
        "domain-rule-manifest": lambda: write_domain_rule_manifest(
            Path(args.rule_dir), Path(args.output_file)
        ),
    }

    handler = handlers.get(args.command)
    if handler is None:
        return 1

    try:
        handler()
        return 0
    except Exception as exc:  # pragma: no cover - surfaced to shell
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
