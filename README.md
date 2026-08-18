# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

面向 Surge、Quantumult X、Egern、sing-box、mihomo 五种客户端的域名与 IP 规则集。流水线自动聚合上游数据，经规范化、去重、渲染与校验后，发布到各产物分支供直接订阅。

## 特性

- **每日自动同步**：`main` 分支推送即构建，并每日定时刷新上游数据。
- **可复现构建**：sing-box / mihomo 版本与哈希锁定，同一提交产出确定一致的规则文件。
- **多层守卫**：上游健康校验、产物数量与 CIDR 有效性检查，异常即中止，不发布损坏数据。
- **原子发布**：产物校验通过后整批覆盖发布，失败自动回滚。

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

> [!IMPORTANT]
> 请订阅**产物分支**；`main` 分支为构建源，不含可直接订阅的规则文件。

<details>
<summary>配置示例</summary>

**Surge**

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```

**sing-box**

```json
{
  "route": {
    "rule_set": [
      { "tag": "cn", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs" }
    ]
  }
}
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

另含 `cloudflare`、`github`、`openai`、`category-ai-chat-!cn`、`google-gemini`、`speedtest` 等常用服务列表。

`geolocation-!cn@cn` 聚合境外实体中可在中国大陆直连的域名（CDN/接入点），应放在 `geolocation-!cn` 之前匹配；`apple@cn`、`google@cn`、`microsoft@cn`、`steam@cn` 为对应服务的同型细分，同样前置直连。

### 发布范围

- `common`：默认范围。中国域名只发布 `cn` 超集；常用境外服务与精选工具列表单独发布。
- `extended`：恢复旧兼容名称与大型分类列表。
- `auto`：使用 [`config/domain-publish-policy.json`](config/domain-publish-policy.json) 中的默认 profile，目前为 `common`。

`cn` 在 DLC 上游由 `tld-cn + geolocation-cn` 组成，因此只发布 `cn` 一个超集入口；`geolocation-cn`/`tld-cn` 不再单独发布（订阅 `cn` 即覆盖两者）。旧名称会在构建时验证其规则仍被 common 中的替代名称完整覆盖。

> [!TIP]
> `geolocation-!cn@cn` 表示境外实体中可在中国大陆访问的域名。使用时应放在 `geolocation-!cn` 之前匹配。

## 架构

流水线由上游数据驱动：`上游获取 → 规范化 → 合并与派生 → 平台渲染 → 守卫校验 → 事务发布`。

### 上游获取

来源在 [`config/upstreams.json`](config/upstreams.json) 声明，并为每个来源配置健康策略（最小条目数、最小体积、地址族），拦截空响应与截断数据。域名主干为 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（克隆后先过数据审计）+ ShellCrash `fakeip-filter`；IP 侧中国 IP 用 Clang.CN 完整双栈列表并合并 APNIC 基线，另有 google / telegram / cloudflare / cloudfront / fastly 及内置 Apple 源，RIPEstat 按 ASN 拉取前缀。本地来源为 `sources/custom/` 与 `sources/builtin/`。

### 规范化与合并

统一大小写与书写形式，按 `DOMAIN` / `DOMAIN-SUFFIX` 超集折叠去重。DLC include 树完整解析后，按 profile 选入口发布，未单独发布的子表仍参与聚合。`cn` = `tld-cn + geolocation-cn`，只发布 `cn` 一个超集入口；`@cn` 聚合为 `geolocation-!cn@cn`。common 保留面向用户的名称（如 `category-ai-chat-!cn`、`google-gemini`），旧名仅在 extended 发布，导出器验证替代关系语义覆盖完整。`@ads` 仅参与基础过滤，ads 收敛为单一平坦产物 `category-ads-all`。独立补充来源只做增量合并，不改写 DLC 路由语义。

### 平台渲染

规则类型按平台能力矩阵映射为原生格式：Surge / Quantumult X 输出 `.list`，Egern 输出 `.yaml`，sing-box / mihomo 分别编译为 `.srs` / `.mrs`。平台不支持的规则类型跳过并汇总受影响列表数。二进制产物以规范化输入摘要、格式版本和编译器摘要缓存，CI 跨构建恢复并 SHA-256 校验，损坏时自动重编译。

### 守卫与发布

发布前检查产物数量、CIDR 地址族、必需派生集、列表内部冗余和平台解码。重叠报告只做候选发现，不自动合并具有独立订阅用途的列表。内部 manifest 固化 profile、输入摘要、工具来源和校验结果。构建在临时目录完成，验证成功后原子替换本地产物；发布时五个平台分支整批更新（分支只含 README、`domain/`、`ip/`）。

### 可复现性

sing-box / mihomo 版本、归档与二进制哈希锁定于 [`config/tools-lock.json`](config/tools-lock.json)，下载后校验并记录 provenance，保证构建可复现。

## 许可

仓库代码以 [MIT License](LICENSE) 授权；第三方数据及其派生内容遵循各自许可，来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [NOTICE](NOTICE)。
