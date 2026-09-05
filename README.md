# Rules / mihomo

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic | 8 |
| domain/apple-apns | 2 |
| domain/apple-intelligence | 5 |
| domain/apple | 1585 |
| domain/apple@cn | 235 |
| domain/bahamut | 5 |
| domain/category-ads-all | 908 |
| domain/category-ai-chat-!cn | 180 |
| domain/cloudflare | 76 |
| domain/cn | 6058 |
| domain/discord | 28 |
| domain/disney | 223 |
| domain/emby | 10 |
| domain/epicgames | 33 |
| domain/facebook | 394 |
| domain/fakeip-filter | 114 |
| domain/geolocation-!cn | 23888 |
| domain/geolocation-!cn@cn | 602 |
| domain/github | 59 |
| domain/google-gemini | 41 |
| domain/google | 848 |
| domain/google@cn | 119 |
| domain/hbo | 65 |
| domain/icloud | 53 |
| domain/instagram | 72 |
| domain/microsoft | 640 |
| domain/microsoft@cn | 88 |
| domain/mihoyo | 24 |
| domain/netflix | 28 |
| domain/onedrive | 11 |
| domain/openai | 23 |
| domain/oracle | 19 |
| domain/paypal | 245 |
| domain/primevideo | 23 |
| domain/private | 131 |
| domain/reddit | 12 |
| domain/speedtest | 14 |
| domain/spotify | 25 |
| domain/steam | 59 |
| domain/steam@cn | 10 |
| domain/telegram | 21 |
| domain/tiktok | 35 |
| domain/twitter | 24 |
| domain/whatsapp | 11 |
| domain/xai | 4 |
| domain/xbox | 45 |
| domain/youtube | 177 |
| ip/apple | 4 |
| ip/cloudflare | 22 |
| ip/cloudfront | 211 |
| ip/cn | 8930 |
| ip/fastly | 21 |
| ip/google | 145 |
| ip/private | 18 |
| ip/telegram | 12 |

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

## 域名数据 MIT 通知

本分支的域名产物包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游许可文本见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
