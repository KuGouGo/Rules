#!/usr/bin/env python3
import re
import datetime
from collections import defaultdict

RULE_FILE = "emby.list"
HEADER_PATTERN = r"^# NAME:.*?(?=\n[^#]|\Z)"
RULE_REGEX = r"^(?P<type>DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|PROCESS-NAME|USER-AGENT|IP-CIDR)[,\s]+(?P<value>[^#\s]+)"

def process_rules():
    with open(RULE_FILE, "r+", encoding="utf-8") as f:
        content = f.read()

        # 分离元数据与规则内容
        header_match = re.search(HEADER_PATTERN, content, re.DOTALL)
        header = header_match.group(0) if header_match else ""
        body = content[len(header):].lstrip('\n')

        # 解析规则和注释
        rule_dict = defaultdict(set)
        comments = []
        for line in body.splitlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                comments.append(line)
                continue
            if match := re.match(RULE_REGEX, line):
                rule_type = match.group("type")
                value = match.group("value").lower().strip()
                rule_dict[rule_type].add(value)

        # 生成新元数据
        new_header = f"""# NAME: Emby
# AUTHOR: KuGouGo
# REPO: https://github.com/KuGouGo/Rules
# UPDATED: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n"""
        
        # 添加统计信息
        stats = {k: len(v) for k, v in rule_dict.items()}
        for rule_type in sorted(stats.keys()):
            new_header += f"# {rule_type}: {stats[rule_type]}\n"
        new_header += f"# TOTAL: {sum(stats.values())}\n\n"

        # 整理规则（类型排序 → 字母排序）
        sorted_rules = []
        type_order = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "PROCESS-NAME", "USER-AGENT", "IP-CIDR"]
        for rule_type in type_order:
            if rule_type in rule_dict:
                sorted_values = sorted(rule_dict[rule_type])
                sorted_rules.extend([f"{rule_type},{v}" for v in sorted_values])

        # 重组文件内容
        new_content = new_header + "\n".join(comments + sorted_rules)

        # 写回文件
        f.seek(0)
        f.truncate()
        f.write(new_content)

if __name__ == "__main__":
    process_rules()