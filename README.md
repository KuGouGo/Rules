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
| `cn` | 中国大陆直连域名 | 国内网站直连 |
| `geolocation-cn` / `geolocation-!cn` | 按地理归集的中国 / 非中国域名 | 直连或走代理 |
| `google` / `telegram` / `apple` | 对应服务的域名与 IP | 单独控制 |
| `fakeip-filter` | 需要直连的域名 | Fake-IP 模式放行 |
| `private` | 内网与保留地址 | 兜底直连 |

另含 `cloudflare`、`cloudfront`、`fastly` 等按服务划分的列表，及 `xxx@cn`、`xxx@!cn` 等属性派生集，可按需订阅。

## 架构

流水线由上游数据驱动：`上游获取 → 规范化 → 合并与派生 → 平台渲染 → 守卫校验 → 事务发布`。详见 [docs/architecture.md](docs/architecture.md)。

## 许可

仓库代码以 [MIT License](LICENSE) 授权；第三方数据及其派生内容遵循各自许可，来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [NOTICE](NOTICE)。
