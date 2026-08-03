# Rules / Egern

这里放 Egern 的自动构建产物，每次推送 `main` 都会整批覆盖更新。里面只有 `README.md`、`domain/` 和 `ip/`；想固定版本就锁定提交 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 与 `ip/` 均使用 `.yaml` 扩展名。
- 域名规则：支持 `domain_set`、`domain_suffix_set`、`domain_keyword_set`、`domain_regex_set` 四类。
- IP 规则：支持 `ip_cidr_set`、`ip_cidr6_set`，区分 IPv4 与 IPv6。
- 产物面向 Egern 生成，不能假定与其他客户端的规则格式兼容；本分支只提供规则集数据，不包含完整客户端配置。

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

## v2fly/domain-list-community MIT 通知

本分支的域名产物包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），完整许可文本见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
