# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20Quantumult%20X%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
</p>

个人自用规则仓库：维护自定义规则，拉取并整合上游数据，自动生成多个客户端的规则文件。

> 客户端不要引用 `main`，请使用对应的产物分支。

## 产物

| 客户端 | 分支 | 格式 |
| --- | --- | --- |
| Surge | [`surge`](https://github.com/KuGouGo/Rules/tree/surge) | `.list` |
| Quantumult X | [`quanx`](https://github.com/KuGouGo/Rules/tree/quanx) | `.list` |
| Egern | [`egern`](https://github.com/KuGouGo/Rules/tree/egern) | `.yaml` |
| sing-box | [`sing-box`](https://github.com/KuGouGo/Rules/tree/sing-box) | `.srs` |
| mihomo | [`mihomo`](https://github.com/KuGouGo/Rules/tree/mihomo) | `.mrs` |

URL 格式：

```text
https://raw.githubusercontent.com/KuGouGo/Rules/{branch}/{domain|ip}/{name}.{extension}
```

示例：

```text
https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/emby-cn.list
https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/fakeip-filter.srs
https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/google.mrs
```

常用规则包括 `cn`、`geolocation-cn`、`geolocation-!cn`、`google`、`telegram`、`emby-cn`、`emby` 和 `fakeip-filter`。同时使用 `emby-cn` 与 `emby` 时，应先加载范围较小的 `emby-cn`。

## 添加自定义规则

- 域名规则：`sources/custom/domain/*.list`
- IP 规则：`sources/custom/ip/*.list`
- 文件名使用小写字母、数字和连字符。

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,example
DOMAIN-REGEX,^(.+\.)?example\.com$
IP-CIDR,192.0.2.0/24
IP-CIDR6,2001:db8::/32
```

不同文件可以按策略需要重叠；同一文件内不要保留重复或被更宽规则覆盖的条目。

## 本地检查

需要 Bash 5+、Python 3.11+、GNU Make 和 Git。

```bash
make check              # 日常快速检查
make validate           # 完整测试
make build-custom-text  # 预览自定义文本产物
make clean              # 清理生成文件
```

更多维护命令见 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。推送到 `main` 后，GitHub Actions 会自动构建并更新五个平台分支；每天也会定时同步一次上游。

## 声明

规则按现状提供，上游内容可能随时变化，请自行确认使用策略并保留回退版本。仓库代码使用 MIT License；第三方内容仍遵循各自条款，来源见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
