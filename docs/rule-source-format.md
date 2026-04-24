# 自定义规则格式

本仓库从 `sources/custom/domain/*.list` 与 `sources/custom/ip/*.list` 读取自定义规则，并在构建时转换为 Surge、Quantumult X、Egern、sing-box 与 mihomo 产物。

## 通用规则

- 文件扩展名必须是 `.list`。
- 空行会被忽略。
- `#` 后面的内容视为注释。
- 重复规则会在构建时去重，并保留首次出现的顺序。
- 文件名会成为输出规则名，例如 `sources/custom/domain/emby.list` 生成 `emby` 相关产物。

## 域名规则

域名规则放在 `sources/custom/domain/`，支持以下前缀：

```text
DOMAIN,example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,keyword
DOMAIN-REGEX,^(.+\.)?example\.com$
```

构建行为：

- `DOMAIN` 与 `DOMAIN-SUFFIX` 会转换为小写并移除结尾的 `.`。
- `DOMAIN-KEYWORD` 会转换为小写。
- `DOMAIN-REGEX` 保留原始表达式内容。
- Surge、Quantumult X 与 mihomo 只输出其支持的域名规则类型。
- Egern 与 sing-box 会保留更完整的域名规则类型。

## IP 规则

IP 规则放在 `sources/custom/ip/`，支持以下前缀：

```text
IP-CIDR,1.2.3.0/24
IP-CIDR6,2001:db8::/32
IP6-CIDR,2001:db8::/32
```

构建行为：

- IPv4 CIDR 输出为 `IP-CIDR`。
- IPv6 CIDR 输出为 `IP-CIDR6` 或目标平台对应格式。
- Surge 输出默认附加 `no-resolve`，可通过 `SURGE_IP_APPEND_NO_RESOLVE=0` 做对比验证。
- 自定义 IP 文件会由 `scripts/lint-custom-rules.sh` 使用 Python `ipaddress` 校验。

## 本地校验

修改规则后建议运行：

```bash
shellcheck scripts/*.sh scripts/lib/*.sh
scripts/lint-custom-rules.sh
scripts/test-domain-parsing.sh
scripts/build-custom.sh
```

