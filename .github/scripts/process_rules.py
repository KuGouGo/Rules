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

    def __init__(self, input_dir: Path, output_dir: Path = None):
        self.input_dir = input_dir
        self.output_dir = output_dir or input_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def _load_content(self, file_path: Path) -> Optional[str]:
        try:
            print(f"Reading input file: {file_path}", file=sys.stderr)
            content = file_path.read_text(encoding="utf-8")
            header_match = self.HEADER_REGEX.search(content)
            if header_match:
                return content[len(header_match.group(0)):].lstrip('\n')
            return content
        except FileNotFoundError:
            print(f"Error: Input file '{file_path}' not found.", file=sys.stderr)
            return None
        except Exception as e:
            print(f"Error reading input file '{file_path}': {e}", file=sys.stderr)
            return None

    def _parse_line(self, line: str) -> Optional[Tuple[str, str]]:
        line = line.strip()
        if not line or line.startswith("#"):
            return None

        match = self.RULE_TYPE_REGEX.match(line)
        if match:
            rule_type = match.group(1).upper()
            value = match.group(2).lower()
            if value:
                return rule_type, value
            else:
                return None

        if self.DOMAIN_ONLY_REGEX.match(line):
            return "DOMAIN", line.lower()

        return None

    def _filter_redundant_suffixes(self, suffixes: Set[str]) -> Set[str]:
        if not suffixes:
            return set()
        sorted_suffixes = sorted(list(suffixes), key=lambda s: (len(s), s))
        filtered_suffixes = set(sorted_suffixes)
        redundant = set()
        for i, s1 in enumerate(sorted_suffixes):
            if s1 in redundant:
                continue
            for j in range(i + 1, len(sorted_suffixes)):
                s2 = sorted_suffixes[j]
                if s2.endswith('.' + s1):
                    redundant.add(s2)
        return filtered_suffixes - redundant

    def _generate_header(self, name: str, stats: Dict[str, int]) -> str:
        now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
        header_lines = [
            f"# NAME: {name}",
            "# AUTHOR: KuGouGo",
            "# REPO: https://github.com/KuGouGo/Rules",
            f"# UPDATED: {now_utc}",
        ]
        total_rules = 0
        all_present_types = set(stats.keys())
        types_in_order = self.TYPE_ORDER + sorted([t for t in all_present_types if t not in self.TYPE_ORDER])
        for rule_type in types_in_order:
            count = stats.get(rule_type, 0)
            if count > 0:
                header_lines.append(f"# {rule_type}: {count}")
                total_rules += count
        header_lines.append(f"# TOTAL: {total_rules}")
        header_lines.append("\n")
        return "\n".join(header_lines)

    def _write_list_output(self, output_file: Path, header: str, sorted_rules: Dict[str, List[str]]) -> bool:
        try:
            print(f"Writing processed list to: {output_file}", file=sys.stderr)
            with output_file.open("w", encoding="utf-8") as f:
                f.write(header)
                all_present_types = set(sorted_rules.keys())
                types_in_order = self.TYPE_ORDER + sorted([t for t in all_present_types if t not in self.TYPE_ORDER])
                for rule_type in types_in_order:
                    if rule_type in sorted_rules:
                        for value in sorted_rules[rule_type]:
                            f.write(f"{rule_type},{value}\n")
            return True
        except Exception as e:
            print(f"Error writing list output file '{output_file}': {e}", file=sys.stderr)
            return False

    def _write_json_output(self, output_file: Path, sorted_rules: Dict[str, List[str]]) -> bool:
        output_json_rules_list = []
        rule_entry: Dict[str, List[str]] = {}
        has_rules_in_entry = False
        for rule_type_internal, json_key in self.JSON_MAP.items():
            if rule_type_internal in sorted_rules:
                rule_entry[json_key] = sorted_rules[rule_type_internal]
                has_rules_in_entry = True

        if has_rules_in_entry:
            output_json_rules_list.append(rule_entry)

        json_data = {"version": 3, "rules": output_json_rules_list}

        try:
            print(f"Writing JSON output to: {output_file}", file=sys.stderr)
            with output_file.open("w", encoding="utf-8") as f:
                json.dump(json_data, f, indent=2)
                f.write("\n")
            return True
        except Exception as e:
            print(f"Error writing JSON output file '{output_file}': {e}", file=sys.stderr)
            return False

    def _process_single_file(self, input_file: Path) -> bool:
        content = self._load_content(input_file)
        if content is None:
            return False

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
                print(f"Filtered {removed_count} redundant DOMAIN-SUFFIX rule(s) in {input_file.name}.", file=sys.stderr)
            rules_data["DOMAIN-SUFFIX"] = filtered_suffixes

        sorted_rules: Dict[str, List[str]] = {}
        stats: Dict[str, int] = defaultdict(int)
        
        all_types_present = set(rules_data.keys())
        type_processing_order = self.TYPE_ORDER + sorted([t for t in all_types_present if t not in self.TYPE_ORDER])
        for t in type_processing_order:
            if t in rules_data and rules_data[t]:
                sorted_values = sorted(list(rules_data[t]))
                sorted_rules[t] = sorted_values
                stats[t] = len(sorted_values)

        base_name = input_file.stem
        header = self._generate_header(base_name.title(), stats)
        
        output_list_file = self.output_dir / f"{base_name}.list"
        output_json_file = self.output_dir / f"{base_name}.json"

        list_success = self._write_list_output(output_list_file, header, sorted_rules)
        json_success = self._write_json_output(output_json_file, sorted_rules)
        
        return list_success and json_success

    def process_all_list_files(self) -> bool:
        list_files = list(self.input_dir.glob("*.list"))
        
        if not list_files:
            print("No .list files found in input directory.", file=sys.stderr)
            return False

        success_count = 0
        total_count = len(list_files)
        
        print(f"Found {total_count} .list file(s) to process.", file=sys.stderr)
        
        for list_file in list_files:
            print(f"Processing: {list_file.name}", file=sys.stderr)
            if self._process_single_file(list_file):
                success_count += 1
                print(f"Successfully processed: {list_file.name}", file=sys.stderr)
            else:
                print(f"Failed to process: {list_file.name}", file=sys.stderr)

        print(f"Processing completed: {success_count}/{total_count} files processed successfully.", file=sys.stderr)
        return success_count == total_count

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Process all .list rule files for Sing-box.")
    parser.add_argument("input_dir", type=Path, help="Input directory containing .list files.")
    parser.add_argument("-o", "--output-dir", dest="output_dir", type=Path, help="Output directory for processed files (default: same as input).")
    args = parser.parse_args()

    if not args.input_dir.exists() or not args.input_dir.is_dir():
        print(f"Error: Input directory '{args.input_dir}' does not exist or is not a directory.", file=sys.stderr)
        sys.exit(1)

    processor = RuleProcessor(
        input_dir=args.input_dir,
        output_dir=args.output_dir
    )

    success = processor.process_all_list_files()

    if success:
        print("All files processed successfully.", file=sys.stderr)
        sys.exit(0)
    else:
        print("Some files failed to process.", file=sys.stderr)
        sys.exit(1)
