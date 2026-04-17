# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)

多平台代理规则仓库，支持：
- Surge
- Quantumult X（QuanX）
- Egern
- sing-box
- mihomo

特点：
- 统一维护，多端输出
- 每日自动同步发布
- 支持自定义规则
- 提供 Domain / IP 两类规则

更新时间：每日 08:00 UTC

## 目录

- [订阅地址](#订阅地址)
- [配置示例](#配置示例)
- [常用规则](#常用规则)
- [自定义规则](#自定义规则)
- [仓库结构](#仓库结构)
- [自动化与来源](#自动化与来源)

---

## 订阅地址

通用地址模板：

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

说明：
- `{name}` 替换为规则名，例如：`cn`、`google`、`telegram`
- 通常建议 Domain + IP 搭配使用
- Domain 优先，IP 作为补充

分支索引：
- [surge](https://github.com/KuGouGo/Rules/tree/surge)
- [quanx](https://github.com/KuGouGo/Rules/tree/quanx)
- [egern](https://github.com/KuGouGo/Rules/tree/egern)
- [sing-box](https://github.com/KuGouGo/Rules/tree/sing-box)
- [mihomo](https://github.com/KuGouGo/Rules/tree/mihomo)

---

## 配置示例

### Surge

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/google.list,PROXY
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/google.list,PROXY
```

### Quantumult X（QuanX）

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/google.list, tag=GOOGLE-DOMAIN, force-policy=proxy, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/google.list, tag=GOOGLE-IP, force-policy=proxy, enabled=true
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

---

## 常用规则

常用 Domain：
- `cn`
- `google`
- `apple`
- `telegram`
- `github`
- `openai`
- `cloudflare`
- `youtube`
- `netflix`
- `spotify`
- `disney`

广告规则：
- `awavenue-ads`

常用 IP：
- `cn`
- `google`
- `telegram`
- `cloudflare`
- `cloudfront`
- `aws`
- `fastly`
- `github`
- `apple`
- `netflix`
- `spotify`
- `disney`

推荐起步组合：
- 国内直连：`cn`
- 国外常用：`google` `telegram` `github` `openai`
- 苹果：`apple`
- CDN 补充：`cloudflare`

---

## 自定义规则

自定义 Domain：
- `sources/custom/domain/{name}.list`

示例：

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,keyword
```

自定义 IP：
- `sources/custom/ip/{name}.list`

示例：

```text
IP-CIDR,1.2.3.0/24
IP-CIDR6,2403:300::/32
```

注意：
- 名称不要与现有规则组重名
- `DOMAIN_SUFFIX` 与 `DOMAIN-SUFFIX` 等价
- 构建时会自动标准化大小写与格式

---

## 仓库结构

```text
README.md                     项目说明
.github/workflows/build.yml   自动构建与发布流程
scripts/                      构建、同步、校验脚本
sources/custom/               自定义规则源
```

---

## 自动化与来源

自动化流程：
- [build.yml](.github/workflows/build.yml)

核心脚本：
- [scripts/sync-upstream.sh](scripts/sync-upstream.sh)
- [scripts/build-custom.sh](scripts/build-custom.sh)
- [scripts/restore-artifacts.sh](scripts/restore-artifacts.sh)
- [scripts/guard-artifacts.sh](scripts/guard-artifacts.sh)
- [scripts/normalize-ip-source.py](scripts/normalize-ip-source.py)
- [scripts/export-domain-rules.py](scripts/export-domain-rules.py)

上游来源：
- [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)
- [TG-Twilight/AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule)
- [ispip.clang.cn](https://ispip.clang.cn/)
- [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip)
- [Google IP ranges](https://www.gstatic.com/ipranges/goog.json)
- [Telegram CIDR](https://core.telegram.org/resources/cidr.txt)
- [Cloudflare IPs](https://www.cloudflare.com/ips/)
- [AWS IP ranges](https://ip-ranges.amazonaws.com/ip-ranges.json)
- [Fastly public IP list](https://api.fastly.com/public-ip-list)
- [GitHub Meta API](https://api.github.com/meta)
- [Apple network list](https://support.apple.com/en-us/101555)
- [RIPE NCC Stat](https://stat.ripe.net/)
