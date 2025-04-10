#!/usr/bin/env python3
import re
import sys
import datetime
from pathlib import Path
from collections import defaultdict
import json

RULE_FILE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("emby.list")
OUTPUT_JSON_FILE = Path("emby.json")
TYPE_ORDER = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "PROCESS-NAME", "USER-AGENT", "IP-CIDR"]
RULE_PATTERN = re.compile(
    r"^(?P<type>" + "|".join(TYPE_ORDER) + r")"
    r"[,\s]+"
    r"(?P<value>[^#\s]+)"
    r"(?:\s*#\s*(?P<comment>.*))?$",
    re.IGNORECASE
)

class RuleProcessor:
    def __init__(self):
        self.rule_data = defaultdict(set)
        self.comments = []
        self.other_lines = []

    def load_content(self):
        try:
            content = RULE_FILE.read_text(encoding="utf-8")
        except FileNotFoundError:
            print(f"Error: File {RULE_FILE} does not exist")
            sys.exit(1)

        header_match = re.search(r"^# NAME:.*?(?=\n[^#]|\Z)", content, re.DOTALL)
        self.header = header_match.group(0) if header_match else ""
        return content[len(self.header):].lstrip('\n')

    def parse_line(self, line: str):
        line = line.strip()
        if not line:
            return None
        if line.startswith("#"):
            self.comments.append(line)
            return None

        if match := RULE_PATTERN.match(line):
            rule_type = match.group("type").upper()
            value = match.group("value").lower().strip()
            return {"type": rule_type, "value": value}
        else:
            value = line.strip().lower()
            return {"type": "DOMAIN", "value": value}

    def generate_header(self) -> str:
        stats = {k: len(v) for k, v in self.rule_data.items()}
        return (
            f"# NAME: Emby\n"
            f"# AUTHOR: KuGouGo\n"
            f"# REPO: https://github.com/KuGouGo/Rules\n"
            f"# UPDATED: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            + "\n".join(f"# {k}: {v}" for k, v in stats.items() if v > 0)
            + f"\n# TOTAL: {sum(stats.values())}\n\n"
        )

    def sort_and_format_rules(self) -> list:
        sorted_rules = []
        for rule_type in TYPE_ORDER:
            if values := self.rule_data.get(rule_type):
                sorted_values = sorted(values)
                sorted_rules.extend(f"{rule_type},{v}" for v in sorted_values)
        return sorted_rules

    def generate_json_output(self, rules: list):
        json_rules = []
        for rule in rules:
            rule_type = rule["type"].lower().replace('-', '_')
            value = rule["value"]
            json_rules.append({rule_type: value})
            if rule_type not in ["domain", "domain_keyword", "domain_suffix", "ip_cidr", "process_name", "user_agent"]:
                print(f"Warning: JSON not handling rule type: {rule_type}, value: {value}")

        output_data = {
            "version": 3,
            "rules": json_rules
        }

        try:
            with open(OUTPUT_JSON_FILE, 'w', encoding='utf-8') as outfile:
                json.dump(output_data, outfile, indent=2)
            print(f"Successfully generated {OUTPUT_JSON_FILE}")
        except PermissionError:
            print(f"Error: Permission denied to write file {OUTPUT_JSON_FILE}")
            sys.exit(1)

    def save_file(self, new_content: str):
        try:
            RULE_FILE.write_text(new_content, encoding="utf-8")
        except PermissionError:
            print(f"Error: Permission denied to write file {RULE_FILE}")
            sys.exit(1)

    def process(self):
        content = self.load_content()
        parsed_rules = []

        for line in content.splitlines():
            rule = self.parse_line(line)
            if rule:
                parsed_rules.append(rule)

        domain_suffix_rules = {rule['value'] for rule in parsed_rules if rule['type'] == 'DOMAIN-SUFFIX'}
        final_unique_rules = []

        for rule in parsed_rules:
            if rule['type'] == 'DOMAIN-SUFFIX':
                final_unique_rules.append(rule)
            elif rule['type'] == 'DOMAIN':
                if rule['value'] not in domain_suffix_rules:
                    final_unique_rules.append(rule)
            elif rule['type'] in TYPE_ORDER and rule['type'] not in ['DOMAIN', 'DOMAIN-SUFFIX']:
                final_unique_rules.append(rule)

        parsed_rules = final_unique_rules

        self.rule_data.clear()
        for rule in parsed_rules:
            self.rule_data[rule['type']].add(rule['value'])

        sorted_rules_text = self.sort_and_format_rules()
        header_text = self.generate_header()

        new_content = (
            header_text
            + "\n".join(sorted_rules_text)
            + ("\n" + "\n".join(self.other_lines) if self.other_lines else "")
        )
        self.save_file(new_content.strip() + "\n")

        self.generate_json_output(parsed_rules)

if __name__ == "__main__":
    RuleProcessor().process()
