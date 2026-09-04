#!/usr/bin/env python3

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


SCHEMA_VERSION = 4
GEO_CN = "geolocation-cn"
GEO_NOT_CN = "geolocation-!cn"


PROFILE_NAMES = ("common", "extended")


@dataclass(frozen=True)
class PublishPolicy:
    default_profile: str
    common_geographic_roots: frozenset[str]
    common_geolocation_not_cn: frozenset[str]
    common_standalone: frozenset[str]
    extended_geographic_roots: frozenset[str]
    extended_geolocation_not_cn: frozenset[str]
    compatibility_replacements: dict[str, str]

    def geographic_roots(self, profile: str) -> set[str]:
        if profile not in PROFILE_NAMES:
            raise ValueError(f"unsupported publish profile: {profile}")
        selected = set(self.common_geographic_roots)
        if profile == "extended":
            selected.update(self.extended_geographic_roots)
        return selected

    def geolocation_not_cn(self, profile: str) -> set[str]:
        if profile not in PROFILE_NAMES:
            raise ValueError(f"unsupported publish profile: {profile}")
        selected = set(self.common_geolocation_not_cn)
        if profile == "extended":
            selected.update(self.extended_geolocation_not_cn)
        return selected

def _name_list(source: str, location: str, value: object) -> frozenset[str]:
    if (
        not isinstance(value, list)
        or any(not isinstance(name, str) or not name for name in value)
        or len(value) != len(set(value))
    ):
        raise ValueError(f"{source}: {location} must be a list of unique non-empty names")
    if value != sorted(value):
        raise ValueError(f"{source}: {location} must be sorted")
    return frozenset(value)


def parse_publish_policy(data: object, source: str = "publish policy") -> PublishPolicy:
    if not isinstance(data, dict):
        raise ValueError(f"{source}: top level must be an object")
    expected = {
        "schema_version",
        "default_profile",
        "common",
        "extended",
        "compatibility_replacements",
    }
    if set(data) != expected:
        raise ValueError(f"{source}: expected exactly {', '.join(sorted(expected))}")
    if data.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(f"{source}: schema_version must be {SCHEMA_VERSION}")
    if data.get("default_profile") not in {"common", "extended"}:
        raise ValueError(f"{source}: default_profile must be common or extended")

    common, extended = data["common"], data["extended"]
    replacements = data["compatibility_replacements"]
    section_keys = {"geographic_roots", "geolocation_not_cn", "standalone"}
    if not isinstance(common, dict) or set(common) != section_keys:
        raise ValueError(f"{source}: common must contain exactly {', '.join(sorted(section_keys))}")
    if not isinstance(extended, dict) or set(extended) != section_keys:
        raise ValueError(f"{source}: extended must contain exactly {', '.join(sorted(section_keys))}")
    if extended["standalone"] != "all":
        raise ValueError(f"{source}: extended.standalone must equal all")
    if not isinstance(replacements, dict) or any(
        not isinstance(name, str)
        or not name
        or not isinstance(target, str)
        or not target
        or name == target
        for name, target in replacements.items()
    ):
        raise ValueError(
            f"{source}: compatibility_replacements must map non-empty distinct names"
        )
    if list(replacements) != sorted(replacements):
        raise ValueError(f"{source}: compatibility_replacements must be sorted")
    chained = set(replacements) & set(replacements.values())
    if chained:
        raise ValueError(
            f"{source}: compatibility replacements must not be chained: "
            + ", ".join(sorted(chained))
        )

    common_roots = _name_list(source, "common.geographic_roots", common["geographic_roots"])
    common_geo = _name_list(source, "common.geolocation_not_cn", common["geolocation_not_cn"])
    common_standalone = _name_list(source, "common.standalone", common["standalone"])
    extended_roots = _name_list(source, "extended.geographic_roots", extended["geographic_roots"])
    extended_geo = _name_list(source, "extended.geolocation_not_cn", extended["geolocation_not_cn"])

    if common_roots != {GEO_NOT_CN} or extended_roots:
        raise ValueError(
            f"{source}: common geographic roots must be {GEO_NOT_CN} and "
            f"extended must not add geographic roots (cn covers geolocation-cn/tld-cn)"
        )
    overlap = common_geo & extended_geo
    if overlap:
        raise ValueError(
            f"{source}: common and extended geographic lists overlap: "
            + ", ".join(sorted(overlap))
        )

    return PublishPolicy(
        default_profile=str(data["default_profile"]),
        common_geographic_roots=common_roots,
        common_geolocation_not_cn=common_geo,
        common_standalone=common_standalone,
        extended_geographic_roots=extended_roots,
        extended_geolocation_not_cn=extended_geo,
        compatibility_replacements=dict(replacements),
    )


def load_publish_policy(path: Path) -> PublishPolicy:
    return parse_publish_policy(
        json.loads(path.read_text(encoding="utf-8")),
        str(path),
    )
