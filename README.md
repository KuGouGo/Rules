# Rules

把上游 geosite / geoip 数据整理成适合以下客户端直接使用的规则文件：

- **Surge**
- **sing-box**
- **mihomo**

## 目录

- [上游来源](#上游来源)
- [目录结构](#目录结构)
- [使用示例](#使用示例)
  - [Surge](#surge)
  - [sing-box](#sing-box)
  - [mihomo--clash-meta)
- [自定义规则](#自定义规则)
- [更新频率](#更新频率)

## 上游来源

- Geosite: [nekolsd/sing-geosite](https://github.com/nekolsd/sing-geosite)
- GeoIP: [nekolsd/geoip](https://github.com/nekolsd/geoip)
- 基础数据: [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)
- IP 数据: [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip)

## 目录结构

```text
sources/
  domain/
    custom/     # 自定义域名规则
  ip/

domain/
  surge/      # Surge DOMAIN-SET
  sing-box/   # sing-box .srs
  mihomo/     # mihomo .mrs

ip/
  surge/      # Surge IP 规则文本
  sing-box/   # sing-box .srs
  mihomo/     # mihomo .mrs
```

## 使用示例

### Surge

#### 域名规则 (DOMAIN-SET)

```ini
[Rule]
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/cn.txt,DIRECT
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/google.txt,Proxy
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/emby.txt,Emby
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/emby-cn.txt,DIRECT
```

#### IP 规则

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/surge/cn.txt,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/surge/us.txt,Proxy
```

### sing-box

```json
{
  "route": {
    "rules": [
      {
        "rule_set": "cn",
        "outbound": "direct"
      },
      {
        "rule_set": "google",
        "outbound": "proxy"
      }
    ],
    "rule_set": [
      {
        "tag": "cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/sing-box/cn.srs",
        "download_detour": "auto"
      },
      {
        "tag": "google",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/sing-box/google.srs",
        "download_detour": "auto"
      },
      {
        "tag": "cn-ip",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/sing-box/cn.srs",
        "download_detour": "auto"
      }
    ]
  }
}
```

### mihomo / Clash Meta

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/mihomo/cn.mrs"
    interval: 86400

  google:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/mihomo/google.mrs"
    interval: 86400

  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/mihomo/cn.mrs"
    interval: 86400

  emby:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/mihomo/emby.mrs"
    interval: 86400

rules:
  - RULE-SET,cn,DIRECT
  - RULE-SET,google,Proxy
  - RULE-SET,cn-ip,DIRECT
  - RULE-SET,emby,Emby
```

## 自定义规则

自定义规则位于 `sources/domain/custom/`，详见 [说明文档](sources/domain/custom/README.md)。

### 文件格式

| 文件 | 用途 |
|-----|------|
| `*.list` | Surge 规则格式，用于生成 DOMAIN-SET |
| `*-domain.txt` | 纯域名列表，用于生成 mihomo `.mrs` |

### 当前自定义规则

- **emby** - Emby 媒体服务域名
- **emby-cn** - Emby 直连域名

## 更新频率

- 自动同步：每 6 小时
- 手动触发：GitHub Actions → Sync Rules → Run workflow

## License

上游项目的许可证适用于其各自的数据。本仓库的自定义规则可自由使用。