# Rules / Surge

本分支存放 Surge 专用规则，每日随 `main` 分支重新构建并整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。如需固定版本，可将订阅地址中的分支名替换为对应提交的 SHA。

## 规则说明

- **文件格式**：`domain/` 与 `ip/` 均为 `.list` 文本规则集。
- **域名规则**：包含 `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD`（不含 `DOMAIN-REGEX`）。
- **IP 规则**：包含 `IP-CIDR`、`IP-CIDR6`，默认附带 `no-resolve`。

## 配置示例

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```

<!-- artifact-table -->

## 许可与来源

- 项目说明与许可范围见 [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)、[LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE) 与 [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)。
- 域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（[MIT License](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)）。
