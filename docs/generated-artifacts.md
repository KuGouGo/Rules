# 生成产物说明

构建产物先写入 `.output/`，发布时再复制到对应平台分支。`.output/` 是本地临时目录，不提交到 `main`。

## 目录矩阵

| 类型 | 平台 | 本地目录 | 发布分支路径 | 扩展名 |
| --- | --- | --- | --- | --- |
| domain | Surge | `.output/domain/surge` | `domain/` | `.list` |
| domain | Quantumult X | `.output/domain/quanx` | `domain/` | `.list` |
| domain | Egern | `.output/domain/egern` | `domain/` | `.yaml` |
| domain | sing-box | `.output/domain/sing-box` | `domain/` | `.srs` |
| domain | mihomo | `.output/domain/mihomo` | `domain/` | `.mrs` |
| ip | Surge | `.output/ip/surge` | `ip/` | `.list` |
| ip | Quantumult X | `.output/ip/quanx` | `ip/` | `.list` |
| ip | Egern | `.output/ip/egern` | `ip/` | `.yaml` |
| ip | sing-box | `.output/ip/sing-box` | `ip/` | `.srs` |
| ip | mihomo | `.output/ip/mihomo` | `ip/` | `.mrs` |

## 发布分支

`scripts/publish-branches.sh` 将 `.output/` 中的产物发布到以下客户端分支：

- `surge`
- `quanx`
- `egern`
- `sing-box`
- `mihomo`

这些分支只承载面向订阅使用的产物和分支 README，不承载 `main` 分支的脚本源码。

## 兼容性约束

- 不应随意修改分支名、目录名、文件扩展名或规则名。
- 自定义规则文件名会映射到订阅 URL 中的 `{name}`。
- 二进制产物由 `sing-box` 与 `mihomo` 编译生成，工具版本由 `scripts/resolve-versions.sh` 与 `.bin/*.version` 管理。
- `scripts/guard-artifacts.sh` 会检查产物数量、IP 条目数量和大规模删除/变更比例。

## 临时目录

- `.bin/`：下载缓存的 `sing-box`、`mihomo` 与版本文件。
- `.tmp/`：脚本运行期间的临时文件。
- `.output/`：本次构建生成的发布候选产物。

