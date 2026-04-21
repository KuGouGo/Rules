# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)

多平台代理规则仓库，每日自动同步上游数据源并生成规则文件。

## 支持平台

- Surge
- Quantumult X (QuanX)
- Egern
- sing-box
- mihomo (Clash Meta)

## 特点

- 统一维护，多平台输出
- 每日自动同步（08:00 UTC）
- 支持自定义规则扩展
- 提供 Domain 和 IP 两类规则
- 自动生成 @cn 属性过滤版本

---

## 快速开始

### 订阅地址格式

```
https://raw.githubusercontent.com/KuGouGo/Rules/{platform}/{type}/{name}.{ext}
```

**参数说明：**
- `{platform}`: surge | quanx | egern | sing-box | mihomo
- `{type}`: domain | ip
- `{name}`: 规则名称（见下方常用规则列表）
- `{ext}`: list (Surge/QuanX) | yaml (Egern) | srs (sing-box) | mrs (mihomo)

**示例：**
```
Surge Domain:    https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list
sing-box IP:     https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/google.srs
mihomo Domain:   https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/telegram.mrs
```

### 常用规则列表

**基础规则：**
- `cn` - 中国大陆域名/IP
- `geolocation-!cn` - 非中国大陆域名
- `geolocation-!cn@cn` - 非中国大陆域名（仅包含 @cn 标记的 CDN 友好规则）
- `private` - 私有域名（.local、.lan、路由器管理域名等）
- `privateip` - 私有 IP 地址段（RFC 1918 等）

**常用服务：**
- `google` - Google 服务
- `apple` - Apple 服务
- `microsoft` - Microsoft 服务
- `telegram` - Telegram
- `github` - GitHub
- `openai` - OpenAI / ChatGPT
- `anthropic` - Anthropic / Claude
- `cloudflare` - Cloudflare CDN
- `cloudfront` - AWS CloudFront
- `aws` - Amazon Web Services

**流媒体：**
- `youtube` - YouTube
- `netflix` - Netflix
- `spotify` - Spotify
- `disney` - Disney+

**广告过滤：**
- `awavenue-ads` - 广告拦截规则

**推荐配置组合：**
```
国内直连：cn (domain + ip)
国外代理：google, telegram, github, openai (domain + ip)
CDN 优化：cloudflare (ip)
广告拦截：awavenue-ads (domain)
私有网络：private (domain), privateip (ip)
```

---

## 配置示例

### Surge

```ini
[Rule]
# 国内直连
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT

# 私有网络直连
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/private.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/privateip.list,DIRECT

# 国外服务代理
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/google.list,PROXY
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/telegram.list,PROXY

# 广告拦截
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/awavenue-ads.list,REJECT
```

### Quantumult X

```ini
[filter_remote]
# 国内直连
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN域名, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true

# 国外服务代理
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/google.list, tag=Google, force-policy=proxy, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/telegram.list, tag=Telegram, force-policy=proxy, enabled=true

# 广告拦截
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/awavenue-ads.list, tag=广告拦截, force-policy=reject, enabled=true
```

### sing-box

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "cn-domain",
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
        "tag": "google",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/google.srs"
      }
    ],
    "rules": [
      {
        "rule_set": ["cn-domain", "cn-ip"],
        "outbound": "direct"
      },
      {
        "rule_set": ["google"],
        "outbound": "proxy"
      }
    ]
  }
}
```

### mihomo (Clash Meta)

```yaml
rule-providers:
  cn-domain:
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

  google:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/google.mrs"
    interval: 86400

rules:
  - RULE-SET,cn-domain,DIRECT
  - RULE-SET,cn-ip,DIRECT
  - RULE-SET,google,PROXY
```

---

## 自定义规则

你可以在 `sources/custom/` 目录下添加自定义规则，构建时会自动合并。

### 添加自定义域名规则

创建文件：`sources/custom/domain/{name}.list`

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,keyword
DOMAIN-REGEX,^.*\.example\.com$
```

### 添加自定义 IP 规则

创建文件：`sources/custom/ip/{name}.list`

```text
IP-CIDR,1.2.3.0/24
IP-CIDR6,2001:db8::/32
```

**注意事项：**
- 规则名称不要与现有规则重名
- 支持 `DOMAIN-SUFFIX` 和 `DOMAIN_SUFFIX` 等多种写法
- 构建时会自动标准化格式

---

## 数据来源

### 域名规则
- [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) - 主要域名列表
- [TG-Twilight/AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule) - 广告过滤规则

### IP 规则

**中国 IP：**
- [ispip.clang.cn](https://ispip.clang.cn/) - 中国 IPv4/IPv6 地址
- [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip) - 中国运营商 IP（基于 ASN）

**国际服务：**
- [Google IP ranges](https://www.gstatic.com/ipranges/goog.json)
- [Telegram CIDR](https://core.telegram.org/resources/cidr.txt)
- [Cloudflare IPs](https://www.cloudflare.com/ips/)
- [AWS IP ranges](https://ip-ranges.amazonaws.com/ip-ranges.json)
- [Fastly public IP list](https://api.fastly.com/public-ip-list)
- [GitHub Meta API](https://api.github.com/meta)
- [Apple network list](https://support.apple.com/en-us/101555)

**流媒体服务（通过 ASN）：**
- Netflix (AS2906, AS40027)
- Spotify (AS35228, AS7441)
- Disney+ (AS133530, AS394297)
- 数据来源：[RIPE NCC Stat](https://stat.ripe.net/)

**私有 IP：**
- RFC 1918, RFC 6598, RFC 3927, RFC 4193, RFC 4291 等标准私有地址段

---

## 仓库结构

```
.
├── .github/workflows/build.yml    # 自动构建流程
├── scripts/                       # 构建脚本
│   ├── sync-upstream.sh          # 同步上游数据源
│   ├── build-custom.sh           # 构建自定义规则
│   ├── export-domain-rules.py    # 导出域名规则
│   └── normalize-ip-source.py    # 标准化 IP 规则
├── sources/custom/               # 自定义规则源
│   ├── domain/                   # 自定义域名规则
│   └── ip/                       # 自定义 IP 规则
└── README.md                     # 本文档
```

**输出分支：**
- [surge](https://github.com/KuGouGo/Rules/tree/surge) - Surge 规则
- [quanx](https://github.com/KuGouGo/Rules/tree/quanx) - Quantumult X 规则
- [egern](https://github.com/KuGouGo/Rules/tree/egern) - Egern 规则
- [sing-box](https://github.com/KuGouGo/Rules/tree/sing-box) - sing-box 规则
- [mihomo](https://github.com/KuGouGo/Rules/tree/mihomo) - mihomo 规则

---

## 更新频率

- 自动构建时间：每日 08:00 UTC
- 触发条件：定时任务或手动触发
- 构建流程：同步上游 → 处理规则 → 生成多平台格式 → 推送到对应分支

---

## License

MIT License
