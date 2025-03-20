#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
import sys
import datetime
from pathlib import Path
from collections import defaultdict

# 配置文件路径（支持命令行参数）
RULE_FILE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("emby.list")
TYPE_ORDER = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "PROCESS-NAME", "USER-AGENT", "IP-CIDR"]
RULE_PATTERN = re.compile(
    r"^(?P<type>" + "|".join(TYPE_ORDER) + r")"
    r"[,\s]+"
    r"(?P<value>[^#\s]+)"  # 捕获规则值
    r"(?:\s*#\s*(?P<comment>.*))?$",  # 捕获行尾注释
    re.IGNORECASE
)

class RuleProcessor:
    def __init__(self):
        self.rule_data = defaultdict(set)
        self.comments = []
        self.other_lines = []

    def load_content(self):
        """加载并解析规则文件"""
        try:
            content = RULE_FILE.read_text(encoding="utf-8")
        except FileNotFoundError:
            print(f"错误：文件 {RULE_FILE} 不存在")
            sys.exit(1)

        header_match = re.search(r"^# NAME:.*?(?=\n[^#]|\Z)", content, re.DOTALL)
        self.header = header_match.group(0) if header_match else ""
        return content[len(self.header):].lstrip('\n')

    def parse_line(self, line: str):
        """解析单行内容"""
        line = line.strip()
        if not line:
            return
        if line.startswith("#"):
            self.comments.append(line)
            return

        if match := RULE_PATTERN.match(line):
            rule_type = match.group("type").upper()  # 统一转为大写
            value = match.group("value").lower().strip()
            self.rule_data[rule_type].add(value)
            
            # 保留行尾注释
            if comment := match.group("comment"):
                self.comments.append(f"# {comment}")
        else:
            self.other_lines.append(line)

    def generate_header(self) -> str:
        """生成元数据头"""
        stats = {k: len(v) for k, v in self.rule_data.items()}
        return (
            f"# NAME: Emby\n"
            f"# AUTHOR: KuGouGo\n"
            f"# REPO: https://github.com/KuGouGo/Rules\n"
            f"# UPDATED: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            + "\n".join(f"# {k}: {v}" for k, v in stats.items() if v > 0)
            + f"\n# TOTAL: {sum(stats.values())}\n\n"
        )

    def sort_rules(self) -> list:
        """生成排序后的规则列表（纯字母顺序）"""
        sorted_rules = []
        for rule_type in TYPE_ORDER:
            if values := self.rule_data.get(rule_type):
                # 按纯字母顺序排序
                sorted_values = sorted(values)
                sorted_rules.extend(
                    f"{rule_type},{v}" 
                    for v in sorted_values
                )
        return sorted_rules

    def save_file(self, new_content: str):
        """保存处理后的内容"""
        try:
            RULE_FILE.write_text(new_content, encoding="utf-8")
        except PermissionError:
            print(f"错误：无权限写入文件 {RULE_FILE}")
            sys.exit(1)

    def process(self):
        """主处理流程"""
        body = self.load_content()
        
        # 解析内容
        for line in body.splitlines():
            self.parse_line(line)

        # 生成新内容
        new_content = (
            self.generate_header()
            + "\n".join(self.comments)
            + ("\n" if self.comments else "")
            + "\n".join(self.sort_rules())
            + ("\n" + "\n".join(self.other_lines) if self.other_lines else "")
        )

        self.save_file(new_content.strip() + "\n")

if __name__ == "__main__":
    RuleProcessor().process()