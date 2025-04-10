#!/usr/bin/env python3
import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone
from collections import defaultdict
import argparse  # Import the argparse module for command-line arguments

class RuleProcessor:
    TYPE_ORDER = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "IP-CIDR"]
    JSON_MAP = {"DOMAIN": "domain", "DOMAIN-KEYWORD": "domain_keyword",
                "DOMAIN-SUFFIX": "domain_suffix", "IP-CIDR": "ip_cidr"}

    def __init__(self, input_file, output_json):
        """Initializes the RuleProcessor with input and output file paths."""
        self.input_file = Path(input_file)
        self.output_json = Path(output_json)
        self.rules = defaultdict(set)

    def _load_content(self):
        """Loads content from the input file, skipping the header."""
        try:
            with open(self.input_file, encoding="utf-8") as f:
                content = f.read()
            header_match = re.search(r"^# NAME:.*?(?=\n[^#]|\Z)", content, re.DOTALL)
            if header_match:
                return content[len(header_match.group(0)):].lstrip('\n')
            return content
        except FileNotFoundError:
            print(f"Error: Input file '{self.input_file}' not found.")
            sys.exit(1)
        except Exception as e:
            print(f"Error reading input file '{self.input_file}': {e}")
            sys.exit(1)

    def _parse_line(self, line):
        """Parses a single line from the input file into a rule dictionary."""
        line = line.strip()
        if not line or line.startswith("#"):
            return None
        match = re.match(rf"^({'|'.join(self.TYPE_ORDER)})[,\s]+([^#\s]+)", line, re.I)
        if match:
            return {"type": match.group(1).upper(), "value": match.group(2).lower()}
        return {"type": "DOMAIN", "value": line.lower()}

    def _filter_rules(self, rules):
        """Filters out DOMAIN rules that are also present as DOMAIN-SUFFIX rules."""
        suffixes = {r["value"] for r in rules if r["type"] == "DOMAIN-SUFFIX"}
        return [r for r in rules if not (r["type"] == "DOMAIN" and r["value"] in suffixes)]

    def _generate_header(self, stats):
        """Generates the header content for the output file."""
        now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
        header_lines = [
            "# NAME: Emby",
            "# AUTHOR: KuGouGo",
            "# REPO: https://github.com/KuGouGo/Rules",
            f"# UPDATED: {now_utc}",
        ]
        for k, v in stats.items():
            if v:
                header_lines.append(f"# {k}: {v}")
        header_lines.append(f"# TOTAL: {sum(stats.values())}")
        header_lines.append("")
        return "\n".join(header_lines) + "\n"

    def process(self):
        """Processes the rules from the input file, filters them, and writes to output files."""
        content = self._load_content()
        rules = [r for r in (self._parse_line(l) for l in content.splitlines()) if r]
        filtered = self._filter_rules(rules)

        for r in filtered:
            self.rules[r["type"]].add(r["value"])

        sorted_rules = []
        for t in self.TYPE_ORDER:
            if t in self.rules:
                sorted_rules.extend(f"{t},{v}" for v in sorted(self.rules[t]))

        stats = {k: len(v) for k, v in self.rules.items()}
        header = self._generate_header(stats)

        try:
            with open(self.input_file, "w", encoding="utf-8") as f:
                f.write(header)
                f.write("\n".join(sorted_rules))
        except Exception as e:
            print(f"Error writing to input file '{self.input_file}': {e}")

        json_rules = [{self.JSON_MAP[r["type"]]: r["value"]} for r in filtered]
        try:
            with open(self.output_json, "w", encoding="utf-8") as f:
                json.dump({"version": 3, "rules": json_rules}, f, indent=2)
        except Exception as e:
            print(f"Error writing to output JSON file '{self.output_json}': {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Process and filter rule lists.")
    parser.add_argument("input_file", nargs="?", default="emby.list", help="Input file path (default: emby.list)")
    parser.add_argument("output_json", nargs="?", default="emby.json", help="Output JSON file path (default: emby.json)")
    args = parser.parse_args()

    RuleProcessor(args.input_file, args.output_json).process()
