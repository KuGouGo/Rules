#!/usr/bin/env python3
import re
import datetime
import os

# 重点配置：规则文件路径（假设规则文件在仓库根目录）
RULE_FILE = "emby.list"
STATS = {
    "DOMAIN": 0,
    "DOMAIN-SUFFIX": 0,
    "DOMAIN-KEYWORD": 0,
    "PROCESS-NAME": 0,
    "USER-AGENT": 0,
    "IP-CIDR": 0
}

def update_metadata():
    with open(RULE_FILE, "r+") as f:
        content = f.read()
        
        # 统计规则数量
        for rule_type in STATS:
            STATS[rule_type] = len(re.findall(rf"^{rule_type}(?=\s|,)", content, re.M))
        
        # 生成新header
        new_header = f"""# NAME: Emby
# AUTHOR: KuGouGo
# REPO: https://github.com/KuGouGo/Rules
# UPDATED: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
"""
        # 添加统计信息
        for k, v in STATS.items():
            if v > 0:
                new_header += f"# {k}: {v}\n"
        total = sum(STATS.values())
        new_header += f"# TOTAL: {total}\n\n"
        
        # 替换旧header
        new_content = re.sub(r"^# NAME:.*?(?=\n[^#]|\Z)", new_header.strip(), content, flags=re.DOTALL)
        
        # 写回文件
        f.seek(0)
        f.truncate()
        f.write(new_content)

if __name__ == "__main__":
    update_metadata()