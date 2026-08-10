# 架构

规则流水线把上游数据变成各客户端产物，流程如下：

```
上游获取 → 规范化 → 合并与派生 → 平台渲染 → 守卫校验 → 事务发布
```

## 上游获取

来源统一在 [`config/upstreams.json`](../config/upstreams.json) 中声明，并为每个来源配置健康策略（最小条目数、最小体积、地址族等），拦截空响应与截断数据。

- **域名**：[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（核心树；克隆后先过数据审计，硬性数据错误阻断构建）、ShellCrash `fakeip-filter`。
- **IP**：中国 IP 使用 Clang.CN 完整双栈列表，并与 APNIC 注册分配基线合并；其他上游包括 google、telegram、cloudflare、cloudfront（CloudFront CDN）、fastly，Apple IP 为内置自定义源，以及由 RIPEstat 按 ASN 拉取的前缀。
- **本地**：`sources/custom/` 自定义规则与 `sources/builtin/` 内置保留地址。

## 规范化与合并

- 统一大小写与书写形式，按 `DOMAIN` / `DOMAIN-SUFFIX` 超集折叠去重。
- DLC include 树先完整解析，再根据 profile 选择需要发布的入口；未单独发布的子表仍参与聚合。
- `cn` 由 `tld-cn + geolocation-cn` 组成，只发布 `cn` 一个超集入口；子表不再单独发布。
- `@cn` 规则聚合为 `geolocation-!cn@cn`，`@!cn` 规则并入 `geolocation-!cn`；两者分别用于大陆可达例外和默认境外路由。
- 未标属性但同时出现在两个地理根的精确规则归 `geolocation-cn`，并从 `geolocation-!cn` 基础表移除。
- common 中保留面向用户的名称，例如 `category-ai-chat-!cn`、`google-gemini`、`speedtest`；旧名称只在 extended 发布。导出器会验证替代关系仍保持完整语义覆盖。
- `@ads` 仅参与基础列表过滤（如 `cn` 剔除广告条目）；ads 类别收敛为单一扁平产物 `category-ads-all`，不发布 `category-ads*` 及区域派生。
- 独立补充来源只做增量合并，不改写 DLC 的路由语义。

## 平台渲染

规则类型按平台能力矩阵映射为原生格式：Surge / Quantumult X 输出 `.list`，Egern 输出 `.yaml`，sing-box 与 mihomo 分别编译为 `.srs` / `.mrs`。平台不支持的规则类型会被跳过，并按平台汇总受影响列表数与规则类型。二进制编译产物以规范化输入摘要、格式版本和编译器二进制摘要缓存；缓存由 CI 跨构建恢复，并通过 SHA-256 sidecar 检查，损坏时自动重编译。

## 守卫与发布

发布前依次检查产物数量、CIDR 地址族、必需派生集、列表内部冗余和平台解码结果。重叠报告记录跨列表的精确重叠与语义覆盖率，只用于发现候选，不自动合并具有独立订阅用途的列表。

内部 manifest 固化 profile、输入摘要、工具来源和产物校验结果。构建在临时目录完成，验证成功后原子替换本地产物；发布时五个平台分支整批更新。发布分支只包含 README、`domain/` 和 `ip/`。

## 可复现性

sing-box / mihomo 的版本、归档与二进制哈希锁定于 [`config/tools-lock.json`](../config/tools-lock.json)，下载后校验并记录 provenance，保证构建可复现。

## 相关入口

- 命令：`scripts/commands/`（sync-upstream、build-custom、guard-artifacts、publish-branches）
- 工具：`scripts/tools/`（Python：归一化、合并、渲染、校验）
- 测试：`scripts/tests/`
- CI：`.github/workflows/build.yml`、`validate.yml`
