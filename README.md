# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

每日自动构建的分流规则集，支持 **Surge**、**Quantumult X**、**Egern**、**sing-box** 和 **mihomo**。

> `main` 分支仅存放构建脚本与配置，**请通过下方对应客户端分支订阅规则**。

## 订阅指南

| 客户端 | 产物分支 | 格式 | 支持的域名规则类型 |
| --- | --- | --- | --- |
| Surge | [`surge`](https://github.com/KuGouGo/Rules/tree/surge) | `.list` | 精确、后缀、关键词（不含正则） |
| Quantumult X | [`quanx`](https://github.com/KuGouGo/Rules/tree/quanx) | `.list` | 精确、后缀、关键词（不含正则） |
| Egern | [`egern`](https://github.com/KuGouGo/Rules/tree/egern) | `.yaml` | 精确、后缀、关键词、正则 |
| sing-box | [`sing-box`](https://github.com/KuGouGo/Rules/tree/sing-box) | `.srs` | 精确、后缀、关键词、正则 |
| mihomo | [`mihomo`](https://github.com/KuGouGo/Rules/tree/mihomo) | `.mrs` | 精确、后缀（不含关键词与正则） |

订阅地址格式：

```text
https://raw.githubusercontent.com/KuGouGo/Rules/{分支}/{domain|ip}/{名称}.{后缀}
```

- 各分支的 `README.md` 提供完整的**产物清单**与实时条目数。
- 如需锁定特定版本，可将订阅地址中的 `{分支}` 替换为对应的提交 SHA。

<details>
<summary>查看各客户端配置示例</summary>

**Surge**

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```

**Quantumult X**

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```

**Egern**

```yaml
rules:
  - rule_set:
      match: "https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml"
      policy: DIRECT
  - rule_set:
      match: "https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml"
      policy: DIRECT
```

**sing-box**

```json
{
  "route": {
    "rule_set": [
      { "tag": "cn", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs" },
      { "tag": "cn-ip", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/cn.srs" }
    ]
  }
}
```

**mihomo**

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/cn.mrs
    interval: 86400
  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/cn.mrs
    interval: 86400
```

</details>

## 规则说明

| 路径 | 内容说明 | 推荐策略 |
| --- | --- | --- |
| `domain/cn` | 中国大陆域名（合并 `tld-cn` 与 `geolocation-cn`） | 直连 |
| `domain/geolocation-!cn` | 境外常用域名合集 | 代理 |
| `domain/geolocation-!cn@cn` | 境外服务在中国大陆可直连的域名 | 直连（置于 `geolocation-!cn` 之前） |
| `domain/{service}` | 主流境外服务域名（`apple`、`google`、`microsoft`、`openai`、`telegram`、`netflix` 等） | 按需分流 |
| `domain/{service}@cn` | 对应服务在大陆可直连的域名（`apple@cn`、`google@cn`、`microsoft@cn`、`steam@cn`） | 直连（置于对应服务规则之前） |
| `domain/category-ai-chat-!cn` | 境外主流 AI 对话服务域名合集 | 代理 |
| `domain/fakeip-filter` | Fake-IP 模式下需跳过虚拟 IP 解析的域名 | Fake-IP 过滤 / 直连 |
| `ip/cn` | 中国大陆 IPv4 / IPv6 地址段 | 直连 |
| `ip/private` | 局域网与保留地址段 | 直连 |
| `ip/apple`、`ip/google`、`ip/telegram` | 对应服务的 ASN 路由地址段 | 按需分流 |

> **分流顺序提示**：带有 `@cn` 后缀的直连子集必须排列在对应代理规则之前，否则会被代理规则提前匹配。

## 构建与开发

工作流每日定时拉取上游数据（推送 `main` 分支亦会触发），依次执行规范化、去重、健康阈值检查与官方编译器构建，校验通过后原子推送到五个客户端分支。

### 目录结构

```text
config/             上游数据源、平台能力与发布策略配置
sources/custom/     自维护规则源（domain/ 为 Surge 经典格式，ip/ 为 CIDR 列表）
scripts/            同步、构建、校验、发布脚本及测试套件
templates/          各产物分支的 README 模板
```

### 本地命令

完整构建需在 Linux 环境下运行（依赖官方 Linux 二进制编译器）；其他系统可使用 `make build-custom-rules-text` 仅生成文本规则。

| 命令 | 说明 |
| --- | --- |
| `make validate` | 运行全部语法检查、配置校验与测试（与 CI 门禁一致） |
| `make build-custom-rules` | 构建自定义规则与二进制产物（仅限 Linux） |
| `make build-custom-rules-text` | 仅构建自定义规则的文本产物 |
| `make clean` | 清理构建产物与临时文件 |

## 许可与来源

仓库代码、文档及自维护规则采用 [MIT License](LICENSE) 授权。上游数据及其派生产物遵循各自原有许可，详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
