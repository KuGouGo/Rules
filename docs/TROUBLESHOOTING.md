# 故障排查

先处理日志中最早的错误，并对照 [开发指南](DEVELOPMENT.md) 的环境边界。

## `make validate` 失败

- `shellcheck not found`：本地默认可跳过，CI 强制要求；安装后重试。
- Python 编译失败：确认 Python 3 环境并修复首个语法错误。
- 配置失败：检查 HTTPS URL、正整数阈值、必需项和支持的枚举。
- 自定义规则失败：处理非 canonical 类型/值、跨文件或同文件的 domain 精确项/后缀覆盖、IP 重复/包含、正则或 CIDR 规范问题。若涉及豁免，只能在 `config/custom-rule-conflicts.json` 逐条记录真实关系；不要添加文件对级宽泛关系，失效和重复关系也会失败。
- 测试失败：直接运行对应 `scripts/tests/test-*.sh`，再检查夹具是否应有意更新。

## 原生 Windows 构建失败

sing-box/mihomo 下载逻辑会在需要获取新工具时拒绝原生 Windows。请使用 WSL、Linux 或 GitHub Actions。Git Bash 不属于完整支持环境，不能因文本目标偶尔可运行而推断二进制构建受支持。

## 文本成功但二进制失败

`make build-custom-text` 不下载编译器。检查网络、GitHub Release 可用性、`amd64` / `arm64` 架构和 `.bin/` 缓存后运行：

```bash
make build-custom
```

若日志报告 checksum mismatch，停止并核对 `config/tools-lock.json` 与官方 GitHub Release 资产，不要绕过校验。缓存命中还会检查 provenance sidecar、二进制 SHA-256 和版本探针；校验失败时会自动重新下载。该机制验证固定资产摘要，但不等同于发布者签名。

## `make clean` 后工具仍存在

这是预期行为。清理会删除 `.tmp/`、`.output/`、Python 缓存及 `.bin/*.new*`，但保留已缓存的 sing-box、mihomo 和 provenance sidecar。若需要强制重新下载，应人工删除对应二进制及其 `.provenance.json`；不要提交 `.bin/`。

## 自定义名称冲突

冲突检查只针对相对基准新加入的自定义源，并在同一 domain/ip 类型内检查当前 `.output/` 的五平台目标。报错时重命名新增规则，不要删除恢复或同步得到的产物。

既有自定义源修改、domain 与 ip 同名、当前产物中尚不存在的未来上游名称不在同一检查范围内，仍需人工审查。

## `emby-cn` 未按预期命中

确认 `emby-cn` 位于 `emby` 之前，并绑定不同策略。两份规则当前有三条在 `config/custom-rule-conflicts.json` 逐条记录的精确覆盖关系；反向加载会让宽泛规则先命中。若 lint 报告该配置失效或出现新冲突，应核对具体双方规则，不要扩大为文件对级豁免。

## 上游同步或条目异常

1. 对照 `config/upstreams.json` 检查主 URL、回退、解析器和阈值。
2. 成功事务查看 `.output/upstream-summary.json`；失败事务查看 `.artifacts/diagnostics/<generation-time>/` 中保留的 upstream/transaction health 报告。失败时 `.output/` 仍是事务开始前的完整树，不会包含部分下载、渲染或编译结果。
3. 成功后查看 `.output/domain/rule-manifest.json` 定位属性派生。
4. 对照基线和发布分支判断变化是否预期。

该摘要不包括本仓库维护的自定义源（包括 `sources/custom/domain/fakeip-filter.list`），也没有完整转换链、提交身份或内容校验和，不能单独作为完整来源追溯记录或许可依据。`fakeip-filter` 应由 `build-custom.sh` 生成；若日志出现第三方 URL、独立同步或预编译下载，应视为迁移回归。过去的 `wwqgtxx/clash-rules` 二进制仅属历史。

## 找不到 `build-summary.json`

独立运行 `make build-custom*` 不生成它；请运行 `build-artifacts-transaction.sh`。成功事务会在产物守卫之后、manifest 之前生成并绑定该摘要。工作流的 `Show summary` 只显示成功输出，或在失败诊断时临时生成可读摘要；失败时 `.output/` 仍保留上一次成功事务。

## 产物守卫（artifact guard）阻断

检查最低文件数、冗余派生名、文本域名下降、Surge/Quantumult X 文本 IP 合法性和部分内置 IP 基线。二进制格式没有全部执行等价语义检查。只有在来源证据、测试和评审说明齐全时才调整阈值。

## 许可状态不明

自动化不会发现或阻断许可问题。停止相关内容的合并或发布，由维护者对照 `NOTICE`、`THIRD_PARTY_NOTICES.md`、上游许可证和条款人工评审。CI 通过不构成授权。

## 客户端问题

- 404：核对分支、domain/ip 类型、规则名和固定扩展名。
- Quantumult X 策略不存在：用 `filter_remote` 的 `force-policy` 绑定本地策略。
- mihomo 缺少 domain `.mrs`：只有关键词或正则的列表会因当前降级边界而不发布。
- 内容未更新：检查发布分支提交、工作流状态和客户端缓存周期。

## 文档导航

- [`README.md`](../README.md)：用户入口、平台示例和关键边界
- [`CONTRIBUTING.md`](../CONTRIBUTING.md)：贡献规则与人工评审清单
- [`docs/README.md`](README.md)：文档职责与阅读路径
- [`docs/DEVELOPMENT.md`](DEVELOPMENT.md)：环境、命令和开发流程
- [`docs/STRUCTURE.md`](STRUCTURE.md)：构建、产物、守卫和发布结构
- [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md)：常见失败与定位步骤
- [`SECURITY.md`](../SECURITY.md)：安全支持范围和私密报告
- [`NOTICE`](../NOTICE) / [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)：许可范围与第三方状态
