# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

为 Surge、Quantumult X、Egern、sing-box、mihomo 自动构建域名与 IP 分流规则集。
上游数据每日聚合，经规范化、去重与多层校验后，发布到各产物分支供直接订阅。

## 订阅

| 客户端 | 分支 | 格式 |
| --- | --- | --- |
| Surge | [`surge`](https://github.com/KuGouGo/Rules/tree/surge) | `.list` |
| Quantumult X | [`quanx`](https://github.com/KuGouGo/Rules/tree/quanx) | `.list` |
| Egern | [`egern`](https://github.com/KuGouGo/Rules/tree/egern) | `.yaml` |
| sing-box | [`sing-box`](https://github.com/KuGouGo/Rules/tree/sing-box) | `.srs` |
| mihomo | [`mihomo`](https://github.com/KuGouGo/Rules/tree/mihomo) | `.mrs` |

订阅地址模板（把 `{分支}`、`{domain|ip}`、`{名字}`、`{后缀}` 按上表替换）：

```
https://raw.githubusercontent.com/KuGouGo/Rules/{分支}/{domain|ip}/{名字}.{后缀}
```

> [!IMPORTANT]
> 请订阅**产物分支**。`main` 是构建源码，不含可直接订阅的规则文件。
> 每个产物分支的 README 附有产物清单表（各列表与条目数），便于核对数据变化。

<details>
<summary><strong>五客户端最小配置示例</strong></summary>

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
| `cn` | 中国域名超集（= tld-cn + geolocation-cn） | 直连 |
| `geolocation-!cn` | 境外实体域名全集 | 走代理 |
| `geolocation-!cn@cn` | 境外实体中可在中国大陆直连的域名 | **放在 `geolocation-!cn` 之前**直连 |
| `google` / `telegram` / `apple` | 对应服务的域名与 IP | 单独控制 |
| `fakeip-filter` | 需要直连的域名 | Fake-IP 模式放行 |
| `private` | 内网与保留地址 | 兜底直连 |

另含 `cloudflare`、`github`、`openai`、`category-ai-chat-!cn`、`google-gemini`、`speedtest`
以及 `apple@cn`、`google@cn`、`microsoft@cn`、`steam@cn` 等服务细分（同样前置直连）。

**发布范围**由 [`config/domain-publish-policy.json`](config/domain-publish-policy.json) 控制：

- `common`（默认）：中国域名只发布 `cn` 一个超集入口（覆盖 `geolocation-cn` 与 `tld-cn`），境外服务发布精选列表。
- `extended`：额外恢复旧兼容名称与大型分类列表。
- 构建时验证替代名称的规则覆盖完整，旧名只在 extended 下发布。

## 工作原理

```
上游获取 → 规范化与合并 → 平台渲染 → 守卫校验 → 事务发布（五分支原子推送）
```

- **上游获取** —— 来源与健康策略（最小条目数、最小体积、地址族）声明于 [`config/upstreams.json`](config/upstreams.json)。域名主干 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) + ShellCrash `fakeip-filter`；IP 侧为 Clang.CN 双栈中国列表 + APNIC 基线、[Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip) CN 前缀与 [17mon/china_ip_list](https://github.com/17mon/china_ip_list)（iPIP 实用地理数据，补齐注册表视角外的中国实用段如阿里 ARIN 注册的 8.x）多源最优合并、google / telegram / cloudflare / cloudfront / fastly 官方源、RIPEstat 按 ASN 拉取。本地来源在 [`sources/custom/`](sources/custom) 与 [`sources/builtin/`](sources/builtin)。

- **上游锁定** —— DLC 的消费提交钉定于 [`config/upstream-pins.json`](config/upstream-pins.json)：每日工作流对比上游 HEAD，有差异自动开 PR，**人工审核合并后**才进入构建。紧急排查可设 `RULES_UPSTREAM_FLOAT=1` 临时漂移到上游 HEAD。

- **规范化与合并** —— 统一大小写与 punycode（IDNA）表示，按 `DOMAIN` / `DOMAIN-SUFFIX` 超集折叠去重；DLC include 树完整解析，`@cn` 聚合为 `geolocation-!cn@cn`，`@ads` 收敛为单一 `category-ads-all`。补充来源只做增量合并，不改写 DLC 路由语义。

- **平台渲染** —— 按能力矩阵（[`config/domain-platform-capabilities.json`](config/domain-platform-capabilities.json)）映射为各平台原生格式；不支持的规则类型（如 Surge / QX 的 `DOMAIN-REGEX`）跳过并汇总。二进制产物按输入摘要、格式版本与编译器摘要缓存。

- **守卫与发布** —— 产物数量、CIDR 地址族、必需派生集、内部冗余、平台解码（sing-box 反编译 / mihomo MRS 读回）全部通过后，在临时目录构建、原子替换产物，五个分支整批 `--force-with-lease` 推送，失败自动回滚。

- **可复现与供应链** ——
  - 编译器版本与哈希锁定于 [`config/tools-lock.json`](config/tools-lock.json)，下载后记录 provenance；
  - 依赖更新用 `gh attestation verify` 对照上游 artifact attestation 独立验证（无 attestation 的上游如实记录 `unavailable`）；
  - 依赖 PR 仅在 Validation 通过、且 head SHA 携带 `dependency-update-validation` 状态标记后才被自动合并；
  - `.srs` / `.mrs` 产物有逐字节金样测试，编译输出漂移立即暴露。

## 本地构建

完整构建（含二进制编译）**仅支持 Linux**（锁定编译器只提供 linux-amd64 / linux-arm64）；其他平台用 GitHub Actions，或 `make build-custom-text` 只构建文本产物。

| 命令 | 说明 |
| --- | --- |
| `make check` | 快速语法与配置检查 |
| `make validate` | 全量 lint + 全部测试（与 CI 门禁一致） |
| `make build-custom` | 构建自定义规则与二进制产物 |
| `make build-custom-text` | 只构建文本产物（无需下载编译器） |
| `make clean` | 清理产物与临时文件 |

<details>
<summary>常用环境变量</summary>

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `RULES_BUILD_SCOPE` | `full` | `full` 同步上游后构建；`custom` 仅基于已有产物重构建自定义规则 |
| `DOMAIN_PUBLISH_PROFILE` | policy 默认 | `common` / `extended` |
| `RULES_BUILD_CUSTOM_TEXT_ONLY` | 未设置 | `1` 时跳过二进制编译 |
| `RULES_COMPILE_JOBS` | 自动探测（≤4） | 二进制编译并行度 |
| `SURGE_IP_APPEND_NO_RESOLVE` | `1` | Surge IP 规则附加 `no-resolve`；`0` 用于 A/B 对比 |
| `SINGBOX_RULE_SET_VERSION` | 按编译器探测 | 覆盖 `.srs` 源格式版本 |
| `RULES_UPSTREAM_FLOAT` | 未设置 | `1` 时忽略上游 pin，构建上游 HEAD |
| `RULES_LIVE_ARTIFACT_ROOT` | `.output` | 事务提升目标目录 |
| `RULES_ARTIFACT_DIAGNOSTICS_ROOT` | `.artifacts/diagnostics` | 失败诊断输出目录 |
| `RULES_COMPILE_CACHE_ROOT` | `.cache/compiled-rules` | 二进制编译缓存目录 |

</details>

每次构建写入 `.output/build-timings.json`（上游同步 / 自定义构建 / 重叠审计 / 守卫 / manifest 各阶段耗时），用于跟踪性能退化。

## 常见问题

**如何固定在某个历史版本？**
把订阅 URL 中的分支名换成具体 commit SHA 即可（产物分支每次发布都是单提交，任意 SHA 可回溯）。

**条目数每天波动正常吗？**
正常，上游数据每日变化。守卫设有最小条目数与体积下限，不达标直接中止构建而非发布残缺数据。

**为什么 Surge / QX 产物里缺某些规则？**
能力矩阵跳过了平台不支持的类型（如 `DOMAIN-REGEX`）；仅含不支持类型的列表不会在该平台发布。

**为什么不把 dnsmasq 系大列表（如 Loyalsoldier direct-list）合并进 `cn` 域名列表？**
这类列表面向 **DNS 分流**（判断域名是否走国内解析），内容是"解析视角"而非"路由视角"，不保证直连正确性；`cn` 域名列表保持 DLC 人工策展。未命中域名列表的国内站点由 **`cn` IP 兜底**：把 `ip/cn` 规则放在 MATCH 之前且不带 `no-resolve`（Surge 去掉 `no-resolve` 参数，其余客户端放行解析即可），客户端会先解析再按落地 IP 判定直连。默认示例带 `no-resolve` 是为了避免域名请求触发额外解析，按需取舍。

**`geolocation-!cn@cn` 与 `cn` 的顺序？**
`geolocation-!cn@cn` 必须放在 `geolocation-!cn` **之前**；`cn` 及 `cn` IP 可在其前，参考产物分支 README 的示例。

**发现分流错误怎么反馈？**
先定位域名归属的上游列表（domain-list-community 对应文件或本仓库 `sources/custom/`），到对应上游提修正；上游未收录且与分流明确相关的条目适合加入本仓库自定义列表。

## 贡献

- **加自定义规则**：向 [`sources/custom/domain/`](sources/custom/domain) 添加列表（域名用 Surge classical 格式：`DOMAIN` / `DOMAIN-SUFFIX` / `DOMAIN-KEYWORD` / `DOMAIN-REGEX`）；IP 自定义创建 [`sources/custom/ip/`](sources/custom/ip) 目录后放入 `IP-CIDR` / `IP-CIDR6` 列表。构建会先 lint（冲突、冗余、格式），再渲染到五个平台。
- **改流水线代码**：提交 PR 前跑 `make validate`，与 CI 门禁完全一致。
- **上游数据变更**：DLC pin 由每日工作流自动提议、人工合并，通常无需手改。

## 许可

仓库代码以 [MIT License](LICENSE) 授权；第三方数据及其派生内容遵循各自许可，来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [NOTICE](NOTICE)。
