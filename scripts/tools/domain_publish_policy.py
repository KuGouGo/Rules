#!/usr/bin/env python3

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


SCHEMA_VERSION = 5
GEO_CN = "geolocation-cn"
GEO_NOT_CN = "geolocation-!cn"


@dataclass(frozen=True)
class PublishPolicy:
    geographic_roots: frozenset[str]
    geolocation_not_cn: frozenset[str]
    standalone: frozenset[str]
    compatibility_replacements: dict[str, str]


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
        "geographic_roots",
        "geolocation_not_cn",
        "standalone",
        "compatibility_replacements",
    }
    if set(data) != expected:
        raise ValueError(f"{source}: expected exactly {', '.join(sorted(expected))}")
    if data.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(f"{source}: schema_version must be {SCHEMA_VERSION}")

    replacements = data["compatibility_replacements"]
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

    roots = _name_list(source, "geographic_roots", data["geographic_roots"])
    if roots != {GEO_NOT_CN}:
        raise ValueError(
            f"{source}: geographic_roots must be exactly [{GEO_NOT_CN}] "
            "(cn covers geolocation-cn/tld-cn)"
        )

    return PublishPolicy(
        geographic_roots=roots,
        geolocation_not_cn=_name_list(source, "geolocation_not_cn", data["geolocation_not_cn"]),
        standalone=_name_list(source, "standalone", data["standalone"]),
        compatibility_replacements=dict(replacements),
    )


def load_publish_policy(path: Path) -> PublishPolicy:
    return parse_publish_policy(
        json.loads(path.read_text(encoding="utf-8")),
        str(path),
    )
