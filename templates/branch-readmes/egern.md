# Rules / Egern

<!-- artifact-table -->

本分支存放 Egern 客户端的自动构建产物。产物由 `main` 分支的持续集成流水线生成，并在每次推送 `main` 时整批覆盖更新；分支仅包含 `README.md`、`domain/` 与 `ip/`。如需固定版本，可锁定具体提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 与 `ip/` 使用 `.yaml` 格式。
- 域名规则：支持 `domain_set`、`domain_suffix_set`、`domain_keyword_set`、`domain_regex_set` 四类。
- IP 规则：支持 `ip_cidr_set`、`ip_cidr6_set`，区分 IPv4 与 IPv6。
- 产物面向 Egern 生成，不能假定与其他客户端的规则格式兼容；本分支仅提供规则集数据，不包含完整客户端配置。

## 最小示例

```yaml
rules:
  - rule_set:
      match: "https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml"
      policy: DIRECT
  - rule_set:
      match: "https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml"
      policy: DIRECT
```

## 域名数据 MIT 通知

本分支的域名产物包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游许可文本见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
