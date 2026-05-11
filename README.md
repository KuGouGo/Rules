# Rules

多平台代理规则构建仓库。

## Quick Start

```bash
make help
make validate
make preflight
make build-custom-text
```

`make build-custom` 会构建完整自定义规则产物，包括 `sing-box`/`mihomo` 二进制规则；首次运行可能会下载外部编译工具。只想检查文本产物时使用 `make build-custom-text`。

## Paths

- `sources/custom/domain/*.list`：自定义域名规则
- `sources/custom/ip/*.list`：自定义 IP 规则
- `scripts/`：同步、构建、测试、发布脚本
- `config/`：构建校验配置
- `tests/fixtures/`：测试夹具
- `docs/STRUCTURE.md`：仓库结构与构建流程说明
- `CONTRIBUTING.md`：规则贡献与本地校验说明

## Commands

```bash
make help
make lint
make test
make validate
make preflight
make build-custom-text
make build-custom
make clean
```

## Rule Sources

```text
sources/custom/domain/example.list
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,example
DOMAIN-REGEX,^(.+\.)?example\.com$

sources/custom/ip/example.list
IP-CIDR,1.2.3.0/24
IP-CIDR6,2001:db8::/32
```

## Output URL

```text
https://raw.githubusercontent.com/KuGouGo/Rules/{platform}/{type}/{name}.{ext}
```

- `platform`: `surge` | `quanx` | `egern` | `sing-box` | `mihomo`
- `type`: `domain` | `ip`
- `ext`: `list` | `yaml` | `srs` | `mrs`

## Output Matrix

| Platform | Domain | IP |
| --- | --- | --- |
| Surge | `domain/{name}.list` | `ip/{name}.list` |
| Quantumult X | `domain/{name}.list` | `ip/{name}.list` |
| Egern | `domain/{name}.yaml` | `ip/{name}.yaml` |
| sing-box | `domain/{name}.srs` | `ip/{name}.srs` |
| mihomo | `domain/{name}.mrs` | `ip/{name}.mrs` |

## Development

- 仓库结构见 [docs/STRUCTURE.md](docs/STRUCTURE.md)。
- 贡献规则或改脚本前，先看 [CONTRIBUTING.md](CONTRIBUTING.md)。
- `make lint` 会同时检查脚本语法、Python 工具、自定义规则质量和配置文件。
- 新增测试脚本命名为 `scripts/tests/test-*.sh`，`make test` 会自动发现。
