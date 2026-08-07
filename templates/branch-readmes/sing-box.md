# Rules / sing-box

本分支存放 sing-box 客户端的自动构建产物。产物由 `main` 分支的持续集成流水线生成，并在每次推送 `main` 时整批覆盖更新；分支仅包含 `README.md`、`domain/` 与 `ip/`。如需固定版本，可锁定具体提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 与 `ip/` 使用二进制 `.srs` 格式。
- 域名规则：保留精确域名、域名后缀、域名关键词与域名正则。
- IP 规则：保留 IPv4 与 IPv6 CIDR。
- 产物面向 sing-box 生成，为二进制格式，不能假定与其他客户端的规则格式兼容；配置字段以所用版本的官方 schema 为准。

## 最小示例

```json
{
  "route": {
    "rule_set": [
      { "tag": "cn", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs" },
      { "tag": "cn-ip", "type": "remote", "format": "binary", "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/cn.srs" }
    ]
  }
}
```

## 域名数据 MIT 通知

本分支的域名产物包含或派生自 [nekolsd/dlc2](https://github.com/nekolsd/dlc2)（MIT License，v2fly/domain-list-community 的干净分支），上游许可文本见 [LICENSE](https://github.com/nekolsd/dlc2/blob/master/LICENSE)。
