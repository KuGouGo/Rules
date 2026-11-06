# Rules / Egern

本分支存放 Egern 专用规则，每日随 `main` 分支重新构建并整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。如需固定版本，可将订阅地址中的分支名替换为对应提交的 SHA。

## 规则说明

- **文件格式**：`domain/` 与 `ip/` 均为 `.yaml` 规则集。
- **域名规则**：包含 `domain_set`、`domain_suffix_set`、`domain_keyword_set`、`domain_regex_set`。
- **IP 规则**：包含 `ip_cidr_set`（IPv4）与 `ip_cidr6_set`（IPv6），默认启用 `no_resolve: true`。

## 配置示例

```yaml
rules:
  - rule_set:
      match: "https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml"
      policy: DIRECT
  - rule_set:
      match: "https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml"
      policy: DIRECT
```

<!-- artifact-table -->

## 许可与来源

- 项目说明与许可范围见 [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)、[LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE) 与 [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)。
- 域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（[MIT License](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)）。
