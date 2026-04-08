# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)
[![Repo Size](https://img.shields.io/github/repo-size/KuGouGo/Rules)](https://github.com/KuGouGo/Rules)
[![Surge](https://img.shields.io/badge/client-Surge-orange)](https://github.com/KuGouGo/Rules/tree/surge)
[![QuanX](https://img.shields.io/badge/client-QuanX-purple)](https://github.com/KuGouGo/Rules/tree/quanx)
[![sing-box](https://img.shields.io/badge/client-sing--box-blue)](https://github.com/KuGouGo/Rules/tree/sing-box)
[![mihomo](https://img.shields.io/badge/client-mihomo-green)](https://github.com/KuGouGo/Rules/tree/mihomo)

代理规则集，每日自动同步，支持 **Surge**、**QuanX**、**sing-box**、**mihomo** 四端直接订阅。

---

## 域名规则

来源：[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)，1400+ 个规则组。

**URL 格式**

```text
Surge    https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/{name}.list
QuanX    https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/{name}.list
sing-box https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/{name}.srs
mihomo   https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/{name}.mrs
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

```text
Surge    https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/{name}.list
QuanX    https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/{name}.list
sing-box https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/{name}.srs
mihomo   https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/{name}.mrs
```

**可用规则**

| 名称 | 说明 |
|------|------|
| `cn` | 中国大陆 IP（IPv4 + IPv6，ISP + ASN/BGP 并集） |
| `google` | Google |
| `telegram` | Telegram |
| `cloudflare` | Cloudflare |
| `cloudfront` | Amazon CloudFront |
| `aws` | Amazon AWS 全量 |
| `fastly` | Fastly CDN |
| `github` | GitHub |
| `apple` | Apple |
| `netflix` | Netflix（RIPE ASN 推导） |
| `spotify` | Spotify（RIPE ASN 推导） |
| `disney` | Disney+（RIPE ASN 推导） |

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

---

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

提交后 CI 自动编译并发布到四端分支。自定义规则名称不能与现有规则组重名。

---

## 上游来源

- Domain source: <https://github.com/v2fly/domain-list-community>
- CN IP sources: <https://ispip.clang.cn/all_cn.txt> and <https://ispip.clang.cn/all_cn_ipv6.txt>
- CN ASN/BGP sources: <https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt> and <https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt>
- Google IP source: <https://www.gstatic.com/ipranges/goog.json>
- Telegram IP source: <https://core.telegram.org/resources/cidr.txt>
- Cloudflare IP source: <https://www.cloudflare.com/ips/>
- CloudFront / AWS IP source: <https://ip-ranges.amazonaws.com/ip-ranges.json>
- Fastly IP source: <https://api.fastly.com/public-ip-list>
- GitHub IP source: <https://api.github.com/meta>
- Apple IP source: <https://support.apple.com/en-us/101555> (fallback: <https://support.apple.com/zh-cn/101555>)
- RIPE ASN prefixes source: <https://stat.ripe.net/>

---

每日 08:00 UTC 自动同步所有上游数据。
