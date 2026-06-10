# Rules

<p align="center">
  <a href="https://github.com/KuGouGo/Rules/actions/workflows/build.yml"><img alt="Sync Rules" src="https://github.com/KuGouGo/Rules/actions/workflows/build.yml/badge.svg"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Surge%20%7C%20QuanX%20%7C%20Egern%20%7C%20sing--box%20%7C%20mihomo-2f6f6f">
  <img alt="Artifacts" src="https://img.shields.io/badge/artifacts-domain%20%7C%20ip-4b5563">
</p>

一份规则源，多端规则产物。仓库面向日常代理客户端使用，尽量在不同客户端之间保持规则命名、来源和更新节奏一致。

本仓库维护自定义规则，定时同步可信上游，生成 Surge、Quantumult X、Egern、sing-box、mihomo 可直接引用的规则集。构建流程会统一做规则标准化、平台格式转换、二进制编译、完整性守卫和分支发布。

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

规则名称保留上游语义：

- `*-cn` / `*-!cn` 是上游已有的区域列表，例如 `geolocation-cn`、`geolocation-!cn`。
- `name@cn`、`name@!cn`、`name@ads` 是从上游属性标签派生的筛选列表，例如 `apple@cn`、`alibaba@!cn`、`apple@ads`。
- 区域列表也会保留非冗余属性筛选，例如 `geolocation-cn@!cn`、`geolocation-!cn@cn`。
- `@!cn` 是普通属性名，不是对 `@cn` 取反。上游 `include:list @-!cn` 这类语法才表示排除 `!cn` 属性。
- 冗余派生不会发布，例如 `cn@cn`、`geolocation-cn@cn`、`geolocation-!cn@!cn`。

## 产物矩阵

| 平台 | 域名规则 | IP 规则 | 说明 |
| --- | --- | --- | --- |
| Surge | `domain/{name}.list` | `ip/{name}.list` | Classical rule-set；域名规则保留 `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD` |
| Quantumult X | `domain/{name}.list` | `ip/{name}.list` | `HOST` / `HOST-SUFFIX` / `HOST-KEYWORD`，带显式策略字段 |
| Egern | `domain/{name}.yaml` | `ip/{name}.yaml` | YAML rule-set；域名规则保留 suffix、full、keyword、regex |
| sing-box | `domain/{name}.srs` | `ip/{name}.srs` | Binary rule-set；域名规则保留 suffix、full、keyword、regex |
| mihomo | `domain/{name}.mrs` | `ip/{name}.mrs` | Binary rule-provider；域名 `.mrs` 保留 domain/full/suffix 类匹配 |

平台能力不完全相同。若某个域名列表只包含 `DOMAIN-REGEX`，Surge、Quantumult X 和 mihomo `.mrs` 不会发布空规则；Egern 和 sing-box 会保留完整规则。mihomo 继续只发布 `.mrs`，以保持客户端配置简单、加载快、行为稳定。

mihomo 示例：

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/cn.mrs
    interval: 86400
```

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

## 构建守卫

构建会在发布前检查关键不变量：

- v2fly `domain-list-community/data` 必须作为域名上游，以保留 `@cn`、`@!cn`、`@ads` 等属性信息。
- 派生规则数量和代表性文件必须存在，例如 `apple@cn`、`apple@ads`、`alibaba@!cn`、`geolocation-cn@!cn`、`geolocation-!cn@cn`。
- 各平台不会发布冗余属性筛选文件，例如 `geolocation-cn@cn`。
- IP 规则会检查 CIDR 族、非公网地址泄漏和核心上游条目数量。
- 发布分支只包含目标客户端需要的最终产物和 README。

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
