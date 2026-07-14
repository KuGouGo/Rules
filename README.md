# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/pull-request.yml"><img alt="Pull Request Validation" src="https://github.com/KuGouGo/Rules/actions/workflows/pull-request.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-4b5563">
</p>

面向 Surge、Quantumult X、Egern、sing-box 和 mihomo 的规则构建仓库。`dev` 集成开发变更，`main` 保存稳定源码并触发发布，客户端产物位于对应平台分支。

> [!IMPORTANT]
> 客户端不要引用 `main`。第三方规则不因格式转换而自动适用 MIT，来源和许可边界见 [`NOTICE`](NOTICE) 与 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 使用规则

稳定 URL 格式：

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

各平台的接入方式和最小配置示例位于对应产物分支的 `README.md`。分支 URL 始终指向最新产物；需要固定内容时，将分支名替换为具体提交 SHA。

## 常用规则

| 名称 | 类型 | 用途 |
| --- | --- | --- |
| `cn` | domain / ip | 中国大陆域名或合并后的中国大陆 CIDR |
| `geolocation-cn` | domain | 上游定义的中国大陆区域域名 |
| `geolocation-!cn` | domain | 上游定义的非中国大陆区域域名 |
| `google` / `telegram` | ip | 对应服务的 CIDR；Telegram 额外合并 ASN 前缀 |
| `emby-cn` | domain | Emby 中国大陆细分规则 |
| `emby` | domain | 通用 Emby 规则 |
| `fakeip-filter` | domain | 本仓库维护的 Fake-IP 排除规则 |

`emby-cn` 必须放在 `emby` 前面。规则名称来自上游，不同名称即使内容相近也不视为别名；使用前请在目标分支确认文件存在。

## 平台能力

| 平台 | 精确域名 | 后缀 | 关键词 | 正则 | IP CIDR |
| --- | :---: | :---: | :---: | :---: | :---: |
| Surge | ✓ | ✓ | ✓ | — | ✓ |
| Quantumult X | ✓ | ✓ | ✓ | — | ✓ |
| Egern | ✓ | ✓ | ✓ | ✓ | ✓ |
| sing-box | ✓ | ✓ | ✓ | ✓ | ✓ |
| mihomo | ✓ | ✓ | — | — | ✓ |

`—` 表示当前转换链不保留该类型，不代表客户端本身不支持。列表只包含不受支持的规则类型时，对应平台不会发布空产物。

属性与区域名称沿用上游语义：

- `name@cn`、`name@!cn`、`name@ads` 是属性派生集合，`@!cn` 不是布尔取反。
- `*-cn`、`*-!cn` 是区域列表名称；明显冗余的属性派生不会发布。
- `official`、`registry`、`community` 仅表示采集来源分类，不代表质量或许可等级。

## 本地维护

要求 Bash 5+、GNU Make、Git 和 Python 3。macOS 可使用 Homebrew Bash 完成验证与文本构建；sing-box 和 mihomo 的完整二进制构建仅支持 lock 文件声明的 Linux 平台。

```bash
make check-runtime
make validate
make build-custom-text
make preflight
make clean
```

- `make validate`：运行 Shell、Python、配置、规则质量和测试检查。
- `make build-custom-text`：生成自定义文本产物，不下载二进制工具。
- `make preflight`：执行完整验证和文本构建，适合提交前检查。
- `make clean`：删除生成产物和临时文件，保留可信工具缓存。

完整环境、构建事务和调试命令见 [开发指南](docs/DEVELOPMENT.md)。

## 仓库边界

- 长期分支只保留 `dev`、`main` 与 `surge`、`quanx`、`egern`、`sing-box`、`mihomo` 五个产物分支。
- 日常代码、文档和依赖更新先进入 `dev`；`dev` 只验证不发布，合并到 `main` 后才构建并更新产物分支。
- Dependabot 以 `dev` 为目标，每月集中提交 GitHub Actions 的 minor/patch 更新；major 与安全告警经人工评估后同样从 `dev` 进入，临时分支在合并后删除。
- `fakeip-filter` 是本仓库维护的文本源，不下载第三方预编译文件。
- 构建摘要、manifest 和 CI 通过都不是第三方许可证明。
- 规则按现状提供，部署前应检查内容并保留回滚方案。

## 文档

| 文档 | 内容 |
| --- | --- |
| [贡献指南](CONTRIBUTING.md) | 规则格式、来源要求和评审清单 |
| [开发指南](docs/DEVELOPMENT.md) | 环境、命令和开发流程 |
| [仓库结构](docs/STRUCTURE.md) | 同步、构建、manifest、守卫和发布架构 |
| [故障排查](docs/TROUBLESHOOTING.md) | 常见构建和产物问题 |
| [安全政策](SECURITY.md) | 安全问题报告范围与方式 |
| [第三方声明](THIRD_PARTY_NOTICES.md) | 上游来源和人工许可核对状态 |
