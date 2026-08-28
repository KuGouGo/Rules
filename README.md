# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

面向 Surge、Quantumult X、Egern、sing-box、mihomo 五种客户端的域名与 IP 规则集。流水线自动聚合上游数据，经规范化、去重、渲染与校验后，发布到各产物分支供直接订阅。

## 特性

- **每日自动同步**：`main` 分支推送即构建，并每日定时刷新上游数据。
- **可复现构建**：sing-box / mihomo 版本与哈希锁定，同一提交产出确定一致的规则文件；二进制产物另有金样校验。
- **上游数据锁定**：domain-list-community 的消费提交经人工审核后才进入构建，上游投毒无法直接生效。
- **多层守卫**：上游健康校验、产物数量与 CIDR 有效性检查，异常即中止，不发布损坏数据。
- **原子发布**：产物校验通过后整批覆盖发布到五个平台分支，失败自动回滚。

## 快速开始

按客户端订阅对应分支：

| 客户端 | 分支 | 格式 |
| --- | --- | --- |
| Surge | [`surge`](https://github.com/KuGouGo/Rules/tree/surge) | `.list` |
| Quantumult X | [`quanx`](https://github.com/KuGouGo/Rules/tree/quanx) | `.list` |
| Egern | [`egern`](https://github.com/KuGouGo/Rules/tree/egern) | `.yaml` |
| sing-box | [`sing-box`](https://github.com/KuGouGo/Rules/tree/sing-box) | `.srs` |
| mihomo | [`mihomo`](https://github.com/KuGouGo/Rules/tree/mihomo) | `.mrs` |

订阅地址：`https://raw.githubusercontent.com/KuGouGo/Rules/{分支}/{domain|ip}/{名字}.{后缀}`

每个分支的 README 附有**产物清单表**（各列表及条目数），条目数变化即代表数据实际发生了变化。

> [!IMPORTANT]
> 请订阅**产物分支**；`main` 分支为构建源，不含可直接订阅的规则文件。

<details>
<summary>五个客户端的配置示例</summary>

**Surge**

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/geolocation-!cn@cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/geolocation-!cn.list,PROXY
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT,no-resolve
FINAL,PROXY
```

**Quantumult X**

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/geolocation-!cn@cn.list, tag=cn-cdn, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=cn, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/geolocation-!cn.list, tag=proxy, force-policy=proxy, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=cn-ip, force-policy=direct, enabled=true
```

**Egern**

```ini
[Rule]
RULE SET,https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml,DIRECT
RULE SET,https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/geolocation-!cn.yaml,PROXY
RULE SET,https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml,DIRECT
FINAL,PROXY
```

**sing-box**

```json
{
  "route": {
    "rule_set": [
      { "tag": "geolocation-!cn@cn", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/geolocation-!cn@cn.srs" },
      { "tag": "cn", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs" },
      { "tag": "geolocation-!cn", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/geolocation-!cn.srs" },
      { "tag": "cn-ip", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/cn.srs" }
    ],
    "rules": [
      { "rule_set": ["geolocation-!cn@cn", "cn", "cn-ip"], "outbound": "direct" },
      { "rule_set": ["geolocation-!cn"], "outbound": "proxy" }
    ]
  }
}
```

**mihomo**

```yaml
rule-providers:
  geolocation-!cn@cn:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/geolocation-!cn@cn.mrs"
    interval: 86400
  cn:
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

rules:
  - RULE-SET,geolocation-!cn@cn,DIRECT
  - RULE-SET,cn,DIRECT
  - RULE-SET,cn-ip,DIRECT
  - MATCH,PROXY
```

</details>

## 规则集

| 列表 | 内容 | 用途 |
| --- | --- | --- |
| `cn` | 中国域名超集（= tld-cn + geolocation-cn） | 直连 |
| `geolocation-!cn` | 境外实体域名全集 | 走代理 |
| `google` / `telegram` / `apple` | 对应服务的域名与 IP | 单独控制 |
| `fakeip-filter` | 需要直连的域名 | Fake-IP 模式放行 |
| `private` | 内网与保留地址 | 兜底直连 |

另含 `cloudflare`、`github`、`openai`、`category-ai-chat-!cn`、`google-gemini`、`speedtest` 等常用服务列表。每个产物分支的 README 列出该平台实际发布的全部列表与条目数。

`geolocation-!cn@cn` 聚合境外实体中可在中国大陆直连的域名（CDN/接入点），应放在 `geolocation-!cn` 之前匹配；`apple@cn`、`google@cn`、`microsoft@cn`、`steam@cn` 为对应服务的同型细分，同样前置直连。

### 发布范围

- `common`：默认范围。中国域名只发布 `cn` 超集；常用境外服务与精选工具列表单独发布。
- `extended`：恢复旧兼容名称与大型分类列表。
- `auto`：使用 [`config/domain-publish-policy.json`](config/domain-publish-policy.json) 中的默认 profile，目前为 `common`。

`cn` 在 DLC 上游由 `tld-cn + geolocation-cn` 组成，因此只发布 `cn` 一个超集入口；`geolocation-cn`/`tld-cn` 不再单独发布（订阅 `cn` 即覆盖两者）。旧名称会在构建时验证其规则仍被 common 中的替代名称完整覆盖，extended 发布时还会校验兼容入口存在。

> [!TIP]
> `geolocation-!cn@cn` 表示境外实体中可在中国大陆访问的域名。使用时应放在 `geolocation-!cn` 之前匹配。

## 架构

流水线由上游数据驱动：`上游获取 → 规范化 → 合并与派生 → 平台渲染 → 守卫校验 → 事务发布`。

### 上游获取

来源在 [`config/upstreams.json`](config/upstreams.json) 声明，并为每个来源配置健康策略（最小条目数、最小体积、地址族），拦截空响应与截断数据。域名主干为 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（克隆后先过数据审计）+ ShellCrash `fakeip-filter`；IP 侧中国 IP 用 Clang.CN 完整双栈列表并合并 APNIC 基线，另有 google / telegram / cloudflare / cloudfront / fastly 及内置 Apple 源，RIPEstat 按 ASN 拉取前缀。本地来源为 `sources/custom/` 与 `sources/builtin/`。

domain-list-community 的消费提交锁定在 [`config/upstream-pins.json`](config/upstream-pins.json)：每日工作流对比上游 HEAD 与锁定值，有差异时自动开 PR，由人工审核后合并——上游投毒或意外变更必须先过这道人工门禁才能进入构建。紧急排查时可设 `RULES_UPSTREAM_FLOAT=1` 临时漂移到上游 HEAD。

### 规范化与合并

统一大小写与书写形式，按 `DOMAIN` / `DOMAIN-SUFFIX` 超集折叠去重。DLC include 树完整解析后，按 profile 选入口发布，未单独发布的子表仍参与聚合。`cn` = `tld-cn + geolocation-cn`，只发布 `cn` 一个超集入口；`@cn` 聚合为 `geolocation-!cn@cn`。common 保留面向用户的名称（如 `category-ai-chat-!cn`、`google-gemini`），旧名仅在 extended 发布，导出器验证替代关系语义覆盖完整。`@ads` 仅参与基础过滤，ads 收敛为单一平坦产物 `category-ads-all`。独立补充来源只做增量合并，不改写 DLC 路由语义。

非 ASCII（Unicode）域名在入库时统一转换为 punycode（IDNA）表示，避免产出运行时永不匹配的规则。

### 平台渲染

规则类型按平台能力矩阵（[`config/domain-platform-capabilities.json`](config/domain-platform-capabilities.json)）映射为原生格式：Surge / Quantumult X 输出 `.list`，Egern 输出 `.yaml`，sing-box / mihomo 分别编译为 `.srs` / `.mrs`。平台不支持的规则类型（如 Surge / QX 的 `DOMAIN-REGEX`）跳过并汇总受影响列表数。二进制产物以规范化输入摘要、格式版本和编译器摘要缓存，CI 跨构建恢复并 SHA-256 校验，损坏时自动重编译。

### 守卫与发布

发布前检查产物数量、CIDR 地址族、必需派生集、列表内部冗余和平台解码（sing-box 反编译 / mihomo MRS 读回）。重叠报告只做候选发现，不自动合并具有独立订阅用途的列表。内部 manifest 固化 profile、输入摘要、工具来源和校验结果。构建在临时目录完成，验证成功后原子替换本地产物；发布时五个平台分支整批更新（分支只含 README、`domain/`、`ip/`），并用 `--force-with-lease` 防止覆盖并发发布。

### 可复现性与供应链

- **编译器锁定**：sing-box / mihomo 版本、归档与二进制哈希锁定于 [`config/tools-lock.json`](config/tools-lock.json)，下载后校验并记录 provenance，保证构建可复现。
- **独立信任锚**：依赖更新流程用 `gh attestation verify` 对照上游仓库的 GitHub artifact attestation 独立验证归档；对不发布 attestation 的上游（如 mihomo）在锁中如实记录 `unavailable`，此时哈希锚定的是下载产物本身。
- **合并门禁**：依赖更新 PR 只有在 Validation 通过、且 head SHA 带有 `dependency-update-validation` 状态标记后才会被自动合并；对分支的任何后续推送都无法继承旧提交的验证结果。
- **金样测试**：`.srs` / `.mrs` 产物对锁定的编译器版本做逐字节金样对比，编译输出漂移会在 CI 中立即暴露。

## 本地构建

完整构建（含 `.srs` / `.mrs` 编译）仅支持 Linux：锁定的编译器资产只提供 linux-amd64 / linux-arm64，其他平台请用 GitHub Actions，或在本机执行 `make build-custom-text` 只构建文本产物。

常用命令：

| 命令 | 说明 |
| --- | --- |
| `make check` | 快速语法与配置检查 |
| `make validate` | 全量 lint + 全部测试（PR 门禁同一套） |
| `make build-custom` | 构建自定义规则与二进制产物 |
| `make build-custom-text` | 只构建文本产物（不需要编译器） |
| `make clean` | 清理产物与临时文件 |

常用环境变量（`scripts/lib/` 与 `scripts/commands/` 内定义）：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `RULES_BUILD_SCOPE` | `full` | 构建范围：`full` 同步上游后构建；`custom` 仅基于已有产物重构建自定义规则 |
| `DOMAIN_PUBLISH_PROFILE` | policy 的 `default_profile` | 域名发布 profile：`common` / `extended` |
| `RULES_BUILD_CUSTOM_TEXT_ONLY` | 未设置 | 设为 `1` 时跳过二进制编译，只产出文本平台 |
| `RULES_COMPILE_JOBS` | 自动探测（上限 4） | 二进制编译并行度 |
| `SURGE_IP_APPEND_NO_RESOLVE` | `1` | Surge IP 规则是否附加 `no-resolve`；设为 `0` 做 A/B 对比 |
| `SINGBOX_RULE_SET_VERSION` | 按编译器版本探测 | 覆盖 `.srs` 源格式版本 |
| `RULES_UPSTREAM_FLOAT` | 未设置 | 设为 `1` 时忽略 `upstream-pins.json`，构建上游 HEAD |
| `RULES_LIVE_ARTIFACT_ROOT` | `.output` | 事务提升目标目录 |
| `RULES_ARTIFACT_DIAGNOSTICS_ROOT` | `.artifacts/diagnostics` | 失败诊断输出目录 |
| `RULES_COMPILE_CACHE_ROOT` | `.cache/compiled-rules` | 二进制编译缓存目录 |

每次构建写入 `.output/build-timings.json`，记录各阶段（上游同步、自定义构建、重叠审计、守卫、manifest）耗时，用于跟踪性能退化。

## 常见问题

**如何把规则固定在某个历史版本，不跟随自动更新？**
把订阅 URL 中的分支名替换为具体 commit SHA，例如 `https://raw.githubusercontent.com/KuGouGo/Rules/<commit-sha>/domain/cn.list`。产物分支每次发布都是单提交覆盖，任意历史 SHA 均可回溯。

**规则条目数为什么每天有波动？**
上游数据（domain-list-community、各家官方 IP 列表）每日变化，条目数随之波动是正常现象。守卫层设置了最小条目数与体积下限，低于健康阈值的上游会直接中止构建而不是发布残缺数据；每个产物分支 README 的清单表可用于粗查异常。

**为什么 Surge / Quantumult X 产物里没有某些列表或规则？**
能力矩阵会跳过平台不支持的规则类型（如两家的 `DOMAIN-REGEX`）。仅含不支持类型的列表不会在该平台发布，跳过量记录在构建日志与重叠审计报告中。

**`geolocation-!cn@cn` 和 `cn` 应该怎么排？**
`geolocation-!cn@cn`（境外实体的中国大陆直连部分）必须放在 `geolocation-!cn` 之前；`cn` 与 `cn` IP 列表可在其前。参考上文配置示例中的顺序。

**发现某个域名分流错误，如何反馈？**
先确认该域名归属哪个上游列表（domain-list-community 的对应文件或本仓库 `sources/custom/`），再到对应上游提修正；本仓库的自定义列表适合收录上游尚未收录、且与分流明确相关的条目。

## 贡献

- **加入自定义规则**：向 [`sources/custom/domain/`](sources/custom/domain) 或 [`sources/custom/ip/`](sources/custom/ip) 添加列表文件（域名用 Surge classical 格式：`DOMAIN` / `DOMAIN-SUFFIX` / `DOMAIN-KEYWORD` / `DOMAIN-REGEX`；IP 用 `IP-CIDR` / `IP-CIDR6`）。构建会先 lint（冲突、冗余、格式），再渲染到全部五个平台。
- **修改流水线代码**：提交 PR 前跑 `make validate`（与 CI 门禁完全一致，含 shellcheck 与锁定编译器的二进制校验）。
- **上游数据变更**：domain-list-community 的 pin 由每日工作流自动提议、人工合并，通常不需要手动编辑 `config/upstream-pins.json`。

## 许可

仓库代码以 [MIT License](LICENSE) 授权；第三方数据及其派生内容遵循各自许可，来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [NOTICE](NOTICE)。
