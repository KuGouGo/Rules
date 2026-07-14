# 贡献指南

本文件规定提交与评审要求。开发命令见 [开发指南](docs/DEVELOPMENT.md)，实现边界见 [仓库结构](docs/STRUCTURE.md)。

## 开始之前

日常变更以 `dev` 为集成目标，验证通过后再由 `dev` 合并到 `main` 发布。提交第三方规则、数据或派生内容时，提供原始来源及可核验的许可、条款或授权；无法确认时明确写“未知”，并由维护者在合并和发布前人工决定处置。

许可审查不是自动检查。CI 不解析 `NOTICE` 或 `THIRD_PARTY_NOTICES.md`，也不会因“未知”状态自动失败。公开 URL、官方来源、`trust` 分类和 CI 通过都不能替代人工许可评审。

## 自定义规则

域名规则位于 `sources/custom/domain/*.list`：

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,example
DOMAIN-REGEX,^(.+\.)?example\.com$
```

IP 规则约定放在 `sources/custom/ip/*.list`：

```text
IP-CIDR,1.2.3.0/24
IP-CIDR6,2001:db8::/32
```

IP 目录可不存在或为空。文件名只使用小写字母、数字和连字符。

新增名称检查有明确边界：`build-custom.sh` 只对相对构建基准新加入的自定义源执行冲突判断，并只检查同一 `domain` 或 `ip` 类型在五个平台 `.output/` 中的目标路径。既有自定义源修改不经过同一新增名称判断，domain 与 ip 可同名。提交者仍应人工检查目标发布分支，避免语义混淆。

### `emby-cn` 与 `emby`

两份规则存在三条经审核的精确覆盖关系，逐条记录在 `config/custom-rule-conflicts.json`。采用首条命中的客户端必须先加载 `emby-cn`，再加载 `emby`。修改时说明重叠变化；失效、重复或只指定文件对而不指定双方规则的宽泛豁免会被拒绝。

## 质量要求

`make lint` 使用与构建相同的严格域名解析器及严格 IP 解析器，要求规则类型和值已经是规范形式，并在所有自定义文件合并后检查 domain 精确项/后缀覆盖和 IP 重复/包含。除精确审核的关系外，跨文件冲突与同文件冲突都会失败。`build-custom.sh` 会在创建构建目录、检查已有产物或准备工具前先执行该校验。不要通过删除测试、扩大豁免、降低阈值或跳过守卫掩盖原因。

配置校验只验证结构和实现约束，例如支持的枚举、HTTPS URL、阈值及必需项目；配置通过不代表许可确认。修改 `config/upstreams.json` 时必须同步更新 `THIRD_PARTY_NOTICES.md`。

## 审计信息的使用

完整主上游同步生成 `.output/upstream-summary.json` 和域名 `rule-manifest.json`。前者是部分采集摘要，不覆盖本仓库维护的自定义源（包括 `sources/custom/domain/fakeip-filter.list`）、完整转换链、提交身份或内容校验和，不能称为完整来源追溯记录。`fakeip-filter` 与其他自定义规则一起生成各平台产物，不得重新引入第三方预编译文件或下载步骤；过去采用的 `wwqgtxx/clash-rules` 二进制仅属历史。

成功的 `build-artifacts-transaction.sh` 在产物守卫之后、manifest 之前生成 `.output/build-summary.json`；manifest 绑定其文件摘要与嵌入内容。独立运行 `make build-custom*` 不生成该文件。所有摘要都不是许可证明。

## 本地验证

```bash
make validate
make preflight
```

涉及二进制格式或编译器时再运行：

```bash
make build-custom
```

`make preflight` 只组合 `make validate` 与文本自定义构建，不执行完整同步、产物守卫（artifact guard）或发布。本地缺少 ShellCheck 时可能跳过，CI 则设置 `REQUIRE_SHELLCHECK=1`。

完整支持环境与工具下载边界见 [开发指南](docs/DEVELOPMENT.md)。不要提交 `.output/`、`.tmp/`、`.bin/`、凭据或本机缓存。

## 修改实现

修改生成逻辑时：

- 为有意输出变化更新 `tests/fixtures/`；
- 新增或调整 `scripts/tests/test-*.sh`；
- 运行适用的验证和构建命令；
- 说明五平台产物及降级行为变化。

测试运行器会自动发现 `test-*.sh`，无需为此修改 Makefile。

## Pull Request 评审清单

- 说明目的、范围和用户可见影响；
- 提供来源及许可、条款、授权或“未知”状态；
- 由维护者人工确认第三方内容是否可合并与发布；
- 说明预期的平台产物和审计摘要变化；
- 记录已运行命令与结果；
- 涉及 `emby-cn` / `emby` 时确认细分规则优先；
- 不绕过严格校验、产物守卫（artifact guard）或发布树检查。

## 文档导航

- [`README.md`](README.md)：用户入口、平台示例和关键边界
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：贡献规则与人工评审清单
- [`docs/README.md`](docs/README.md)：文档职责与阅读路径
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)：环境、命令和开发流程
- [`docs/STRUCTURE.md`](docs/STRUCTURE.md)：构建、产物、守卫和发布结构
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)：常见失败与定位步骤
- [`SECURITY.md`](SECURITY.md)：安全支持范围和私密报告
- [`NOTICE`](NOTICE) / [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)：许可范围与第三方状态
