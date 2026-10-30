# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

一套每天自动更新的分流规则，覆盖 Surge、Quantumult X、Egern、sing-box 和 mihomo。域名和 IP 从各自的上游取来，规范化、去重、校验之后，发布到五个可以直接订阅的分支。

`main` 上只有构建源码，订阅不了。规则在下面五个分支里。

## 订阅

| 客户端 | 分支 | 格式 |
| --- | --- | --- |
| Surge | [`surge`](https://github.com/KuGouGo/Rules/tree/surge) | `.list` |
| Quantumult X | [`quanx`](https://github.com/KuGouGo/Rules/tree/quanx) | `.list` |
| Egern | [`egern`](https://github.com/KuGouGo/Rules/tree/egern) | `.yaml` |
| sing-box | [`sing-box`](https://github.com/KuGouGo/Rules/tree/sing-box) | `.srs` |
| mihomo | [`mihomo`](https://github.com/KuGouGo/Rules/tree/mihomo) | `.mrs` |

地址按这个样子拼，换成你要的分支、类型、名字和后缀：

```
https://raw.githubusercontent.com/KuGouGo/Rules/{分支}/{domain|ip}/{名字}.{后缀}
```

每个分支的 README 里有一张清单，列出全部列表和当天的条目数，每天的增减从那里看。想钉住某一天的版本，把地址里的分支名换成那个提交的 SHA。

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
| `geolocation-!cn@cn` | 境外实体里在中国大陆可直连的域名 | 放在 `geolocation-!cn` 前面直连 |
| `google` / `telegram` / `apple` | 对应服务的域名与 IP | 单独控制 |
| `fakeip-filter` | 需要直连的域名 | Fake-IP 模式放行 |
| `private` | 内网与保留地址 | 兜底直连 |

google、microsoft、netflix、openai、telegram 这类主流境外服务各有自己的域名列表，一共 28 个；AI 服务另外收进 `category-ai-chat-!cn`。`apple@cn`、`google@cn`、`microsoft@cn`、`steam@cn` 是这些服务在大陆可直连的部分，要写在对应服务列表的前面，否则直连规则不会先生效。全部列表见产物分支的 README。

## 怎么构建的

每天定时跑一次，往 `main` 推送也会触发。域名主干取 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) 当天的 master，再补上 ShellCrash 的 `fakeip-filter`。`cn` 的 IP 由五个来源合并：APNIC、Clang.CN、gaoyifan/china-operator-ip、chnroutes2、17mon/iPIP。google、telegram、apple 的 IP 不维护静态段，按 `asn_groups` 从 [iptoasn.com](https://iptoasn.com/) 的 BGP 快照里提取，拿到的是这些 ASN 当时实际宣告的地址。

数据先规范化、去重，再过健康检查，条目数掉到阈值以下就中止，不会把一份残缺的规则推出去。之后渲染成各客户端的原生格式，二进制产物用 sing-box 和 mihomo 的官方编译器生成，校验通过后五个分支一次性推送。

编译器和 GitHub Actions 的版本每周一自动检查，有新版本就验证、提 PR、合并。

## 本地构建

完整构建只能在 Linux 上跑，因为编译器只提供 linux 包。其他系统用 GitHub Actions，或者 `make build-custom-rules-text` 只出文本产物。

| 命令 | 说明 |
| --- | --- |
| `make validate` | 全量 lint 加全部测试，和 CI 的门禁一致 |
| `make build-custom-rules` | 构建自定义规则和二进制产物，仅 Linux |
| `make build-custom-rules-text` | 只构建文本产物，不下载编译器 |
| `make clean` | 清掉产物和临时文件 |

编译器版本钉在 `scripts/lib/common.sh` 顶部，要换版本改那里。

## 仓库里有什么

```
sources/custom/     自己维护的规则，domain 用 Surge classical 格式，ip 用 IP-CIDR 列表
config/             上游源、发布策略这些声明式配置
scripts/commands/   流水线入口：sync-upstream → build-custom-rules → check-artifacts → publish-branches
scripts/lib/        构建用的公共函数，编译器版本钉在 common.sh 顶部
scripts/tools/      规范化、渲染、审计这些 Python 工具
templates/          五个产物分支的 README 模板
```

## 常见问题

**条目数每天都在变，正常吗？**
正常。上游每天都在改，条目数跟着动。

**为什么 Surge 和 Quantumult X 里少了些规则？**
这两个平台不支持 `DOMAIN-REGEX` 这类规则，构建时直接跳过。一个列表如果只剩这种规则，就不会在这两个平台发布。

**`geolocation-!cn@cn` 和 `cn` 谁写前面？**
`geolocation-!cn@cn` 必须放在 `geolocation-!cn` 前面，不然直连部分会被代理规则先匹配走。`cn` 和 `cn` 的 IP 可以再往前放，产物分支的 README 里有示例。

**分流错了怎么反馈？**
先看这个域名属于哪个上游列表，是 domain-list-community 的某个文件，还是本仓库 `sources/custom/` 里的。能改上游就去上游提。上游没收录、又确实影响分流的，加进本仓库的自定义列表。

## 许可

仓库代码用 [MIT License](LICENSE)。第三方数据及其派生内容仍遵循各自的许可，来源和范围见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
