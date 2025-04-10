#!/usr/bin/env python3
import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone
from collections import defaultdict

class RuleProcessor:
    TYPE_ORDER = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "IP-CIDR"]
    JSON_MAP = {"DOMAIN":"domain", "DOMAIN-KEYWORD":"domain_keyword",
                "DOMAIN-SUFFIX":"domain_suffix", "IP-CIDR":"ip_cidr"}
    
    def __init__(self, input_file, output_json):
        self.input_file = Path(input_file)
        self.output_json = Path(output_json)
        self.rules = defaultdict(set)

    def _load_content(self):
        with open(self.input_file, encoding="utf-8") as f:
            content = f.read()
        header = re.search(r"^# NAME:.*?(?=\n[^#]|\Z)", content, re.DOTALL)
        return content[len(header.group(0)):].lstrip('\n') if header else content

    def _parse_line(self, line):
        line = line.strip()
        if not line or line.startswith("#"): return
        match = re.match(rf"^({'|'.join(self.TYPE_ORDER)})[,\s]+([^#\s]+)", line, re.I)
        return {"type": match.group(1).upper(), "value": match.group(2).lower()} if match else {"type": "DOMAIN", "value": line.lower()}

    def _filter_rules(self, rules):
        suffixes = {r["value"] for r in rules if r["type"] == "DOMAIN-SUFFIX"}
        return [r for r in rules if not (r["type"] == "DOMAIN" and r["value"] in suffixes)]

    def _generate_header(self, stats):
        return (f"# NAME: Emby\n# AUTHOR: KuGouGo\n# REPO: https://github.com/KuGouGo/Rules\n"
                f"# UPDATED: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}\n"
                + "\n".join(f"# {k}: {v}" for k,v in stats.items() if v)
                + f"\n# TOTAL: {sum(stats.values())}\n\n")

    def process(self):
        rules = [r for r in (self._parse_line(l) for l in self._load_content().splitlines() if r]
        filtered = self._filter_rules(rules)
        
        for r in filtered:
            self.rules[r["type"]].add(r["value"])
        
        sorted_rules = []
        for t in self.TYPE_ORDER:
            sorted_rules.extend(f"{t},{v}" for v in sorted(self.rules.get(t, [])))
        
        with open(self.input_file, "w", encoding="utf-8") as f:
            f.write(self._generate_header({k: len(v) for k,v in self.rules.items()}) 
            f.write("\n".join(sorted_rules))
        
        json_rules = [{self.JSON_MAP[r["type"]]: r["value"]} for r in filtered]
        with open(self.output_json, "w", encoding="utf-8") as f:
            json.dump({"version":3, "rules":json_rules}, f, indent=2)

if __name__ == "__main__":
    input_file = sys.argv[1] if len(sys.argv) > 1 else "emby.list"
    RuleProcessor(input_file, "emby.json").process()
