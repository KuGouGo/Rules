import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone
from collections import defaultdict
import argparse

class RuleProcessor:
    TYPE_ORDER = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "IP-CIDR"]
    JSON_MAP = {"DOMAIN": "domain", "DOMAIN-KEYWORD": "domain_keyword",
                "DOMAIN-SUFFIX": "domain_suffix", "IP-CIDR": "ip_cidr"}

    def __init__(self, input_file, output_json):
        self.input_file = Path(input_file)
        self.output_json = Path(output_json)
        self.rules = defaultdict(set)

    def _load_content(self):
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
        line = line.strip()
        if not line or line.startswith("#"):
            return None

        type_pattern = rf"^({'|'.join(self.TYPE_ORDER)})[,\s]+([^#\s]+)"
        match = re.match(type_pattern, line, re.I)
        if match:
            return {"type": match.group(1).upper(), "value": match.group(2).lower()}

        if re.match(r"^[a-zA-Z0-9.-]+$", line):
             return {"type": "DOMAIN", "value": line.lower()}

        return None

    def _filter_redundant_suffixes(self, suffixes):
        if not suffixes:
            return set()

        sorted_suffixes = sorted(list(suffixes), key=len)
        redundant = set()

        for i, s1 in enumerate(sorted_suffixes):
            if s1 in redundant:
                continue
            for j in range(i + 1, len(sorted_suffixes)):
                s2 = sorted_suffixes[j]
                if s2.endswith('.' + s1):
                    redundant.add(s2)

        return suffixes - redundant

    def _generate_header(self, stats):
        now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
        header_lines = [
            "# NAME: Emby",
            "# AUTHOR: KuGouGo",
            "# REPO: https://github.com/KuGouGo/Rules",
            f"# UPDATED: {now_utc}",
        ]
        total = 0
        all_present_types = set(stats.keys())
        types_in_order = self.TYPE_ORDER + [t for t in all_present_types if t not in self.TYPE_ORDER]

        for rule_type in types_in_order:
             count = stats.get(rule_type, 0)
             if count > 0:
                 header_lines.append(f"# {rule_type}: {count}")
                 total += count

        header_lines.append(f"# TOTAL: {total}")
        header_lines.append("")
        return "\n".join(header_lines) + "\n"

    def process(self):
        content = self._load_content()

        parsed_rules_list = []
        for line in content.splitlines():
            parsed = self._parse_line(line)
            if parsed:
                parsed_rules_list.append(parsed)

        self.rules = defaultdict(set)
        for r in parsed_rules_list:
            self.rules[r["type"]].add(r["value"])

        if "DOMAIN-SUFFIX" in self.rules:
            original_suffix_count = len(self.rules["DOMAIN-SUFFIX"])
            filtered_suffixes = self._filter_redundant_suffixes(self.rules["DOMAIN-SUFFIX"])
            removed_count = original_suffix_count - len(filtered_suffixes)
            if removed_count > 0:
                print(f"Filtered {removed_count} redundant DOMAIN-SUFFIX rule(s).")
            self.rules["DOMAIN-SUFFIX"] = filtered_suffixes

        sorted_rules_list_output = []
        stats = defaultdict(int)
        all_types_present = set(self.rules.keys())
        type_processing_order = self.TYPE_ORDER + [t for t in all_types_present if t not in self.TYPE_ORDER]

        for t in type_processing_order:
            if t in self.rules and self.rules[t]:
                sorted_values = sorted(list(self.rules[t]))
                stats[t] = len(sorted_values)
                sorted_rules_list_output.extend(f"{t},{v}" for v in sorted_values)

        header = self._generate_header(stats)

        try:
            with open(self.input_file, "w", encoding="utf-8") as f:
                f.write(header)
                f.write("\n".join(sorted_rules_list_output))
                f.write("\n")
        except Exception as e:
            print(f"Error writing to input file '{self.input_file}': {e}")
            sys.exit(1)

        output_json_rules_list = []
        rule_entry = {}
        has_rules_in_entry = False
        for rule_type_internal, json_key in self.JSON_MAP.items():
            if rule_type_internal in self.rules and self.rules[rule_type_internal]:
                sorted_values = sorted(list(self.rules[rule_type_internal]))
                rule_entry[json_key] = sorted_values
                has_rules_in_entry = True

        if has_rules_in_entry:
             output_json_rules_list.append(rule_entry)

        json_data = {"version": 3, "rules": output_json_rules_list}

        try:
            with open(self.output_json, "w", encoding="utf-8") as f:
                json.dump(json_data, f, indent=2)
        except Exception as e:
            print(f"Error writing to output JSON file '{self.output_json}': {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Process rule list, filter redundant DOMAIN-SUFFIX, generate sing-box JSON."
    )
    parser.add_argument(
        "input_file",
        nargs="?",
        default="emby.list",
        help="Input rule list file (default: emby.list)"
    )
    parser.add_argument(
        "output_json",
        nargs="?",
        default="emby.json",
        help="Output JSON file for sing-box (default: emby.json)"
    )
    args = parser.parse_args()

    RuleProcessor(args.input_file, args.output_json).process()
