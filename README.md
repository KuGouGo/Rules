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

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic | 21 |
| domain/apple-apns | 2 |
| domain/apple-intelligence | 5 |
| domain/apple | 1584 |
| domain/apple@cn | 238 |
| domain/bahamut | 5 |
| domain/category-ai-chat-!cn | 216 |
| domain/cloudflare | 76 |
| domain/cn | 6219 |
| domain/discord | 28 |
| domain/disney | 223 |
| domain/emby | 10 |
| domain/epicgames | 33 |
| domain/facebook | 395 |
| domain/fakeip-filter | 114 |
| domain/geolocation-!cn | 24082 |
| domain/geolocation-!cn@cn | 623 |
| domain/github | 59 |
| domain/google-gemini | 49 |
| domain/google | 849 |
| domain/google@cn | 119 |
| domain/hbo | 65 |
| domain/icloud | 52 |
| domain/instagram | 72 |
| domain/microsoft | 640 |
| domain/microsoft@cn | 88 |
| domain/netflix | 28 |
| domain/openai | 25 |
| domain/oracle | 19 |
| domain/paypal | 245 |
| domain/primevideo | 24 |
| domain/private | 133 |
| domain/reddit | 12 |
| domain/speedtest | 21 |
| domain/spotify | 25 |
| domain/steam | 60 |
| domain/steam@cn | 10 |
| domain/telegram | 21 |
| domain/tiktok | 39 |
| domain/twitter | 24 |
| domain/whatsapp | 11 |
| domain/xai | 4 |
| domain/youtube | 177 |
| ip/apple | 21 |
| ip/cn | 9114 |
| ip/google | 928 |
| ip/private | 18 |
| ip/telegram | 12 |

## 许可与来源

- 项目说明与许可范围见 [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)、[LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE) 与 [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)。
- 域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（[MIT License](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)）。
