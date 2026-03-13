# Rules

把上游 geosite / geoip 数据整理成适合以下客户端直接使用的规则文件：

- **Surge**
- **sing-box**
- **mihomo**

## 目录

- [上游来源](#上游来源)
- [目录结构](#目录结构)
- [快速跳转](#快速跳转)
  - [sources/domain/custom](#sourcesdomaincustom)
  - [sources/ip](#sourcesip)
  - [domain/surge](#domainsurge)
  - [domain/sing-box](#domainsing-box)
  - [domain/mihomo](#domainmihomo)
  - [ip/surge](#ipsurge)
  - [ip/sing-box](#ipsing-box)
  - [ip/mihomo](#ipmihomo)
- [快速开始](#快速开始)
- [使用示例](#使用示例)
  - [Surge](#surge)
  - [sing-box](#sing-box)
  - [mihomo / Clash Meta](#mihomo--clash-meta)
- [自定义规则](#自定义规则)
- [更新频率](#更新频率)
- [License](#license)

## 上游来源

本仓库不生产原始规则数据，主要对上游项目做同步、编译和发布。

### 域名规则 (Geosite)
- 数据源: [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) (dlc.dat)
- 编译产物: Surge DOMAIN-SET / sing-box .srs / mihomo .mrs

### IP 规则 (GeoIP)
- 数据源: [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip) (Country.mmdb)
- sing-box .srs: 来自 [nekolsd/geoip](https://github.com/nekolsd/geoip) release 分支预构建文件
- 编译脚本: [nekolsd/geoip](https://github.com/nekolsd/geoip)

## 目录结构

```text
sources/
  domain/       # 上游域名规则构建源（含 .github/workflows, custom/ 等）
    custom/     # 自定义域名规则源
  ip/           # 上游 IP 规则构建源（含 plugin/, lib/ 等）

domain/
  surge/        # Surge DOMAIN-SET
  sing-box/     # sing-box .srs
  mihomo/       # mihomo .mrs

ip/
  surge/        # Surge IP 规则文本
  sing-box/     # sing-box .srs
  mihomo/       # mihomo .mrs
```

## 快速跳转

### sources/domain/custom

自定义域名规则源文件目录：

- [sources/domain/custom/](./sources/domain/custom/)
- 示例文件：
  - [emby.list](./sources/domain/custom/emby.list)
  - [emby-domain.txt](./sources/domain/custom/emby-domain.txt)
  - [emby-cn.list](./sources/domain/custom/emby-cn.list)
  - [emby-cn-domain.txt](./sources/domain/custom/emby-cn-domain.txt)
  - [README.md](./sources/domain/custom/README.md)

### sources/ip

IP 规则上游构建源目录：

- [sources/ip/](./sources/ip/)

### domain/surge

Surge 域名规则目录，使用 **DOMAIN-SET** 格式：

- [domain/surge/](./domain/surge/)
- 常用示例：
  - [cn.txt](./domain/surge/cn.txt)
  - [google.txt](./domain/surge/google.txt)
  - [emby.txt](./domain/surge/emby.txt)
  - [emby-cn.txt](./domain/surge/emby-cn.txt)

### domain/sing-box

sing-box 域名规则目录，使用 `.srs` 二进制规则集：

- [domain/sing-box/](./domain/sing-box/)
- 常用示例：
  - [cn.srs](./domain/sing-box/cn.srs)
  - [google.srs](./domain/sing-box/google.srs)
  - [emby.srs](./domain/sing-box/emby.srs)
  - [emby-cn.srs](./domain/sing-box/emby-cn.srs)

### domain/mihomo

mihomo 域名规则目录，使用 `.mrs` 规则集：

- [domain/mihomo/](./domain/mihomo/)
- 常用示例：
  - [cn.mrs](./domain/mihomo/cn.mrs)
  - [google.mrs](./domain/mihomo/google.mrs)
  - [emby.mrs](./domain/mihomo/emby.mrs)
  - [emby-cn.mrs](./domain/mihomo/emby-cn.mrs)

### ip/surge

Surge IP 规则目录：

- [ip/surge/](./ip/surge/)
- 常用示例：
  - [cn.txt](./ip/surge/cn.txt)
  - [us.txt](./ip/surge/us.txt)

### ip/sing-box

sing-box IP 规则目录：

- [ip/sing-box/](./ip/sing-box/)
- 常用示例：
  - [cn.srs](./ip/sing-box/cn.srs)
  - [us.srs](./ip/sing-box/us.srs)

### ip/mihomo

mihomo IP 规则目录：

- [ip/mihomo/](./ip/mihomo/)
- 常用示例：
  - [cn.mrs](./ip/mihomo/cn.mrs)
  - [us.mrs](./ip/mihomo/us.mrs)

## 快速开始

### Surge 中国直连

```ini
[Rule]
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/cn.txt,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/surge/cn.txt,DIRECT
```

### sing-box 中国直连

```json
{
  "route": {
    "rules": [
      {
        "rule_set": ["cn", "cn-ip"],
        "outbound": "direct"
      }
    ],
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

### mihomo 中国直连

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

rules:
  - RULE-SET,cn,DIRECT
  - RULE-SET,cn-ip,DIRECT
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
      },
      {
        "rule_set": "emby",
        "outbound": "Emby"
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
        "tag": "emby",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/sing-box/emby.srs",
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

自定义规则位于 [sources/domain/custom/](./sources/domain/custom/)，详见 [说明文档](./sources/domain/custom/README.md)。

### 文件格式

| 文件 | 用途 |
|-----|------|
| `*.list` | 主维护源，使用 `DOMAIN` / `DOMAIN-SUFFIX` 规则语义 |
| `*-domain.txt` | 辅助纯域名列表，用于生成 mihomo `.mrs` |

### 当前自定义规则

- **emby** - Emby 媒体服务域名
- **emby-cn** - Emby 直连域名

### 自定义规则生成范围

当前自定义域名规则会自动生成：

- `domain/surge/*.txt`
- `domain/sing-box/*.srs`
- `domain/mihomo/*.mrs`

## 更新频率

- 自动同步：每 6 小时
- 手动触发：GitHub Actions → Sync Rules → Run workflow

## License

上游项目的许可证适用于其各自的数据。请遵循对应上游仓库的许可证要求。
本仓库的自定义规则部分可自由使用。
