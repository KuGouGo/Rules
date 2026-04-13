# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)

多端代理规则集，支持 **Surge / QuanX / Egern / sing-box / mihomo**。
每日 08:00 UTC 自动同步并发布。

## 订阅地址

```text
Surge Domain     https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/{name}.list
Surge IP         https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/{name}.list
QuanX Domain     https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/{name}.list
QuanX IP         https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/{name}.list
Egern Domain     https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/{name}.yaml
Egern IP         https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/{name}.yaml
sing-box Domain  https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/{name}.srs
sing-box IP      https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/{name}.srs
mihomo Domain    https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/{name}.mrs
mihomo IP        https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/{name}.mrs
```

- Domain 全量列表: [surge/domain](https://github.com/KuGouGo/Rules/tree/surge/domain)
- IP 全量列表: [surge/ip](https://github.com/KuGouGo/Rules/tree/surge/ip)

## 常用规则组

- Domain: `cn` `google` `youtube` `apple` `telegram` `netflix` `spotify` `disney` `github` `openai` `cloudflare`
- Ads: `awavenue-ads`
- IP: `cn` `google` `telegram` `cloudflare` `cloudfront` `aws` `fastly` `github` `apple` `netflix` `spotify` `disney`

## 快速示例

### Surge

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```

### QuanX

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
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
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs"
      },
      {
        "tag": "cn-ip",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/cn.srs"
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
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/cn.mrs"
    interval: 86400

  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/cn.mrs"
    interval: 86400
```

### Egern

```text
Domain https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml
IP     https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml
```

## 自定义规则

在 `sources/custom/domain/` 新建 `{name}.list`：

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,keyword
```

在 `sources/custom/ip/` 新建 `{name}.list`：

```text
IP-CIDR,1.2.3.0/24
IP-CIDR6,2403:300::/32
```

说明：

- Domain 类型大小写不敏感，`_` 与 `-` 等价（如 `DOMAIN_SUFFIX` = `DOMAIN-SUFFIX`）
- 构建会标准化：`DOMAIN` / `DOMAIN-SUFFIX` 值转小写并移除末尾 `.`，`DOMAIN-KEYWORD` 值转小写
- 上游导出兼容前缀别名：`domain-suffix` / `domain_suffix` / `suffix`、`domain-full`、`domain-keyword`、`domain-regex` / `regex`
- 自定义规则名不能与现有规则组重名

## 上游来源

- Domain: <https://github.com/v2fly/domain-list-community>
- Ads Domain: <https://github.com/TG-Twilight/AWAvenue-Ads-Rule> (`awavenue-ads`)
- IP: ispip clang、china-operator-ip、Google、Telegram、Cloudflare、AWS/CloudFront、Fastly、GitHub、Apple、RIPE Stat
- 详细来源见 [scripts/sync-upstream.sh](scripts/sync-upstream.sh)
