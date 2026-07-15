# 仓库结构

本文件描述同步、构建、守卫和发布实现，不承担客户端配置教程或许可结论。

## 顶层职责

| 路径 | 职责 |
| --- | --- |
| `sources/custom/` | 自有域名规则及可选 IP 规则 |
| `config/` | 上游端点、首批健康基线、平台能力、自定义规则精确冲突关系和二进制工具 lock |
| `scripts/commands/` | 同步、恢复、构建、守卫和发布入口 |
| `scripts/lib/` | 下载、工具缓存和渲染共享函数 |
| `scripts/tools/` | Python 解析、规范化、校验与摘要工具 |
| `scripts/tests/`、`tests/fixtures/` | 自动测试与稳定夹具 |
| `templates/branch-readmes/` | 发布分支 README 模板及随发布树携带的 v2fly MIT 充分通知 |
| `.output/` | 构建产物及部分审计摘要 |
| `.tmp/` | 可清理临时工作区 |
| `.bin/` | 外部工具及版本缓存 |
| `.artifacts/` | 失败构建保留的诊断摘要；属于可清理的本地/CI 数据，不进入发布分支 |

## 构建范围

完整范围依次同步主上游、构建自定义规则、执行产物守卫（artifact guard），再上传并发布。自定义范围从五个发布分支恢复既有产物，然后重建自定义规则。工作流没有独立的 Fake-IP 同步步骤。

`fakeip-filter` 当前源为本仓库维护的 `sources/custom/domain/fakeip-filter.list`，由 `build-custom.sh` 与其他自定义规则一起生成五平台形式，不从网络下载预编译文件。`config/upstreams.json` 覆盖主上游网络输入；工具资产下载另由工具 lock 控制。

`main` 是唯一长期源码与发布源分支，开发使用合并后删除的临时分支。发布分支为 `surge`、`quanx`、`egern`、`sing-box`、`mihomo`，只允许生成的 `README.md`、`domain/`、`ip/` 及平台对应扩展名。各分支 `README.md` 由 `templates/branch-readmes/` 生成，并直接包含 v2fly/domain-list-community 的完整 MIT 版权与许可通知；因此发布树无需新增独立许可证文件。模板变更属于构建触发路径。

## 审计文件

- `.output/upstream-summary.json`：主同步在健康检查后记录名称、实际 URL、状态、回退、临时路径、原始与规范化内容的字节数、条目数和 SHA-256；DLC 另含检出的 commit。
- `.output/domain/rule-manifest.json`：域名列表、区域集合和属性派生结构。
- `.output/build-summary.json`：GitHub Actions 在产物守卫之后、规范发布清单之前扫描 `.output/` 生成。
- `.output/artifact-manifest.json`：规范发布清单，包含 schema/generation/build/source/build scope、能力与工具 lock 摘要、工具 provenance metadata、可用的上游/构建摘要，以及每个可发布 domain/ip 文件的平台、类型、扩展名、字节数、SHA-256 和可判定来源。JSON 键与产物按稳定顺序输出；generation/build id 由调用方提供，因此相同输入和 id 可复现相同内容。
- `.tmp/**/normalize-tasks.json`：批处理任务描述，属于临时数据。
- `.artifacts/diagnostics/<generation-time>/`：失败事务保留的 `transaction-health.json` 及可用的构建/上游摘要；CI 日志只展示白名单内且大小受限的 JSON，完整诊断作为短期 Actions artifact 上传。

`verify-artifact-manifest.sh` 严格重算能力矩阵允许的完整文件集合、路径层级与安全性、非零大小、字节数和 SHA-256，并核对能力/lock 摘要及可选的预期 source SHA。二进制读回规则与同名 custom 源或同一事务的文本产物按类型和值精确比较，并记录语义 SHA-256。发布作业下载后再次验证；`publish-branches.sh` 自身也必须先验证清单，拒绝缺失、额外或被修改的产物。清单只作为流水线审计输入，不复制到发布分支。一次发布中五个分支提交携带共同 generation id 和 source SHA；任一平台 tree 改变时完整 cohort 原子推进并保留各分支父历史，全部 tree 不变时整体跳过。

