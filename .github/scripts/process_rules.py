#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
import sys
import datetime
from pathlib import Path
from collections import defaultdict
import json

# 配置文件路径（支持命令行参数）
RULE_FILE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("emby.list")
OUTPUT_JSON_FILE = Path("emby.json")
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
        self.rules = [] # 用于存储最终的规则列表

    def load_content(self):
        """加载并解析规则文件"""
        try:
            content = RULE_FILE.read_text(encoding="utf-8")
        except FileNotFoundError:
            print(f"错误：文件 {RULE_FILE} 不存在")
            sys.exit(1)

        self.header_match = re.search(r"^# NAME:.*?(?=\n[^#]|\Z)", content, re.DOTALL)
        self.header = self.header_match.group(0) if self.header_match else ""
        return content[len(self.header):].lstrip('\n')

    def parse_line(self, line: str):
        """解析单行内容并添加到 rules 列表"""
        line = line.strip()
        if not line:
            return
        if line.startswith("#"):
            return

        if match := RULE_PATTERN.match(line):
            rule_type = match.group("type").upper()  # 统一转为大写
            value = match.group("value").lower().strip()
            if rule_type == "DOMAIN-KEYWORD":
                self.rules.append({"domain_keyword": value})
            elif rule_type == "DOMAIN-SUFFIX":
                self.rules.append({"domain_suffix": value})
            elif rule_type == "DOMAIN":
                self.rules.append({"domain": value})
            else:
                # 对于其他类型的规则，如果 Sing-box 需要，你可以在这里添加处理逻辑
                print(f"警告：未处理的规则类型: {rule_type}, 值: {value}")
        else:
            # 如果没有匹配到任何前缀，则尝试作为纯域名处理
            self.rules.append({"domain": line})

    def generate_json_output(self):
        """生成 Sing-box 格式的 JSON 输出"""
        output_data = {
            "version": 1,
            "rules": self.rules
        }
        try:
            with open(OUTPUT_JSON_FILE, 'w', encoding='utf-8') as outfile:
                json.dump(output_data, outfile, indent=2)
            print(f"成功生成 {OUTPUT_JSON_FILE}")
        except PermissionError:
            print(f"错误：无权限写入文件 {OUTPUT_JSON_FILE}")
            sys.exit(1)

    def process(self):
        """主处理流程"""
        body = self.load_content()

        # 解析内容并添加到 rules 列表
        for line in body.splitlines():
            self.parse_line(line)

        # 生成 JSON 输出
        self.generate_json_output()

if __name__ == "__main__":
    RuleProcessor().process()
