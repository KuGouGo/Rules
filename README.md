# Rules

一个可直接订阅的规则仓库，面向 **Surge / sing-box / mihomo**。

## 快速跳转

- **Surge**
  - Domain: [domain/surge/](./domain/surge/)
  - IP: [ip/surge/](./ip/surge/)
- **sing-box**
  - Domain: [domain/sing-box/](./domain/sing-box/)
  - IP: [ip/sing-box/](./ip/sing-box/)
- **mihomo**
  - Domain: [domain/mihomo/](./domain/mihomo/)
  - IP: [ip/mihomo/](./ip/mihomo/)

## 仓库内容

```text
.
├── domain/
│   ├── surge/      # Domain rules for Surge
│   ├── sing-box/   # Domain rules for sing-box
│   └── mihomo/     # Domain rules for mihomo
├── ip/
│   ├── surge/      # IP rules for Surge
│   ├── sing-box/   # IP rules for sing-box
│   └── mihomo/     # IP rules for mihomo
├── scripts/
│   ├── sync-all.sh
│   ├── build-custom.sh
│   ├── guard-artifacts.sh
│   └── lint-custom-rules.sh
└── sources/
    ├── domain/
    │   └── custom/
    └── ip/
```

## 使用示例

### Surge

```ini
[Rule]
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/cn.txt,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/surge/cn.txt,DIRECT
```

### sing-box

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/sing-box/cn.srs"
      },
      {
        "tag": "cn-ip",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/sing-box/cn.srs"
      }
    ]
  }
}
```

### mihomo

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/mihomo/cn.mrs"
    interval: 86400

  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/mihomo/cn.mrs"
    interval: 86400
```

## 上游来源

- Domain Surge / sing-box: <https://github.com/nekolsd/sing-geosite>
- IP Surge / sing-box / mihomo: <https://github.com/nekolsd/geoip>
- mihomo 转换工具: <https://github.com/MetaCubeX/mihomo>
