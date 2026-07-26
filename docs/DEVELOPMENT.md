# 开发指南

本文件说明环境、命令和日常开发流程；构建内部结构见 [仓库结构](STRUCTURE.md)。

## 环境支持

CI 的受支持基准是 GitHub Actions `ubuntu-latest`、Bash 5+ 和 Python 3.11。本地验证与文本构建支持安装了 Bash 5+、Python 3.11+、GNU Make、Git、curl、tar、gzip、find 的 Linux、WSL 和 macOS；macOS 应使用 Homebrew Bash 与 Python，并确保 `/opt/homebrew/bin` 或 `/usr/local/bin` 位于系统路径之前。`make check-runtime` 会在构建前拒绝旧版 Bash 或 Python。

Homebrew 的版本化 Python 将通用的 `python3` 链接放在 `libexec/bin`。macOS 可用以下配置验证当前终端，而无需为本地系统增加二进制规则编译支持：

```bash
export PATH="$(brew --prefix python@3.11)/libexec/bin:$(brew --prefix)/bin:$PATH"
make check-runtime
```

二进制工具下载逻辑仅支持 Linux 的 `amd64`、`arm64` 锁定资产。原生 Windows 在需要下载 sing-box/mihomo 时会被 `require_non_windows_shell` 明确拒绝；macOS 也没有对应 lock 平台。请使用 Linux、WSL 或 GitHub Actions 完成二进制构建。

完整构建只使用 `config/tools-lock.json` 固定的 sing-box 和 mihomo 版本、Linux 资产名、GitHub release asset SHA-256，以及从这些已校验官方归档独立提取的二进制 SHA-256；环境变量不能覆盖版本。下载归档在解包前校验摘要，解包后的程序也必须先匹配锁定摘要才会执行；缓存通过 provenance sidecar、锁定来源、二进制 SHA-256 和版本探针复核，二进制与 sidecar 成对替换，metadata 写入失败不会替换现有缓存。`tag_commit` 仅是记录/人工核对用 metadata，当前流程不认证 tag 与 commit 的关系。工作流缓存键包含锁文件摘要、两个版本和格式前缀。该机制是资产摘要锁定，不是发布者签名。

## 常用命令

```bash
make help
make check
make lint
make test
make validate
make build-custom-text
make build-custom
make preflight
make clean
```

- `make check` / `make lint`：快速检查 Shell、Python、配置和自定义规则。
- `make validate`：快速检查后再运行完整测试。
- `make check-runtime`：验证当前 `PATH` 解析到 Bash 5+ 和 Python 3.11+。
- `make build-custom-text`：只生成自定义文本产物，不下载二进制编译器。
- `make build-custom`：生成自定义文本和二进制产物。
- `make preflight`：`make validate` 加文本自定义构建；不执行完整同步、产物守卫（artifact guard）或发布。
- `build-artifacts-transaction.sh`：CI 的完整入口。它在 `.tmp/` 中以事务自有的 `RULES_ARTIFACT_ROOT` 组合上游同步或已发布分支恢复、自定义构建、守卫、摘要、manifest 生成与验证；调用方提供 `RULES_ARTIFACT_ROOT` 会被拒绝，测试或运维如需改变最终提升位置应使用 `RULES_LIVE_ARTIFACT_ROOT`。该 live root 必须与仓库 `.tmp/` 位于同一文件系统，跨设备目标会在构建前被拒绝；最终 backup、promotion 和 rollback 均使用不允许复制回退的严格目录 rename，因此检查后的设备变化也会以 EXDEV 失败。全部成功后才提升为 `.output/`（或该显式 live root）。backup 后收到 HUP、INT 或 TERM，以及 promotion rename 失败时，都会通过同一幂等回滚恢复旧目录；恢复本身失败时事务目录保留唯一备份以供人工处理。失败诊断写入非发布目录 `.artifacts/diagnostics/`，并记录 failure reason、promotion state、rollback status 与可用的 signal。`config/upstreams.json` 为每个源声明 parser、required/optional、原始字节、规范条目、地址族和 fallback policy；required 源在主 URL 与允许的回退均失败，或出现语义健康回归时阻断提升。每个 RIPE Stat ASN 响应和合并分组都使用 `ripe-stat` health policy，过小或无效响应会先写入诊断摘要再阻断事务。自定义恢复要求五个发布分支都存在且具有相同 generation/source 身份，并把分支 commit 写入 manifest restoration metadata；缺失或身份分裂时失败关闭，应执行 full 构建恢复发布 cohort。
- `generate-artifact-manifest.sh`：完整构建事务的内部阶段，不是独立的日常构建入口。它要求当前 artifact root 已有 canonical 输入、摘要、来源记录和发布基线；按能力配置验证五个平台后才写入 schema v4 manifest。缺失或未验证的产物会阻断生成。CI 将 source SHA 绑定到实际 checkout 的 `github.sha`：PR 验证记录被测试的合并提交，正式发布记录 `main` 提交。
- `verify-artifact-manifest.sh`：严格重算所选 artifact root 内的可发布文件集合、路径、大小和 SHA-256，并重新执行五平台 canonical 验证、核对发布基线、能力/lock 与可选 source SHA；发布 job 在恢复或安装锁定工具后强制执行同一验证。需要单独调试时，应先保留完整事务生成的 artifact root，不要手工拼装 manifest 参数。

