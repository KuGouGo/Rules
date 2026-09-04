# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

为 Surge、Quantumult X、Egern、sing-box、mihomo 自动构建域名与 IP 分流规则集。上游数据每日聚合一次，经过规范化、去重和多层校验后发布到五个产物分支，可以直接订阅。

`main` 分支只有构建源码，没有可直接订阅的规则文件，请订阅下面的产物分支。

## 订阅

| 客户端 | 分支 | 格式 |
| --- | --- | --- |
| Surge | [`surge`](https://github.com/KuGouGo/Rules/tree/surge) | `.list` |
| Quantumult X | [`quanx`](https://github.com/KuGouGo/Rules/tree/quanx) | `.list` |
| Egern | [`egern`](https://github.com/KuGouGo/Rules/tree/egern) | `.yaml` |
| sing-box | [`sing-box`](https://github.com/KuGouGo/Rules/tree/sing-box) | `.srs` |
| mihomo | [`mihomo`](https://github.com/KuGouGo/Rules/tree/mihomo) | `.mrs` |

订阅地址按这个模板拼（分支、类型、名字、后缀按上表替换）：

```
https://raw.githubusercontent.com/KuGouGo/Rules/{分支}/{domain|ip}/{名字}.{后缀}
```

想固定某个历史版本，把分支名换成当时的 commit SHA 就行。每个产物分支的 README 里有一张产物清单表，列出各列表和条目数，方便核对每天的数据变化。

<details>
<summary>五个客户端的最小配置示例</summary>

**Surge**

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT,no-resolve
```

**Quantumult X**

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=cn, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=cn-ip, force-policy=direct, enabled=true
```

**Egern**

```ini
[Rule]
RULE SET,https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml,DIRECT
RULE SET,https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml,DIRECT
```

**sing-box**（`route.rule_set` 数组项）

```json
{ "tag": "cn", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs" }
```

**mihomo**（`rule-providers` 条目）

```yaml
cn:
  type: http
  behavior: domain
  format: mrs
  url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/cn.mrs"
  interval: 86400
```

</details>

## 规则集

| 列表 | 内容 | 典型用途 |
| --- | --- | --- |
| `cn` | 中国域名超集（tld-cn + geolocation-cn） | 直连 |
| `geolocation-!cn` | 境外实体域名全集 | 走代理 |
| `geolocation-!cn@cn` | 境外实体中可在中国大陆直连的域名 | 放在 `geolocation-!cn` 之前直连 |
| `google` / `telegram` / `apple` | 对应服务的域名与 IP | 单独控制 |
| `fakeip-filter` | 需要直连的域名 | Fake-IP 模式放行 |
| `private` | 内网与保留地址 | 兜底直连 |

另外还有 `cloudflare`、`github`、`openai`、`category-ai-chat-!cn`、`google-gemini`、`speedtest`，以及 `apple@cn`、`google@cn`、`microsoft@cn`、`steam@cn` 这类服务细分列表（同样要前置直连）。

## 工作原理

上游数据每日聚合：域名主干来自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)，加上 ShellCrash 的 `fakeip-filter`；IP 侧多源合并中国列表（Clang.CN、APNIC、Loyalsoldier GeoIP、17mon/iPIP），google、telegram、cloudflare 等服务用官方源或 RIPEstat。数据经过规范化、去重和格式校验，按各客户端的原生格式渲染，守卫校验全部通过后五个分支整批原子推送，失败自动回滚。守卫设有最小条目数和体积下限，不达标直接中止构建，不会发布残缺数据。

## 本地构建

完整构建只支持 Linux（锁定的编译器只有 linux-amd64 / linux-arm64 的包）；其他平台用 GitHub Actions，或者 `make build-custom-text` 只构建文本产物。

| 命令 | 说明 |
| --- | --- |
| `make validate` | 全量 lint + 全部测试（和 CI 门禁一致） |
| `make build-custom` | 构建自定义规则与二进制产物（仅 Linux） |
| `make build-custom-text` | 只构建文本产物，不下载编译器 |
| `make clean` | 清理产物与临时文件 |

## 常见问题

**条目数每天波动正常吗？**
正常，上游数据每天都在变。

**为什么 Surge / QX 产物里缺某些规则？**
这两个平台不支持 `DOMAIN-REGEX` 一类的规则类型，构建时跳过；只含不支持类型的列表不会在该平台发布。

**`geolocation-!cn@cn` 与 `cn` 的顺序？**
`geolocation-!cn@cn` 必须放在 `geolocation-!cn` 之前；`cn` 和 `cn` IP 可以放更前面，参考产物分支 README 的示例。

**发现分流错误怎么反馈？**
先定位域名归属的上游列表（domain-list-community 对应文件或本仓库 `sources/custom/`），能改上游就去上游提修正；上游未收录且和分流明确相关的条目适合加进本仓库自定义列表。

## 贡献

加自定义规则：往 [`sources/custom/domain/`](sources/custom/domain) 添加列表（域名用 Surge classical 格式：`DOMAIN` / `DOMAIN-SUFFIX` / `DOMAIN-KEYWORD` / `DOMAIN-REGEX`）；IP 自定义先建 [`sources/custom/ip/`](sources/custom/ip) 目录，放入 `IP-CIDR` / `IP-CIDR6` 列表。构建会先做冲突和冗余检查，再渲染到五个平台。

改流水线代码：提交 PR 前跑 `make validate`，和 CI 门禁完全一致。

## 许可

仓库代码以 [MIT License](LICENSE) 授权；第三方数据及其派生内容遵循各自许可，来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [NOTICE](NOTICE)。
