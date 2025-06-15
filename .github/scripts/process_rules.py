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

    def __init__(self, source_dir: Path, output_base_dir: Path):
        self.source_dir = source_dir
        self.output_base_dir = output_base_dir

    def _load_content(self, file_path: Path) -> Optional[str]:
        try:
            print(f"Reading: {file_path}", file=sys.stderr)
            content = file_path.read_text(encoding="utf-8")
            header_match = self.HEADER_REGEX.search(content)
            if header_match:
                return content[len(header_match.group(0)):].lstrip('\n')
            return content
        except Exception as e:
            print(f"Error reading {file_path}: {e}", file=sys.stderr)
            return None

    def _parse_line(self, line: str) -> Optional[Tuple[str, str]]:
        line = line.strip()
        if not line or line.startswith("#"):
            return None

        match = self.RULE_TYPE_REGEX.match(line)
        if match:
            rule_type = match.group(1).upper()
            value = match.group(2).lower()
            return (rule_type, value) if value else None

        if self.DOMAIN_ONLY_REGEX.match(line):
            return "DOMAIN", line.lower()

        return None

    def _filter_redundant_suffixes(self, suffixes: Set[str]) -> Set[str]:
        if not suffixes:
            return set()
        
        sorted_suffixes = sorted(suffixes, key=lambda s: (len(s), s))
        filtered = set(sorted_suffixes)
        redundant = set()
        
        for i, s1 in enumerate(sorted_suffixes):
            if s1 in redundant:
                continue
            for s2 in sorted_suffixes[i + 1:]:
                if s2.endswith('.' + s1):
                    redundant.add(s2)
        
        return filtered - redundant

    def _generate_header(self, name: str, stats: Dict[str, int]) -> str:
        now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
        header_lines = [
            f"# NAME: {name}",
            "# AUTHOR: KuGouGo", 
            "# REPO: https://github.com/KuGouGo/Rules",
            f"# UPDATED: {now_utc}",
        ]
        
        total_rules = 0
        for rule_type in self.TYPE_ORDER:
            count = stats.get(rule_type, 0)
            if count > 0:
                header_lines.append(f"# {rule_type}: {count}")
                total_rules += count
        
        header_lines.extend([f"# TOTAL: {total_rules}", ""])
        return "\n".join(header_lines)

    def _write_list_file(self, output_file: Path, header: str, sorted_rules: Dict[str, List[str]]) -> bool:
        try:
            print(f"Writing list: {output_file}", file=sys.stderr)
            with output_file.open("w", encoding="utf-8") as f:
                f.write(header)
                for rule_type in self.TYPE_ORDER:
                    if rule_type in sorted_rules:
                        for value in sorted_rules[rule_type]:
                            f.write(f"{rule_type},{value}\n")
            return True
        except Exception as e:
            print(f"Error writing {output_file}: {e}", file=sys.stderr)
            return False

    def _write_json_file(self, output_file: Path, sorted_rules: Dict[str, List[str]]) -> bool:
        rule_entry = {}
        for rule_type, json_key in self.JSON_MAP.items():
            if rule_type in sorted_rules:
                rule_entry[json_key] = sorted_rules[rule_type]

        if not rule_entry:
            return True

        json_data = {"version": 3, "rules": [rule_entry]}

        try:
            print(f"Writing JSON: {output_file}", file=sys.stderr)
            with output_file.open("w", encoding="utf-8") as f:
                json.dump(json_data, f, indent=2, ensure_ascii=False)
                f.write("\n")
            return True
        except Exception as e:
            print(f"Error writing {output_file}: {e}", file=sys.stderr)
            return False

    def _process_single_file(self, input_file: Path) -> Optional[Dict[str, any]]:
        content = self._load_content(input_file)
        if content is None:
            return None

        rules_data: Dict[str, Set[str]] = defaultdict(set)
        
        for line in content.splitlines():
            parsed = self._parse_line(line)
            if parsed:
                rule_type, value = parsed
                rules_data[rule_type].add(value)

        if "DOMAIN-SUFFIX" in rules_data:
            original_count = len(rules_data["DOMAIN-SUFFIX"])
            filtered_suffixes = self._filter_redundant_suffixes(rules_data["DOMAIN-SUFFIX"])
            removed_count = original_count - len(filtered_suffixes)
            if removed_count > 0:
                print(f"Filtered {removed_count} redundant DOMAIN-SUFFIX rules in {input_file.name}", file=sys.stderr)
            rules_data["DOMAIN-SUFFIX"] = filtered_suffixes

        sorted_rules = {}
        stats = {}
        
        for rule_type in self.TYPE_ORDER:
            if rule_type in rules_data and rules_data[rule_type]:
                sorted_values = sorted(rules_data[rule_type])
                sorted_rules[rule_type] = sorted_values
                stats[rule_type] = len(sorted_values)

        return {
            'name': input_file.stem,
            'sorted_rules': sorted_rules,
            'stats': stats
        }

    def process_all_files(self) -> List[str]:
        list_files = list(self.source_dir.glob("*.list"))
        
        if not list_files:
            print("No .list files found", file=sys.stderr)
            return []

        print(f"Found {len(list_files)} .list files", file=sys.stderr)
        processed_dirs = []

        for list_file in sorted(list_files):
            result = self._process_single_file(list_file)
            if not result:
                continue

            name = result['name']
            sorted_rules = result['sorted_rules']
            stats = result['stats']

            if not sorted_rules:
                print(f"No rules found in {list_file.name}", file=sys.stderr)
                continue

            rule_dir = self.output_base_dir / name
            rule_dir.mkdir(parents=True, exist_ok=True)

            header = self._generate_header(name.title(), stats)
            
            list_output = rule_dir / f"{name}.list"
            json_output = rule_dir / f"{name}.json"

            list_success = self._write_list_file(list_output, header, sorted_rules)
            json_success = self._write_json_file(json_output, sorted_rules)

            if list_success and json_success:
                processed_dirs.append(name)
                total_rules = sum(stats.values())
                print(f"Processed: {name}/ ({total_rules} rules)", file=sys.stderr)

        return processed_dirs

def main():
    parser = argparse.ArgumentParser(description="Process rule files into organized directories")
    parser.add_argument("source_dir", type=Path, help="Source directory containing .list files")
    parser.add_argument("--output-dir", type=Path, default=Path("."), help="Base output directory (default: current directory)")
    args = parser.parse_args()

    if not args.source_dir.exists():
        print(f"Source directory {args.source_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    processor = RuleProcessor(args.source_dir, args.output_dir)
    processed_dirs = processor.process_all_files()

    if processed_dirs:
        print(f"Successfully processed {len(processed_dirs)} rule sets: {', '.join(processed_dirs)}", file=sys.stderr)
        print("Created directories:", file=sys.stderr)
        for dir_name in processed_dirs:
            rule_dir = args.output_dir / dir_name
            print(f"  {dir_name}/", file=sys.stderr)
            for file in sorted(rule_dir.glob(f"{dir_name}.*")):
                print(f"    ├── {file.name}", file=sys.stderr)
        sys.exit(0)
    else:
        print("No files were processed successfully", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
