# Rules / Egern

<!-- artifact-table -->

这里是 Egern 用的规则，每天跟着 `main` 重新构建，整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。想钉住某一天的结果，订阅地址里的分支名换成那个提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 和 `ip/` 都是 `.yaml`。
- 域名四类都保留：`domain_set`、`domain_suffix_set`、`domain_keyword_set`、`domain_regex_set`。
- IP 按地址族分开，`ip_cidr_set` 放 IPv4，`ip_cidr6_set` 放 IPv6。
- 这份产物只给 Egern 用，里面是规则集数据，不是一份完整的客户端配置。

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

这里的域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游的许可原文见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
