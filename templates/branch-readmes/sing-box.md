# Rules / sing-box

<!-- artifact-table -->

这里是 sing-box 用的规则，每天跟着 `main` 重新构建，整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。想钉住某一天的结果，订阅地址里的分支名换成那个提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 和 `ip/` 都是二进制 `.srs`。
- 域名四类都保留：精确域名、后缀、关键词、正则。
- IP 保留 IPv4 和 IPv6 的 CIDR。
- 这份产物只给 sing-box 用，是二进制格式，和别的客户端不通用。配置字段以你所用版本的官方 schema 为准。

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

这里的域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游的许可原文见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
