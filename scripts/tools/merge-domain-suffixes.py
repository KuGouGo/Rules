#!/usr/bin/env python3
"""Merge a plain domain-suffix source into classical rule files in one pass."""
from __future__ import annotations

import argparse
from pathlib import Path

from domain_rules import domain_value_errors, parse_classical_domain_file


_TERMINAL = ""


class SuffixTrie:
    """Reversed-label trie answering 'is any stored suffix a parent of value?'."""

    def __init__(self, values: tuple[str, ...] = ()) -> None:
        self.root: dict[str, dict] = {}
        for value in values:
            self.add(value)

    def covers(self, value: str) -> bool:
        node = self.root
        for label in reversed(value.split(".")):
            if _TERMINAL in node:
                return True
            node = node.get(label)
            if node is None:
                return False
        return _TERMINAL in node

    def add(self, value: str) -> None:
        node = self.root
        for label in reversed(value.split(".")):
            if _TERMINAL in node:
                return
            node = node.setdefault(label, {})
        node.clear()
        node[_TERMINAL] = True


def load_plain(path: Path) -> tuple[list[str], int]:
    values: set[str] = set()
    invalid = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        value = raw.split("#", 1)[0].strip().lower().rstrip(".")
        if not value:
            continue
        if domain_value_errors(
            "DOMAIN-SUFFIX",
            value,
            require_canonical=True,
            allow_single_label_suffix=True,
        ):
            invalid += 1
            continue
        values.add(value)
    return sorted(values, key=lambda item: (item.count("."), item)), invalid


def merge_target(target: Path, candidates: list[str]) -> tuple[int, int]:
    rules, errors = parse_classical_domain_file(
        target,
        require_canonical=True,
        allow_single_label_suffix=True,
    )
    if errors:
        raise ValueError("\n".join(errors))

    trie = SuffixTrie(tuple(rule.value for rule in rules if rule.kind == "DOMAIN-SUFFIX"))
    additions: list[str] = []
    for value in candidates:
        if trie.covers(value):
            continue
        trie.add(value)
        additions.append(value)

    lines = [rule.text for rule in rules]
    lines.extend(f"DOMAIN-SUFFIX,{value}" for value in additions)
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(additions), len(candidates) - len(additions)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plain_source")
    parser.add_argument("targets", nargs="+")
    parser.add_argument("--normalized-output")
    args = parser.parse_args()

    candidates, invalid = load_plain(Path(args.plain_source))
    if args.normalized_output:
        Path(args.normalized_output).write_text(
            "\n".join(f"DOMAIN-SUFFIX,{value}" for value in candidates) + "\n",
            encoding="utf-8",
        )

    print(f"candidate={len(candidates)} invalid={invalid}")
    for name in args.targets:
        added, covered = merge_target(Path(name), candidates)
        print(f"target={name} added={added} covered_or_duplicate={covered}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
