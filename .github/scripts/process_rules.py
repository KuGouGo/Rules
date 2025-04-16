import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone
from collections import defaultdict
import argparse
from typing import Dict, Set, List, Optional, Tuple

class RuleProcessor:
    TYPE_ORDER: List[str] = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "IP-CIDR"]
    JSON_MAP: Dict[str, str] = {
        "DOMAIN": "domain",
        "DOMAIN-KEYWORD": "domain_keyword",
        "DOMAIN-SUFFIX": "domain_suffix",
        "IP-CIDR": "ip_cidr"
    }
    HEADER_REGEX = re.compile(r"^# NAME:.*?(?=\n[^#]|\Z)", re.DOTALL | re.MULTILINE)
    RULE_TYPE_REGEX = re.compile(rf"^({'|'.join(TYPE_ORDER)})[,\s]+([^#\s]+)", re.I)
    DOMAIN_ONLY_REGEX = re.compile(r"^[a-zA-Z0-9.-]+$")

    def __init__(self, input_file: Path, output_list_file: Path, output_json_file: Path):
        self.input_file = input_file
        self.output_list_file = output_list_file
        self.output_json_file = output_json_file
        self.rules_data: Dict[str, Set[str]] = defaultdict(set)
        self.sorted_rules: Dict[str, List[str]] = {}
        self.stats: Dict[str, int] = defaultdict(int)

    def _load_content(self) -> Optional[str]:
        try:
            print(f"Reading input file: {self.input_file}", file=sys.stderr)
            content = self.input_file.read_text(encoding="utf-8")
            header_match = self.HEADER_REGEX.search(content)
            if header_match:
                return content[len(header_match.group(0)):].lstrip('\n')
            return content
        except FileNotFoundError:
            print(f"Error: Input file '{self.input_file}' not found.", file=sys.stderr)
            return None
        except Exception as e:
            print(f"Error reading input file '{self.input_file}': {e}", file=sys.stderr)
            return None

    def _parse_line(self, line: str) -> Optional[Tuple[str, str]]:
        line = line.strip()
        if not line or line.startswith("#"):
            return None

        match = self.RULE_TYPE_REGEX.match(line)
        if match:
            rule_type = match.group(1).upper()
            value = match.group(2).lower()
            if value: return rule_type, value
            else: return None

        if self.DOMAIN_ONLY_REGEX.match(line):
             return "DOMAIN", line.lower()

        return None

    def _filter_redundant_suffixes(self, suffixes: Set[str]) -> Set[str]:
        if not suffixes: return set()
        sorted_suffixes = sorted(list(suffixes), key=lambda s: (len(s), s))
        filtered_suffixes = set(sorted_suffixes)
        redundant = set()
        for i, s1 in enumerate(sorted_suffixes):
            if s1 in redundant: continue
            for j in range(i + 1, len(sorted_suffixes)):
                s2 = sorted_suffixes[j]
                if s2.endswith('.' + s1):
                    redundant.add(s2)
        return filtered_suffixes - redundant

    def _generate_header(self) -> str:
        now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
        header_lines = [
            "# NAME: Emby",
            "# AUTHOR: KuGouGo",
            "# REPO: https://github.com/KuGouGo/Rules",
            f"# UPDATED: {now_utc}",
        ]
        total_rules = 0
        all_present_types = set(self.stats.keys())
        types_in_order = self.TYPE_ORDER + sorted([t for t in all_present_types if t not in self.TYPE_ORDER])
        for rule_type in types_in_order:
             count = self.stats.get(rule_type, 0)
             if count > 0:
                 header_lines.append(f"# {rule_type}: {count}")
                 total_rules += count
        header_lines.append(f"# TOTAL: {total_rules}")
        header_lines.append("\n")
        return "\n".join(header_lines)

    def _write_list_output(self, header: str) -> bool:
        try:
            print(f"Writing processed list to: {self.output_list_file}", file=sys.stderr)
            with self.output_list_file.open("w", encoding="utf-8") as f:
                f.write(header)
                all_present_types = set(self.sorted_rules.keys())
                types_in_order = self.TYPE_ORDER + sorted([t for t in all_present_types if t not in self.TYPE_ORDER])
                for rule_type in types_in_order:
                    if rule_type in self.sorted_rules:
                        for value in self.sorted_rules[rule_type]:
                            f.write(f"{rule_type},{value}\n")
            return True
        except Exception as e:
            print(f"Error writing list output file '{self.output_list_file}': {e}", file=sys.stderr)
            return False

    def _write_json_output(self) -> bool:
        output_json_rules_list = []
        rule_entry: Dict[str, List[str]] = {}
        has_rules_in_entry = False
        for rule_type_internal, json_key in self.JSON_MAP.items():
            if rule_type_internal in self.sorted_rules:
                rule_entry[json_key] = self.sorted_rules[rule_type_internal]
                has_rules_in_entry = True

        if has_rules_in_entry:
             output_json_rules_list.append(rule_entry)

        json_data = {"version": 3, "rules": output_json_rules_list}

        try:
            print(f"Writing JSON output to: {self.output_json_file}", file=sys.stderr)
            with self.output_json_file.open("w", encoding="utf-8") as f:
                json.dump(json_data, f, indent=2)
                f.write("\n")
            return True
        except Exception as e:
            print(f"Error writing JSON output file '{self.output_json_file}': {e}", file=sys.stderr)
            return False

    def process(self) -> bool:
        content = self._load_content()
        if content is None: return False

        for line in content.splitlines():
            parsed = self._parse_line(line)
            if parsed:
                rule_type, value = parsed
                self.rules_data[rule_type].add(value)

        if "DOMAIN-SUFFIX" in self.rules_data:
            original_count = len(self.rules_data["DOMAIN-SUFFIX"])
            filtered_suffixes = self._filter_redundant_suffixes(self.rules_data["DOMAIN-SUFFIX"])
            removed_count = original_count - len(filtered_suffixes)
            if removed_count > 0:
                print(f"Filtered {removed_count} redundant DOMAIN-SUFFIX rule(s).", file=sys.stderr)
            self.rules_data["DOMAIN-SUFFIX"] = filtered_suffixes

        all_types_present = set(self.rules_data.keys())
        type_processing_order = self.TYPE_ORDER + sorted([t for t in all_types_present if t not in self.TYPE_ORDER])
        for t in type_processing_order:
            if t in self.rules_data and self.rules_data[t]:
                sorted_values = sorted(list(self.rules_data[t]))
                self.sorted_rules[t] = sorted_values
                self.stats[t] = len(sorted_values)

        header = self._generate_header()
        list_success = self._write_list_output(header)
        json_success = self._write_json_output()
        return list_success and json_success

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Process rule list for Sing-box.")
    parser.add_argument("input_file", type=Path, help="Input rule list file.")
    parser.add_argument("-ol", "--output-list", dest="output_list_file", type=Path, required=True, help="Output file for the processed list rules.")
    parser.add_argument("-oj", "--output-json", dest="output_json_file", type=Path, required=True, help="Output JSON file for sing-box.")
    args = parser.parse_args()

    processor = RuleProcessor(
        input_file=args.input_file,
        output_list_file=args.output_list_file,
        output_json_file=args.output_json_file
    )

    success = processor.process()

    if success:
        print("Processing completed successfully.", file=sys.stderr)
        sys.exit(0)
    else:
        print("Processing failed.", file=sys.stderr)
        sys.exit(1)
