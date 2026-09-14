#!/usr/bin/env python3
import argparse
import ipaddress
import sys
from pathlib import Path

IP_RULE_TYPES = {"IP-CIDR", "IP-CIDR6", "IP6-CIDR"}


def check_dir(dir_path: Path, label: str) -> list[str]:
    violations: list[str] = []

    if not dir_path.exists():
        return violations

    for path in sorted(dir_path.glob("*.list")):
        allow_non_global = path.stem == "private"
        for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            parts = [part.strip() for part in line.split(",")]
            kind = parts[0] if parts else ""
            if kind not in IP_RULE_TYPES:
                continue
            if len(parts) < 2 or not parts[1]:
                violations.append(f"{label}/{path.name}:{line_no}: missing CIDR value")
                continue

            try:
                network = ipaddress.ip_network(parts[1], strict=False)
            except ValueError as exc:
                violations.append(f"{label}/{path.name}:{line_no}: invalid CIDR {parts[1]!r} ({exc})")
                continue

            if kind == "IP-CIDR" and network.version != 4:
                violations.append(f"{label}/{path.name}:{line_no}: IP-CIDR requires IPv4, got {network}")
            if kind in {"IP-CIDR6", "IP6-CIDR"} and network.version != 6:
                violations.append(f"{label}/{path.name}:{line_no}: {kind} requires IPv6, got {network}")
            if not allow_non_global and not network.is_global:
                violations.append(f"{label}/{path.name}:{line_no}: non-global CIDR outside private.list: {network}")

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate public IP CIDR artifacts in a directory.")
    parser.add_argument("directory", type=Path)
    parser.add_argument("label")
    args = parser.parse_args()

    violations = check_dir(args.directory, args.label)
    if violations:
        print("IP CIDR validity guard failed:", file=sys.stderr)
        for violation in violations:
            print(violation, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
