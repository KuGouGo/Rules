# 第三方声明

本文件记录当前已知第三方输入及截至 **2026-07-14** 的人工核对状态。它不是自动生成清单，也不是法律意见。`trust` 只表示采集来源分类；公开可访问、官方托管、注册机构提供或 CI 成功都不等于获得复制、修改或再分发授权。

标准 MIT License 位于 [`LICENSE`](LICENSE)，适用范围见 [`NOTICE`](NOTICE)。第三方材料不会因下载、规范化、合并、转换或编译而变为本仓库的 MIT 内容。

## 已确认的上游许可证

| 输入 | 来源 | 人工核对结果 | 说明 |
| --- | --- | --- | --- |
| `domain.dlc` | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) | MIT License，`Copyright (c) 2018-2019 V2Ray` | 上游 [LICENSE](https://raw.githubusercontent.com/v2fly/domain-list-community/master/LICENSE) 明确声明；再分发时仍需保留其版权与许可声明。 |

“已确认”只表示链接材料中存在明确许可证，不代表自动化验证了每次下载内容、上游全部依赖或具体使用方式。

## 许可或再分发权尚未确认

以下项目统一标记为“未知”。维护者必须在相关合并或发布前人工评审许可证、服务条款、数据来源和适用义务；脚本不会读取本表或据此自动阻断。

| 输入 | 来源 | 分类 | 人工核对状态 |
| --- | --- | --- | --- |
| `ip.cn-ipv46` | <https://ispip.clang.cn/all_cn_ipv46.txt> | `registry` | 未知；响应中未见明确数据许可证。 |
| `ip.loyalsoldier-geoip-cn`、`ip.loyalsoldier-geoip-private` | [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip) `release` 分支 | `community` | 未知；`master` 的 CC BY-SA 4.0 不能自动证明 `release` 聚合产物及全部来源适用相同许可。 |
| `ip.cn-ipv46-apnic` | <https://ispip.clang.cn/all_cn_ipv46_apnic.txt> | `registry` | 未知；名称提及 APNIC 不等于已获 APNIC 再分发授权。 |
| `ip.google` | <https://www.gstatic.com/ipranges/goog.json> | `official` | 未知；响应中未见独立数据许可证。 |
| `ip.telegram` | <https://core.telegram.org/resources/cidr.txt> | `official` | 未知；响应中未见独立数据许可证。 |
| `ip.cloudflare-ipv4`、`ip.cloudflare-ipv6` | <https://www.cloudflare.com/ips-v4>、<https://www.cloudflare.com/ips-v6> | `official` | 未知；未确认独立数据许可证。 |
| `ip.aws`（也生成 `cloudfront`） | <https://ip-ranges.amazonaws.com/ip-ranges.json> | `official` | 未知；响应中未见独立数据许可证。 |
| `ip.fastly` | <https://api.fastly.com/public-ip-list> | `official` | 未知；响应中未见独立数据许可证。 |
| `ip.github` | <https://api.github.com/meta> | `official` | 未知；未确认 Meta API 数据的独立再分发许可证。 |
| `ip.apple` | <https://support.apple.com/en-us/101555>（回退：<https://support.apple.com/zh-cn/101555>） | `official` | 未知；未确认页面中网络范围数据的独立再分发许可证。 |
| `ip.ripe-stat` | <https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS> | `registry` | 未知；未确认 API 响应和 ASN 查询所得前缀集合的再分发许可。 |

`asn_groups.telegram`、`asn_groups.netflix`、`asn_groups.spotify` 和 `asn_groups.disney` 只是 RIPEstat 查询参数分组，不是独立许可声明；所得结果沿用 `ip.ripe-stat` 的“未知”状态。组织名称和商标归各自权利人所有。

## Fake-IP 迁移说明

当前 `fakeip-filter` 是 KuGouGo 在 `sources/custom/domain/fakeip-filter.list` 维护的仓库源码，由自定义构建生成各平台文本产物以及 sing-box、mihomo 二进制产物；它不属于第三方输入，也不下载第三方预编译文件。

本仓库过去曾直接采用 `wwqgtxx/clash-rules` 的预编译 `release/fakeip-filter.mrs`。该来源仅记录历史迁移背景，不是当前网络输入、构建步骤或发布材料；当前产物不得据此归因于该项目。

## 审计与评审边界

- `config/upstreams.json` 覆盖主上游规则网络输入；工具资产下载另由工具 lock 控制。当前没有 Fake-IP 网络输入或独立同步步骤。
- `.output/upstream-summary.json` 只覆盖主同步记录，不覆盖本仓库自定义源（包括 `fakeip-filter`）、完整转换链、提交身份或内容校验和，因此不是完整来源追溯记录。
- `.output/build-summary.json` 由成功构建事务在产物守卫后生成并受 manifest 摘要绑定；它只说明事务产物统计，不证明来源或授权。
- 当前自动化不解析 `NOTICE` 或本文件，不验证第三方许可，也不会因“未知”状态自动失败。
- 新增、更换或改变第三方输入时，应同步更新本文件并提供可核验依据；无法确认时保持“未知”，由维护者人工决定停止、替换、取得授权或满足适用义务后再发布。

## 文档导航

- [`README.md`](README.md)：用户入口、平台示例和关键边界
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：贡献规则与人工评审清单
- [`docs/README.md`](docs/README.md)：文档职责与阅读路径
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)：环境、命令和开发流程
- [`docs/STRUCTURE.md`](docs/STRUCTURE.md)：构建、产物、守卫和发布结构
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)：常见失败与定位步骤
- [`SECURITY.md`](SECURITY.md)：安全支持范围和私密报告
- [`NOTICE`](NOTICE) / [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)：许可范围与第三方状态
