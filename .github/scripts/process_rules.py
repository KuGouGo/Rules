#!/usr/bin/env python3
# -*- coding: utf-8 -*-
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
            print(f"错误：文件 {RULE_FILE} 不存在")
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
            self.rule_data[rule_type].add(value)
            return {"type": rule_type, "value": value}
        else:
            value = line.strip().lower()
            self.rule_data["DOMAIN"].add(value)
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
            rule_type = rule["type"]
            value = rule["value"]
            if rule_type == "DOMAIN-KEYWORD":
                json_rules.append({"domain_keyword": value})
            elif rule_type == "DOMAIN-SUFFIX":
                json_rules.append({"domain_suffix": value})
            elif rule_type == "DOMAIN":
                json_rules.append({"domain": value})
            elif rule_type in ["PROCESS-NAME", "USER-AGENT", "IP-CIDR"]:
                print(f"警告：JSON 可能需要特殊处理的规则类型: {rule_type}, 值: {value}")
            else:
                print(f"警告：JSON 未处理的规则类型: {rule_type}, 值: {value}")

        output_data = {
            "version": 1,
            "rules": json_rules
        }
        try:
            with open(OUTPUT_JSON_FILE, 'w', encoding='utf-8') as outfile:
                json.dump(output_data, outfile, indent=2)
            print(f"成功生成 {OUTPUT_JSON_FILE}")
        except PermissionError:
            print(f"错误：无权限写入文件 {OUTPUT_JSON_FILE}")
            sys.exit(1)

    def save_file(self, new_content: str):
        try:
            RULE_FILE.write_text(new_content, encoding="utf-8")
        except PermissionError:
            print(f"错误：无权限写入文件 {RULE_FILE}")
            sys.exit(1)

    def process(self):
        content = self.load_content()
        parsed_rules = []

        for line in content.splitlines():
            rule = self.parse_line(line)
            if rule:
                parsed_rules.append(rule)

        sorted_rules_text = self.sort_and_format_rules()
        header_text = self.generate_header()

        new_content = (
            header_text
            + "\n".join(self.comments)
            + ("\n" if self.comments else "")
            + "\n".join(sorted_rules_text)
            + ("\n" + "\n".join(self.other_lines) if self.other_lines else "")
        )
        self.save_file(new_content.strip() + "\n")

        self.generate_json_output(parsed_rules)

if __name__ == "__main__":
    RuleProcessor().process()