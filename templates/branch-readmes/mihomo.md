# Rules / mihomo

本分支存放 mihomo 客户端的自动构建产物。产物由 `main` 分支的持续集成流水线生成，并在每次推送 `main` 时整批覆盖更新；分支仅包含 `README.md`、`domain/` 与 `ip/`。如需固定版本，可锁定具体提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 与 `ip/` 使用二进制 `.mrs` 格式。
- 域名规则：仅保留精确域名与域名后缀；域名关键词与正则会降级丢弃，仅含这些类型的列表不会发布。
- IP 规则：保留 IPv4 与 IPv6 CIDR。
- 产物面向 mihomo 生成，为二进制格式，不能假定与其他客户端的规则格式兼容。

## 最小示例

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/cn.mrs
  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/cn.mrs
```

## v2fly/domain-list-community MIT 通知

本分支的域名产物包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），完整许可文本见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
