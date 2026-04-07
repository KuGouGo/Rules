# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)

代理规则集，每日自动同步，支持 **Surge**、**sing-box**、**mihomo** 三端直接订阅。

---

## 域名规则

来源：[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)，1400+ 个规则组。

**URL 格式**

```
Surge   https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/{name}.list
sing-box https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/{name}.srs
mihomo  https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/{name}.mrs
```

**常用规则组**

| 名称 | 说明 |
|------|------|
| `cn` | 中国大陆域名 |
| `google` | Google 全系服务 |
| `youtube` | YouTube |
| `apple` | Apple 全系服务 |
| `icloud` | iCloud |
| `telegram` | Telegram |
| `netflix` | Netflix |
| `spotify` | Spotify |
| `disney` | Disney+ |
| `github` | GitHub |
| `twitter` | Twitter / X |
| `facebook` | Facebook / Meta |
| `instagram` | Instagram |
| `tiktok` | TikTok |
| `discord` | Discord |
| `openai` | OpenAI / ChatGPT |
| `cloudflare` | Cloudflare |

完整列表：[surge/domain/](https://github.com/KuGouGo/Rules/tree/surge/domain)

---

## IP 规则

**URL 格式**

```
Surge   https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/{name}.list
sing-box https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/{name}.srs
mihomo  https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/{name}.mrs
```

**可用规则**

| 名称 | 说明 |
|------|------|
| `cn` | 中国大陆 IP（IPv4 + IPv6）|
| `google` | Google |
| `telegram` | Telegram |
| `cloudflare` | Cloudflare |
| `cloudfront` | Amazon CloudFront |
| `aws` | Amazon AWS 全量 |
| `fastly` | Fastly CDN |
| `github` | GitHub |
| `apple` | Apple |
| `netflix` | Netflix |
| `spotify` | Spotify |
| `disney` | Disney+ |

---

## 使用示例

### Surge

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/netflix.list,PROXY
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/netflix.list,PROXY
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
      },
      {
        "tag": "netflix",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/netflix.srs"
      },
      {
        "tag": "netflix-ip",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/netflix.srs"
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

  netflix:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/netflix.mrs"
    interval: 86400

  netflix-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/netflix.mrs"
    interval: 86400
```

---

## 自定义规则

在 `sources/custom/domain/` 新建 `{name}.list`：

```
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,keyword
```

在 `sources/custom/ip/` 新建 `{name}.list`：

```
IP-CIDR,1.2.3.0/24
IP-CIDR6,2403:300::/32
```

提交后 CI 自动编译并发布到三端分支。自定义规则名称不能与现有规则组重名。

---

每日 08:00 UTC 自动同步所有上游数据。