`scripts/tools/artifact_origins.py` 是 `artifact-origins.json` 的唯一写入口：完整同步重置为 `generated-upstream`，发布分支恢复重置为 `restored-published-branch`，自定义构建只重标本次控制且实际存在的目标，并清除对应平台已经删除或降级省略的旧记录。

`config/domain-platform-capabilities.json` 是平台 branch、extension、format、rule mapping、empty policy、compiler 与 verifier 的唯一结构化来源。`scripts/tools/platform_capabilities.py` 严格加载并校验实现标识，同时向 Python 消费者提供查询对象、向 shell 消费者生成稳定的 tab-separated registry。IP 渲染、构建/守卫的安全循环、摘要和发布均查询该 registry；声明未知实现时构建会 fail closed。公开分支名仍由能力文件中的 `branch` 字段固定。

`upstream-summary.json` 不是完整来源追溯记录：它不覆盖自定义源（包括 `fakeip-filter`）、全部转换步骤或 HTTP 响应身份。上述文件也都不是许可证证明。

## 名称冲突检查

`build-custom.sh` 根据 `RULES_CONFLICT_BASE_SHA`（可用时）或 `HEAD^` 判断自定义源是否为新增。只有新增源会检查五个平台当前 `.output/` 中同类型目标是否已经存在：domain 只对 domain，ip 只对 ip。

因此该检查不覆盖既有自定义源修改、未出现在当前 `.output/` 的潜在未来上游名称，也不禁止 domain 与 ip 使用同一名称。它是防覆盖措施，不是全局命名守卫。

这与源码语义冲突阶段相互独立：严格共享解析器先验证 canonical 类型和值，再把所有 custom domain 文件合并检查精确项/后缀覆盖，把所有 custom IP 文件合并检查重复/包含。`config/custom-rule-conflicts.json` 只能逐条描述真实覆盖关系；失效、重复或文件对级宽泛关系会失败。当前仅列出三条经审核的 `emby-cn` / `emby` 关系。`build-custom.sh` 在创建构建目录、读取已有产物或准备工具前运行该阶段。

## 产物守卫（artifact guard）范围

当前产物守卫（artifact guard）包括：

- 五个平台 domain 和 ip 的最低文件数量；
- 五个平台冗余域名属性派生文件名；
- 基线分支可用且未命中特定兼容跳过条件时，Surge、Quantumult X、Egern 文本域名规则相对发布分支的下降检查；
- Surge 和 Quantumult X 文本 IP 的地址族及非 `private` 非公网 CIDR 检查；
- 两个平台部分内置 IP 集的总数与 IPv4/IPv6 最低值；
- Surge 上部分内置 IP 集相对基线的增长或删除检查。

artifact guard 本身不解析 `.srs` / `.mrs`，二进制读回与精确语义关联由随后生成和复验 manifest 的阶段执行；两者都不审查许可。发布脚本另行检查发布树、扩展名和本地产物完整性。

## 工具缓存与清理

sing-box 和 mihomo 只按 `config/tools-lock.json` 固定版本、tag commit 和 Linux `amd64` / `arm64` 资产下载到 `.bin/`。归档解包前必须匹配 lock 中的 SHA-256。每个缓存二进制都有原子替换的 provenance sidecar，记录 lock commit、资产与归档摘要、二进制摘要和版本探针；命中缓存时会重新核对 sidecar 的完整字段、二进制 SHA 和实时版本输出，不可信缓存会被重新下载替换。工作流缓存键以缓存格式版本开头，并包含两个工具版本、平台和 lock 摘要。该校验是 GitHub release asset digest 锁定，不是发布者签名。`make clean` 保留可信工具缓存，只移除未完成下载与 metadata 临时文件、生成产物、临时目录和 Python 缓存。

## 文档导航

- [`README.md`](../README.md)：用户入口、平台示例和关键边界
- [`CONTRIBUTING.md`](../CONTRIBUTING.md)：贡献规则与人工评审清单
- [`docs/README.md`](README.md)：文档职责与阅读路径
- [`docs/DEVELOPMENT.md`](DEVELOPMENT.md)：环境、命令和开发流程
- [`docs/STRUCTURE.md`](STRUCTURE.md)：构建、产物、守卫和发布结构
- [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md)：常见失败与定位步骤
- [`SECURITY.md`](../SECURITY.md)：安全支持范围和私密报告
- [`NOTICE`](../NOTICE) / [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)：许可范围与第三方状态