五平台验证以 `.output/.canonical/{domain,ip}/` 为共同基准。Surge、Quantumult X、Egern 解析各自文本/YAML，`.srs` 使用固定的 `sing-box rule-set decompile` 读回 JSON，`.mrs` 使用固定的 `mihomo convert-ruleset <domain|ipcidr> mrs INPUT OUTPUT` 读回。每个平台先按能力矩阵过滤不支持的类型，再比较规范化语义集合：域名消除已被更宽后缀覆盖的冗余项，IP 合并为等价 CIDR 并集；值替换、范围扩大、范围丢失、缺少副本和没有 canonical 来源的额外文件都会失败。manifest 记录验证方法、原始计数、读回语义 SHA-256，以及规范输入的语义 SHA-256。
- `make clean`：删除 `.tmp/`、`.output/`、`.artifacts/`、Python `__pycache__` 和未完成的 `.bin/*.new*`；保留已安装的 `.bin/sing-box`、`.bin/mihomo` 及 provenance sidecar。

CI 设置 `REQUIRE_SHELLCHECK=1`，本地缺少 ShellCheck 时的跳过不代表 CI 会通过。

GitHub Actions 使用完整 commit SHA 固定版本，按需手工更新。

## 开发流程

1. 直接修改 `main` 或使用临时分支，不手工编辑生成目录。
2. 修改自定义源、配置、实现或测试夹具。
3. 日常规则变更运行 `make check`；修改生成逻辑时再运行 `make validate` 或适用的构建命令。
4. 检查差异中没有 `.output/`、`.tmp/`、`.bin/`、凭据或无关格式化。
5. 可直接提交到 `main`，也可通过 Pull Request 合并。PR 只运行基础校验；完整候选构建不再重复执行。
6. `main` 的发布工作流按变更范围生成并更新五个平台分支。

## 自定义规则与名称

域名源位于 `sources/custom/domain/*.list`；可选 IP 源位于 `sources/custom/ip/*.list`，后者可不存在。文件名只使用小写字母、数字和连字符。

新增名称冲突检查仅针对相对基准提交新加入的自定义源，且 domain 与 ip 分开检查五个平台的当前 `.output/` 目标路径。它不是全仓库名称注册表，也不覆盖既有自定义源修改。

自定义源会检查类型、值和同一文件内的重复/覆盖关系。不同文件允许有意重叠，以便绑定不同策略，不再维护逐条冲突审批清单。首条命中客户端应先加载细分规则，例如先加载 `emby-cn`，再加载 `emby`。

## 摘要与许可评审

主上游完整同步生成的 `upstream-summary.json` 记录健康检查后的状态、实际 URL、回退、原始与规范化输入的字节数、条目数和 SHA-256；DLC 另记录检出的 commit。它不包含本仓库维护的自定义源（包括 `sources/custom/domain/fakeip-filter.list`），也不覆盖完整转换链或 HTTP 响应身份，因此仍不是完整来源证明。`fakeip-filter` 与其他自定义规则共用同一构建入口，没有独立下载步骤。

`build-summary.json` 是成功构建事务的固有输出：产物守卫通过后、manifest 生成前，由 `build-artifacts-transaction.sh` 在事务 artifact root 中生成。manifest 同时记录摘要文件 SHA-256 与解析后的嵌入内容，发布前验证两者。工作流的 `Show summary` 步骤只负责显示成功输出，或在失败诊断场景中临时生成可读摘要，不定义成功产物。

许可状态完全由维护者人工核验。自动化不解析许可文档，也不会根据“未知”状态自动阻断。

## 测试约定

输出行为有意变化时，更新 `tests/fixtures/` 并新增或调整 `scripts/tests/test-*.sh`。测试运行器自动发现 `test-*.sh`。不要通过降低阈值、删除测试或跳过守卫掩盖异常。

## 文档导航

- [`README.md`](../README.md)：用户入口、平台示例和关键边界
- [`CONTRIBUTING.md`](../CONTRIBUTING.md)：自定义规则格式与修改说明
- [`docs/README.md`](README.md)：文档职责与阅读路径
- [`docs/DEVELOPMENT.md`](DEVELOPMENT.md)：环境、命令和开发流程
- [`docs/STRUCTURE.md`](STRUCTURE.md)：构建、产物、守卫和发布结构
- [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md)：常见失败与定位步骤
- [`SECURITY.md`](../SECURITY.md)：安全支持范围和私密报告
- [`NOTICE`](../NOTICE) / [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)：许可范围与第三方状态
