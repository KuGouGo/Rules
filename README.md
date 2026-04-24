# Rules

多平台代理规则构建仓库。

## Paths

- `sources/custom/domain/*.list`：自定义域名规则
- `sources/custom/ip/*.list`：自定义 IP 规则
- `scripts/`：同步、构建、测试、发布脚本
- `config/`：构建校验配置
- `tests/fixtures/`：测试夹具

## Commands

```bash
make validate
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
