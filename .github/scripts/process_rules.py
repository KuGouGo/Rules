import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone
from collections import defaultdict
import argparse
from typing import Dict, Set, List, Optional, Tuple

class RuleProcessor:
    """处理规则文件的主要类，支持多种规则类型和格式转换"""
    
    TYPE_ORDER: List[str] = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "DOMAIN-REGEX", "IP-CIDR", "IP-CIDR6"]
    
    JSON_MAP: Dict[str, str] = {
        "DOMAIN": "domain",
        "DOMAIN-KEYWORD": "domain_keyword", 
        "DOMAIN-SUFFIX": "domain_suffix",
        "DOMAIN-REGEX": "domain_regex",
        "IP-CIDR": "ip_cidr",
        "IP-CIDR6": "ip_cidr"
    }
    
    # 预编译正则表达式以提高性能
    HEADER_REGEX = re.compile(r"^# NAME:.*?(?=\n[^#]|\Z)", re.DOTALL | re.MULTILINE)
    RULE_TYPE_REGEX = re.compile(rf"^({'|'.join(TYPE_ORDER)})[,\s]+([^#\s]+)", re.IGNORECASE)
    DOMAIN_ONLY_REGEX = re.compile(r"^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
    IPV4_REGEX = re.compile(r"^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(?:/(?:3[0-2]|[12]?[0-9]))?$")
    IPV6_REGEX = re.compile(r"^(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}(?:/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9]))?$|^::(?:[0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}(?:/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9]))?$|^(?:[0-9a-fA-F]{1,4}:){1,7}:(?:/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9]))?$")
    REGEX_PATTERN_REGEX = re.compile(r"^[^#\s]+$")  # 基本的正则表达式格式检查

    def __init__(self, rules_dir: Path, output_base_dir: Path):
        """初始化处理器"""
        self.rules_dir = rules_dir
        self.json_dir = output_base_dir / "json"
        self.srs_dir = output_base_dir / "srs"

    def _create_output_dirs(self) -> None:
        """创建输出目录"""
        for dir_path in [self.json_dir, self.srs_dir]:
            dir_path.mkdir(parents=True, exist_ok=True)

    def _load_content(self, file_path: Path) -> Optional[str]:
        """加载文件内容并去除头部信息"""
        try:
            print(f"Processing: {file_path.name}", file=sys.stderr)
            content = file_path.read_text(encoding="utf-8")
            
            # 去除头部信息
            header_match = self.HEADER_REGEX.search(content)
            if header_match:
                return content[len(header_match.group(0)):].lstrip('\n')
            return content
            
        except Exception as e:
            print(f"Error reading {file_path}: {e}", file=sys.stderr)
            return None

    def _parse_line(self, line: str) -> Optional[Tuple[str, str]]:
        """解析单行规则"""
        line = line.strip()
        if not line or line.startswith("#"):
            return None

        # 尝试匹配规则类型格式
        match = self.RULE_TYPE_REGEX.match(line)
        if match:
            rule_type = match.group(1).upper()
            value = match.group(2).strip()
            
            if not value:
                return None
            
            return self._validate_and_normalize_rule(rule_type, value)

        # 尝试自动检测规则类型
        return self._auto_detect_rule_type(line)

    def _validate_and_normalize_rule(self, rule_type: str, value: str) -> Optional[Tuple[str, str]]:
        """验证并标准化规则"""
        if rule_type in ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX"]:
            return (rule_type, value.lower())
            
        elif rule_type == "DOMAIN-REGEX":
            if self.REGEX_PATTERN_REGEX.match(value):
                return (rule_type, value)
            return None
            
        elif rule_type == "IP-CIDR":
            if self.IPV6_REGEX.match(value):
                return ("IP-CIDR6", value)
            elif self.IPV4_REGEX.match(value):
                return (rule_type, value)
            return None
            
        elif rule_type == "IP-CIDR6":
            if self.IPV6_REGEX.match(value):
                return (rule_type, value)
            return None
            
        return None

    def _auto_detect_rule_type(self, line: str) -> Optional[Tuple[str, str]]:
        """自动检测规则类型"""
        if self.DOMAIN_ONLY_REGEX.match(line):
            return ("DOMAIN", line.lower())
        
        if self.IPV4_REGEX.match(line):
            return ("IP-CIDR", line)
        
        if self.IPV6_REGEX.match(line):
            return ("IP-CIDR6", line)

        return None

    def _generate_header(self, name: str, stats: Dict[str, int]) -> str:
        """生成文件头部信息"""
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
        """写入.list格式文件"""
        try:
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
        """写入JSON格式文件"""
        rule_entry = {}
        
        for rule_type, json_key in self.JSON_MAP.items():
            if rule_type in sorted_rules:
                # 合并IPv4和IPv6到同一个ip_cidr字段
                if json_key == "ip_cidr":
                    if "ip_cidr" not in rule_entry:
                        rule_entry["ip_cidr"] = []
                    rule_entry["ip_cidr"].extend(sorted_rules[rule_type])
                else:
                    rule_entry[json_key] = sorted_rules[rule_type]

        if not rule_entry:
            return True

        json_data = {
            "version": 3,
            "rules": [rule_entry]
        }

        try:
            with output_file.open("w", encoding="utf-8") as f:
                json.dump(json_data, f, indent=2, ensure_ascii=False)
                f.write("\n")
            return True
        except Exception as e:
            print(f"Error writing {output_file}: {e}", file=sys.stderr)
            return False

    def _process_single_file(self, input_file: Path) -> Optional[Dict[str, any]]:
        """处理单个规则文件"""
        content = self._load_content(input_file)
        if content is None:
            return None

        rules_data: Dict[str, Set[str]] = defaultdict(set)
        invalid_lines = 0
        
        # 解析所有行
        for line in content.splitlines():
            parsed = self._parse_line(line)
            if parsed:
                rule_type, value = parsed
                rules_data[rule_type].add(value)
            elif line.strip() and not line.strip().startswith("#"):
                invalid_lines += 1

        if invalid_lines > 0:
            print(f"Warning: {invalid_lines} invalid lines in {input_file.name}", file=sys.stderr)

        # 排序并生成统计信息
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
            'stats': stats,
            'invalid_lines': invalid_lines
        }

    def process_all_files(self) -> Dict[str, any]:
        """处理所有规则文件"""
        self._create_output_dirs()
        
        list_files = list(self.rules_dir.glob("*.list"))
        
        if not list_files:
            print(f"No .list files found in {self.rules_dir}", file=sys.stderr)
            return {'success': False, 'message': 'No files found'}

        print(f"Found {len(list_files)} .list files in {self.rules_dir}", file=sys.stderr)
        
        results = {
            'success': True,
            'processed': [],
            'failed': [],
            'total_rules': 0
        }

        for list_file in sorted(list_files):
            result = self._process_single_file(list_file)
            if not result:
                results['failed'].append(list_file.name)
                continue

            name = result['name']
            sorted_rules = result['sorted_rules']
            stats = result['stats']
            invalid_lines = result['invalid_lines']

            if not sorted_rules:
                print(f"No valid rules found in {list_file.name}", file=sys.stderr)
                results['failed'].append(list_file.name)
                continue

            # 生成文件
            header = self._generate_header(name.title(), stats)
            list_output = self.rules_dir / f"{name}.list"
            json_output = self.json_dir / f"{name}.json"

            list_success = self._write_list_file(list_output, header, sorted_rules)
            json_success = self._write_json_file(json_output, sorted_rules)

            if list_success and json_success:
                total_rules = sum(stats.values())
                results['total_rules'] += total_rules
                results['processed'].append({
                    'name': name,
                    'rules': total_rules,
                    'invalid': invalid_lines,
                    'stats': stats
                })
                
                # 输出处理状态
                status_parts = [f"✓ {name}.list ({total_rules} rules"]
                if invalid_lines > 0:
                    status_parts.append(f"{invalid_lines} invalid")
                status_parts.append(")")
                print(" ".join(status_parts), file=sys.stderr)
            else:
                results['failed'].append(name)

        # 输出总结
        success_count = len(results['processed'])
        if success_count > 0:
            print(f"\nProcessing completed:", file=sys.stderr)
            print(f"  ✓ {success_count} files processed successfully", file=sys.stderr)
            print(f"  ✓ {results['total_rules']} total rules", file=sys.stderr)
            print(f"  ✓ {success_count} JSON configs generated", file=sys.stderr)
            if results['failed']:
                print(f"  ✗ {len(results['failed'])} files failed", file=sys.stderr)

        return results


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="Process rule files with organized output")
    parser.add_argument("--rules-dir", type=Path, default=Path("rules"), 
                       help="Directory containing .list files")
    parser.add_argument("--output-dir", type=Path, default=Path("."), 
                       help="Base output directory for json/ and srs/")
    args = parser.parse_args()

    # 验证输入目录
    if not args.rules_dir.exists():
        print(f"Rules directory {args.rules_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    if not args.rules_dir.is_dir():
        print(f"Rules path {args.rules_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    # 处理文件
    processor = RuleProcessor(args.rules_dir, args.output_dir)
    results = processor.process_all_files()

    # 输出结果
    if results['success'] and results['processed']:
        print(f"\n🎯 Summary:", file=sys.stderr)
        print(f"   Rules: {len(results['processed'])} files processed in rules/", file=sys.stderr)
        print(f"   JSON:  {len(results['processed'])} files generated in json/", file=sys.stderr)
        print(f"   Ready for SRS compilation", file=sys.stderr)
        sys.exit(0)
    else:
        print("Processing failed or no files processed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()