# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/pull-request.yml"><img alt="Pull Request Validation" src="https://github.com/KuGouGo/Rules/actions/workflows/pull-request.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-4b5563">
</p>

面向 **Surge、Quantumult X、Egern、sing-box 和 mihomo** 的多平台规则构建仓库。仓库维护少量原创规则，并同步第三方数据，经规范化、转换和编译后发布到五个平台分支。

> [!IMPORTANT]
> `main` 保存源码和构建逻辑，不是规则下载分支。客户端应引用 `surge`、`quanx`、`egern`、`sing-box` 或 `mihomo`。MIT 许可的适用范围及第三方边界见 [`NOTICE`](NOTICE) 和 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 快速选择

| 需求 | 规则 | 类型 | 注意事项 |
| --- | --- | --- | --- |
| 中国大陆域名 | `cn` 或 `geolocation-cn` | domain | 两者沿用不同上游语义，不是同义别名 |
| 非中国大陆域名 | `geolocation-!cn` | domain | `!cn` 是上游名称的一部分 |
| 中国大陆 IP | `cn` | ip | 合并多个已配置来源并规范化为 CIDR |
| Google / Telegram IP | `google` / `telegram` | ip | Telegram 还会合并配置的 ASN 前缀 |
| Emby 中国大陆细分 | `emby-cn` | domain | 必须放在 `emby` 前面 |
| 通用 Emby | `emby` | domain | 包含较宽泛的后缀和关键词 |

上游列表名称会随上游演进。使用前请在目标发布分支的 `domain/` 或 `ip/` 目录确认文件存在；构建摘要和结构清单不随发布分支分发。

## 稳定 URL 模板

```text
https://raw.githubusercontent.com/KuGouGo/Rules/{branch}/{type}/{name}.{extension}
```

| 分支 | domain | ip |
| --- | --- | --- |
| `surge` | `{name}.list` | `{name}.list` |
| `quanx` | `{name}.list` | `{name}.list` |
| `egern` | `{name}.yaml` | `{name}.yaml` |
| `sing-box` | `{name}.srs` | `{name}.srs` |
| `mihomo` | `{name}.mrs` | `{name}.mrs` |

五个平台的可用 URL 示例：

```text
https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/emby-cn.list
https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml
https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs
https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/google.mrs
```

发布分支 URL 会随更新改变内容，不是固定快照。需要可复现内容时请把 URL 中的分支替换为具体提交 SHA。

## 五平台接入示例

示例策略仅用于展示，请替换为客户端中真实存在的策略或出站标签，并保持规则顺序。

### Surge

Surge 产物为 classical rule-set；IP 规则默认带 `no-resolve`。

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/emby-cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/emby.list,Emby
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```

### Quantumult X

Quantumult X 产物使用 `HOST`、`HOST-SUFFIX`、`HOST-KEYWORD`、`IP-CIDR` 和 `IP6-CIDR`。构建器把规则名写入第三字段；使用 `filter_remote` 时应通过 `force-policy` 绑定本地策略。

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/emby-cn.list, tag=Emby-CN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/emby.list, tag=Emby, force-policy=Emby, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```

### Egern

Egern 产物为 YAML 规则集。域名按内容写入对应集合，IP 写入 IPv4/IPv6 CIDR 集合并设置 `no_resolve: true`。

```text
https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/emby-cn.yaml
https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/emby.yaml
https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml
```

在 Egern 中添加远程规则集，再绑定本地策略。仓库只保证生成的数据结构，不提供完整客户端配置。

### sing-box

sing-box 产物是 `sing-box rule-set compile` 生成的二进制 `.srs`。以下仅为展示远程规则集引用关系的概念片段，不是可直接使用的完整配置。

```json
{
  "route": {
    "rules": [
      { "rule_set": ["emby-cn"], "outbound": "direct" },
      { "rule_set": ["emby"], "outbound": "proxy" },
      { "rule_set": ["cn-ip"], "outbound": "direct" }
    ],
    "rule_set": [
      {
        "tag": "emby-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/emby-cn.srs"
      },
      {
        "tag": "emby",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/emby.srs"
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

字段可能随 sing-box 版本演进，请以所用版本的官方 schema 为准。

### mihomo

mihomo 只发布二进制 `.mrs`。domain provider 使用 `behavior: domain`，IP provider 使用 `behavior: ipcidr`。

```yaml
rule-providers:
  emby-cn:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/emby-cn.mrs
    path: ./ruleset/emby-cn.mrs
    interval: 86400
  emby:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/emby.mrs
    path: ./ruleset/emby.mrs
    interval: 86400
  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/cn.mrs
    path: ./ruleset/cn-ip.mrs
    interval: 86400
rules:
  - RULE-SET,emby-cn,DIRECT
  - RULE-SET,emby,Emby
  - RULE-SET,cn-ip,DIRECT,no-resolve
