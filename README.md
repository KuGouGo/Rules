# Rules / sing-box

这里放 sing-box 的自动构建产物，每次推送 `main` 都会整批覆盖更新。里面只有 `README.md`、`domain/` 和 `ip/`；想固定版本就锁定提交 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 与 `ip/` 均使用二进制 `.srs` 扩展名。
- 域名规则：保留精确域名、域名后缀、域名关键词和域名正则。
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

## v2fly/domain-list-community MIT 通知

本分支的域名产物包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），完整许可文本见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
