# 架构

规则流水线把上游数据变成各客户端产物，流程如下：

```
上游获取 → 规范化 → 合并与派生 → 平台渲染 → 守卫校验 → 事务发布
```

## 上游获取

来源统一在 [`config/upstreams.json`](../config/upstreams.json) 中声明，并为每个来源配置健康策略（最小条目数、最小体积、地址族等），拦截空响应与截断数据。

- **域名**：[nekolsd/dlc2](https://github.com/nekolsd/dlc2)（[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) 的精化分支，核心树；克隆后先过数据审计，硬性数据错误阻断构建）、ShellCrash `fakeip-filter`。
- **IP**：cn-ipv46、google、telegram、cloudflare、cloudfront（CloudFront CDN）、fastly 等上游，Apple IP 为内置自定义源，以及由 RIPEstat 按 ASN 拉取的前缀。
- **本地**：`sources/custom/` 自定义规则与 `sources/builtin/` 内置保留地址。

## 规范化与合并

- 统一大小写与书写形式，按 `DOMAIN` / `DOMAIN-SUFFIX` 超集折叠去重。
- 保留 DLC 的 `@cn` / `@!cn` / `@ads` 属性：`@cn` / `@!cn` 用于派生对应规则集（如 `geolocation-!cn@cn`），`@ads` 仅参与基础列表过滤（如 `cn` 剔除广告条目），不单独发布 `@ads` 衍生产物。
- 独立补充来源只做增量合并，不改写 DLC 的路由语义。

## 平台渲染

规则类型按平台能力矩阵映射为原生格式：Surge / Quantumult X 输出 `.list`，Egern 输出 `.yaml`，sing-box 与 mihomo 分别编译为 `.srs` / `.mrs`。平台不支持的规则类型会被跳过并记录。

## 守卫与发布

发布前执行守卫（`guard-artifacts.sh`）：产物数量下限、地址族与保留地址校验、必需派生集完整性检查、列表内 `DOMAIN-SUFFIX` 超集冗余审计。全部通过后，产物在事务内原子切换，失败自动回滚并保留诊断信息。

## 可复现性

sing-box / mihomo 的版本、归档与二进制哈希锁定于 [`config/tools-lock.json`](../config/tools-lock.json)，下载后校验并记录 provenance，保证构建可复现。

## 相关入口

- 命令：`scripts/commands/`（sync-upstream、build-custom、guard-artifacts、publish-branches）
- 工具：`scripts/tools/`（Python：归一化、合并、渲染、校验）
- 测试：`scripts/tests/`
- CI：`.github/workflows/build.yml`、`validate.yml`