```

## 平台能力与降级

| 平台 | 精确域名 | 后缀 | 关键词 | 正则 | IP CIDR | 当前转换边界 |
| --- | :---: | :---: | :---: | :---: | :---: | --- |
| Surge | ✓ | ✓ | ✓ | — | ✓ | 不写入域名正则 |
| Quantumult X | ✓ | ✓ | ✓ | — | ✓ | 转换为 `HOST*`；不写入域名正则 |
| Egern | ✓ | ✓ | ✓ | ✓ | ✓ | 保留四类域名规则 |
| sing-box | ✓ | ✓ | ✓ | ✓ | ✓ | 编译为 `.srs` |
| mihomo | ✓ | ✓ | — | — | ✓ | domain `.mrs` 仅保留精确域名与后缀 |

`—` 只表示当前转换链路未保留，不表示客户端本身不支持。若源列表仅含目标平台不保留的类型，该平台可能不发布对应空产物。

## 规则语义

- `name@cn`、`name@!cn`、`name@ads` 是按上游属性派生的集合；`@!cn` 不是布尔取反。
- `*-cn` 和 `*-!cn` 保留上游区域列表命名；明显冗余的属性派生不会发布。
- `official`、`registry`、`community` 只是采集来源分类，不是质量等级或许可结论。
- `emby-cn` 与 `emby` 当前有三条经审核并逐条锁定的覆盖关系。采用首条命中时必须先加载 `emby-cn`，再加载 `emby`。

## 更新、构建与审计边界

- `Sync Rules` 每天 08:00 UTC 完整同步；也支持手动选择构建范围。
- `main` 的相关实现、配置或自定义源变更会触发构建；纯文档变更不在 `push.paths` 中。
- 自定义范围会恢复发布分支产物后重建自定义规则；完整范围会同步全部已配置上游。
- `fakeip-filter` 当前由本仓库在 `sources/custom/domain/fakeip-filter.list` 维护，并与其他自定义规则一起生成 Surge、Quantumult X、Egern 文本产物及 sing-box、mihomo 二进制产物；构建不再下载第三方预编译文件。
- 过去曾直接采用 `wwqgtxx/clash-rules` 的预编译 `fakeip-filter.mrs`；该路径仅属历史，不是当前输入或构建步骤。
- `.output/upstream-summary.json` 由主上游同步生成，只是部分采集摘要；本仓库维护的自定义源（包括 `fakeip-filter`）、完整转换链、提交身份和内容校验和不在其中，因此它不是完整来源追溯记录。
- `.output/domain/rule-manifest.json` 描述域名列表和属性派生结构。
- `.output/build-summary.json` 由成功的构建事务在产物守卫之后、manifest 之前生成，并由 manifest 绑定文件摘要与嵌入内容；独立运行 `make build-custom*` 不会生成它。
- 摘要和结构清单都不是许可证证明，也不进入客户端发布分支。

## 校验的实际范围

`make validate` 执行 Shell 语法、可用时的 ShellCheck、Python 编译、配置、自定义规则和测试检查。CI 强制要求 ShellCheck。

产物守卫（artifact guard）检查产物最低数量、域名派生形状、部分文本域名产物的下降、Surge/Quantumult X 文本 IP 的 CIDR 与非公网地址、部分内置 IP 集最低数量及其 Surge 基线波动。它不对所有二进制内容执行等价语义检查。

自定义名称冲突检查发生在构建阶段，仅针对相对基准提交**新加入**的自定义源，并在同一 `domain` 或 `ip` 类型内检查五个平台当前 `.output/` 路径；既有自定义源的修改不会经过同一“新增名称”判断，domain 与 ip 同名也不互相冲突。

许可核验完全依赖维护者人工评审。脚本不会解析 `NOTICE` 或 `THIRD_PARTY_NOTICES.md`，未知许可也不会被 CI 自动识别或阻断。CI 通过不能视为已取得授权。

## 本地开发

支持目标是 GitHub Actions 的 Ubuntu 环境，以及具备 Bash、GNU Make、Git、Python 3、curl 和常用 GNU 工具的 Linux/WSL。脚本可识别非 Windows 的 `amd64` 与 `arm64` 二进制工具资产；原生 Windows 在需要下载新工具时会被明确拒绝，完整二进制构建不属于支持组合，其他环境组合也不作保证。

```bash
make help
make validate
make build-custom-text
make build-custom
make preflight
make clean
```

`make build-custom-text` 不下载二进制编译器；`make preflight` 也不执行完整上游同步、产物守卫（artifact guard）或发布。完整构建只接受 `config/tools-lock.json` 固定的版本、tag commit、Linux 资产名和 SHA-256；归档在解包前校验，`.bin/` 命中还会复核原子写入的 provenance、二进制 SHA-256 与版本探针。`make clean` 删除 `.tmp/`、`.output/`、Python 缓存和未完成的工具临时文件，但保留已验证的工具缓存。

自定义域名源位于 `sources/custom/domain/*.list`，支持 `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD` 和 `DOMAIN-REGEX`。可选 IP 源位于 `sources/custom/ip/*.list`，支持 `IP-CIDR` 和 `IP-CIDR6`；目录可不存在。文件名只使用小写字母、数字和连字符。

## 许可与风险

标准 MIT License 位于 [`LICENSE`](LICENSE)，适用范围说明位于 [`NOTICE`](NOTICE)。第三方来源及人工核对状态见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。格式转换、合并或编译不会把第三方材料重新许可为 MIT；“官方来源”、公开 URL、摘要记录或构建成功也不代表获得再分发授权。

规则按现状提供，不保证完整、实时、无误或适合特定用途。部署前请审查规则并保留回滚方案。本说明不是法律意见。

## 文档导航

- [`README.md`](README.md)：用户入口、平台示例和关键边界
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：贡献规则与人工评审清单
- [`docs/README.md`](docs/README.md)：文档职责与阅读路径
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)：环境、命令和开发流程
- [`docs/STRUCTURE.md`](docs/STRUCTURE.md)：构建、产物、守卫和发布结构
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)：常见失败与定位步骤
- [`SECURITY.md`](SECURITY.md)：安全支持范围和私密报告
- [`NOTICE`](NOTICE) / [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)：许可范围与第三方状态
