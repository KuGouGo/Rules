# Rules / sing-box

本分支存放 sing-box 专用规则，每日随 `main` 分支重新构建并整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。如需固定版本，可将订阅地址中的分支名替换为对应提交的 SHA。

## 规则说明

- **文件格式**：`domain/` 与 `ip/` 均为官方编译器生成的二进制 `.srs` 规则集。
- **域名规则**：包含精确域名、后缀、关键词与正则四类规则。
- **IP 规则**：包含 IPv4 与 IPv6 CIDR。

## 配置示例

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

<!-- artifact-table -->

## 许可与来源

- 项目说明与许可范围见 [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)、[LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE) 与 [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)。
- 域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（[MIT License](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)）。
