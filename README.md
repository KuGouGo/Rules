# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20QuanX%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="Artifacts" src="https://img.shields.io/badge/artifacts-domain%20%7C%20ip-4b5563">
</p>

一份规则源，多端规则产物。

本仓库用于维护自定义规则、同步可信上游、生成并发布多平台代理客户端可直接引用的规则集。构建流程会统一做规则标准化、平台格式转换、二进制编译、产物检查和分支发布。

## 快速使用

产物发布在客户端专用分支，URL 结构固定：

```text
https://raw.githubusercontent.com/KuGouGo/Rules/{platform}/{type}/{name}.{ext}
```

| 字段 | 可选值 |
| --- | --- |
| `platform` | `surge`, `quanx`, `egern`, `sing-box`, `mihomo` |
| `type` | `domain`, `ip` |
| `name` | 规则名称，例如 `cn`, `google`, `telegram`, `emby` |
| `ext` | `list`, `yaml`, `srs`, `mrs` |

常用示例：

```text
https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list
https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/google.srs
https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/emby.mrs
```

## 产物矩阵

| 平台 | 域名规则 | IP 规则 | 说明 |
| --- | --- | --- | --- |
| Surge | `domain/{name}.list` | `ip/{name}.list` | Classical rule-set |
| Quantumult X | `domain/{name}.list` | `ip/{name}.list` | 带显式策略字段 |
| Egern | `domain/{name}.yaml` | `ip/{name}.yaml` | YAML rule-set |
| sing-box | `domain/{name}.srs` | `ip/{name}.srs` | Binary rule-set |
| mihomo | `domain/{name}.mrs` | `ip/{name}.mrs` | Binary rule-provider |

## 本地维护

```bash
make help
make validate
make build-custom-text
```

`make validate` 会执行脚本语法检查、Python 编译检查、配置校验、自定义规则质量检查和测试套件。

`make build-custom-text` 只构建文本产物，适合快速检查自定义规则。需要完整二进制产物时运行：

```bash
make build-custom
```

完整推送前建议运行：

```bash
make preflight
```

## 规则源格式

自定义域名规则放在 `sources/custom/domain/*.list`：

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,example
DOMAIN-REGEX,^(.+\.)?example\.com$
```

自定义 IP 规则放在 `sources/custom/ip/*.list`：

```text
IP-CIDR,1.2.3.0/24
IP-CIDR6,2001:db8::/32
```

文件名只使用小写字母、数字和连字符，例如 `emby-cn.list`。规则质量要求和本地校验细节见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 仓库结构

| 路径 | 用途 |
| --- | --- |
| `sources/custom/` | 自定义域名和 IP 规则源 |
| `config/` | 上游来源、基线阈值、平台能力配置 |
| `scripts/commands/` | Makefile 和 GitHub Actions 使用的入口脚本 |
| `scripts/tools/` | 规则解析、归一化、分类、摘要工具 |
| `scripts/tests/` | 自动发现的 `test-*.sh` 测试 |
| `tests/fixtures/` | 稳定输入和期望输出夹具 |
| `.output/` | 本地生成产物，已忽略，不手动编辑 |

更完整的构建流程说明见 [docs/STRUCTURE.md](docs/STRUCTURE.md)。
