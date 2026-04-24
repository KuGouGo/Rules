# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)

多平台代理规则仓库，每日自动同步上游数据源。

**支持平台：** Surge | Quantumult X | Egern | sing-box | mihomo

## 快速使用

### 订阅地址

```
https://raw.githubusercontent.com/KuGouGo/Rules/{platform}/{type}/{name}.{ext}
```

- `{platform}`: surge | quanx | egern | sing-box | mihomo
- `{type}`: domain | ip
- `{name}`: 规则名称（见下方列表）
- `{ext}`: list | yaml | srs | mrs

**示例：**
```
https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list
https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/google.srs
```

### 常用规则

**基础：**
- `cn` - 中国大陆
- `geolocation-!cn` - 非中国大陆
- `geolocation-!cn@cn` - 非中国大陆（CDN 友好）
- `private` - 私有网络

**服务：**
- `google`, `apple`, `microsoft`, `telegram`, `github`
- `openai`, `anthropic`, `cloudflare`, `aws`

**流媒体：**
- `youtube`, `netflix`, `spotify`, `disney`

**其他：**
- `awavenue-ads` - 广告拦截

## 配置示例

### Surge

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/google.list,PROXY
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/awavenue-ads.list,REJECT
```

### Quantumult X

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/google.list, tag=Google, force-policy=proxy, enabled=true
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
      }
    ],
    "rules": [
      {"rule_set": ["cn"], "outbound": "direct"}
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

rules:
  - RULE-SET,cn,DIRECT
```

## 自定义规则

在 `sources/custom/domain/` 或 `sources/custom/ip/` 下添加 `.list` 文件：

```text
# domain/myapp.list
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,keyword

# ip/myapp.list
IP-CIDR,1.2.3.0/24
IP-CIDR6,2001:db8::/32
```

构建时会自动合并并生成多平台格式。

更完整的维护文档：

- [自定义规则格式](docs/rule-source-format.md)
- [生成产物说明](docs/generated-artifacts.md)
- [维护与发布手册](docs/maintenance-runbook.md)

## 数据来源

**域名：**
- [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)
- [TG-Twilight/AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule)

**IP：**
- 中国：[ispip.clang.cn](https://ispip.clang.cn/), [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip)
- 国际：Google, Telegram, Cloudflare, AWS, GitHub, Apple 官方 API
- 流媒体：Netflix, Spotify, Disney+ (ASN)
- 私有：RFC 1918, RFC 6598, RFC 4193 等

## 更新

每日 08:00 UTC 自动构建，或手动触发 [Actions](https://github.com/KuGouGo/Rules/actions)。

维护者可参考 [维护与发布手册](docs/maintenance-runbook.md) 了解本地校验、手动构建范围与发布分支行为。

## License

MIT
