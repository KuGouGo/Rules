# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/pull-request.yml"><img alt="Pull Request Validation" src="https://github.com/KuGouGo/Rules/actions/workflows/pull-request.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="Repository code license" src="https://img.shields.io/badge/repository%20code-MIT-4b5563">
</p>

本仓库从配置的上游和本地维护源生成 Surge、Quantumult X、Egern、sing-box 与 mihomo 规则。`main` 保存构建源码、配置和工作流；可直接使用的文件位于对应平台分支。

> [!IMPORTANT]
> 客户端不要引用 `main`。规则名称和区域分类沿用上游定义，不构成准确性、完整性或适用性保证。第三方内容不因格式转换而自动适用本仓库的 MIT 许可，详见 [`NOTICE`](NOTICE) 与 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 获取产物

分支 URL 格式：

```text
https://raw.githubusercontent.com/KuGouGo/Rules/{branch}/{type}/{name}.{extension}
```

| 客户端 | 分支 | domain / ip 扩展名 | 分支说明 |
| --- | --- | --- | --- |
| Surge | `surge` | `.list` | [查看产物](https://github.com/KuGouGo/Rules/tree/surge) |
| Quantumult X | `quanx` | `.list` | [查看产物](https://github.com/KuGouGo/Rules/tree/quanx) |
| Egern | `egern` | `.yaml` | [查看产物](https://github.com/KuGouGo/Rules/tree/egern) |
| sing-box | `sing-box` | `.srs` | [查看产物](https://github.com/KuGouGo/Rules/tree/sing-box) |
| mihomo | `mihomo` | `.mrs` | [查看产物](https://github.com/KuGouGo/Rules/tree/mihomo) |

示例：

```text
https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/emby-cn.list
https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml
https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs
https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/google.mrs
```

各平台的接入方式和最小配置示例位于对应产物分支的 `README.md`。分支 URL 会随成功发布变化，不适合作为不可变版本标识；需要固定内容时，应将分支名替换为产物分支的提交 SHA。

## 规则说明

| 名称 | 类型 | 当前生成方式 |
| --- | --- | --- |
| `cn` | domain | v2fly/domain-list-community 的 `cn` 集合及其派生结果 |
| `cn` | ip | 配置的中国大陆 IP 上游经规范化、去重和 CIDR 合并后的结果 |
| `geolocation-cn` / `geolocation-!cn` | domain | 上游提供的区域集合名称与内容 |
| `google` / `telegram` | ip | 配置的服务地址源；Telegram 结果还合并配置的 ASN 前缀 |
| `emby-cn` / `emby` | domain | 本仓库维护的两个 Emby 规则集合 |
| `fakeip-filter` | domain | 本仓库维护的保守型 Fake-IP 排除集合 |

在按首条命中处理的客户端中，如果同时使用 `emby-cn` 和 `emby`，应先加载范围较窄的 `emby-cn`。规则文件会随上游增加、删除或改变；使用前应在目标分支确认文件存在并检查内容。

## 转换行为

| 产物平台 | 精确域名 | 后缀 | 关键词 | 正则 | IP CIDR |
| --- | :---: | :---: | :---: | :---: | :---: |
| Surge | ✓ | ✓ | ✓ | — | ✓ |
| Quantumult X | ✓ | ✓ | ✓ | — | ✓ |
| Egern | ✓ | ✓ | ✓ | ✓ | ✓ |
| sing-box | ✓ | ✓ | ✓ | ✓ | ✓ |
| mihomo | ✓ | ✓ | — | — | ✓ |

`✓` 表示当前转换器会保留并输出该类型，`—` 表示当前转换链会省略该类型；该表不判断客户端自身的全部能力。一个列表在目标平台没有可保留条目时，不发布空文件。

属性与区域名称沿用上游语义：

- `name@cn`、`name@!cn`、`name@ads` 是属性派生集合，`@!cn` 不是布尔取反。
- `*-cn`、`*-!cn` 是区域列表名称；明显冗余的属性派生不会发布。
- `official`、`registry`、`community` 是仓库配置中的来源分类，不代表质量、可信度或许可等级。

## 本地维护

本地命令要求 Bash 5+、GNU Make、Git 和 Python 3。macOS 可使用 Homebrew Bash 运行检查和文本构建；需要下载 sing-box 或 mihomo 的二进制构建只支持 lock 文件声明的 Linux 平台。

```bash
make check-runtime
make validate
make build-custom-text
make preflight
make clean
```

- `make validate`：运行 Shell、Python、配置、自定义规则和测试检查。
- `make build-custom-text`：生成自定义文本产物，不下载二进制工具。
- `make preflight`：执行 `make validate` 和自定义文本构建；不执行上游完整同步、二进制构建或发布。
- `make clean`：删除生成产物和临时文件，保留已校验的工具缓存。

完整环境、构建事务和调试命令见 [开发指南](docs/DEVELOPMENT.md)。

## 仓库边界

- 长期分支只保留 `main` 与 `surge`、`quanx`、`egern`、`sing-box`、`mihomo` 五个产物分支。
- 变更通过临时分支向 `main` 提交 Pull Request；PR 运行静态检查和不发布的完整候选构建，临时分支在合并后删除。
- `main` 在构建相关路径变化、定时任务运行或人工触发时执行发布工作流；产物内容没有变化时不会创建新的产物分支提交。
- Dependabot 每月向 `main` 集中提交一个 GitHub Actions minor/patch 更新 PR；major 与安全告警单独人工评估。
- `fakeip-filter` 是本仓库维护的文本源，不下载第三方预编译文件。
- 构建摘要、manifest 和 CI 通过都不是第三方许可证明。
- 规则按现状提供。使用者需自行判断策略、顺序和更新带来的影响，并保留可回退版本。

## 文档

| 文档 | 内容 |
| --- | --- |
| [贡献指南](CONTRIBUTING.md) | 规则格式、来源要求和评审清单 |
| [开发指南](docs/DEVELOPMENT.md) | 环境、命令和开发流程 |
| [仓库结构](docs/STRUCTURE.md) | 同步、构建、manifest、守卫和发布架构 |
| [故障排查](docs/TROUBLESHOOTING.md) | 常见构建和产物问题 |
| [安全政策](SECURITY.md) | 安全问题报告范围与方式 |
| [第三方声明](THIRD_PARTY_NOTICES.md) | 上游来源和人工许可核对状态 |
