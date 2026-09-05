# Rules / Egern

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic.yaml | 8 |
| domain/apple-apns.yaml | 2 |
| domain/apple-intelligence.yaml | 5 |
| domain/apple.yaml | 1585 |
| domain/apple@cn.yaml | 235 |
| domain/bahamut.yaml | 5 |
| domain/category-ads-all.yaml | 908 |
| domain/category-ai-chat-!cn.yaml | 180 |
| domain/cloudflare.yaml | 76 |
| domain/cn.yaml | 6058 |
| domain/discord.yaml | 28 |
| domain/disney.yaml | 223 |
| domain/emby.yaml | 10 |
| domain/epicgames.yaml | 33 |
| domain/facebook.yaml | 394 |
| domain/fakeip-filter.yaml | 114 |
| domain/geolocation-!cn.yaml | 23888 |
| domain/geolocation-!cn@cn.yaml | 602 |
| domain/github.yaml | 59 |
| domain/google-gemini.yaml | 41 |
| domain/google.yaml | 848 |
| domain/google@cn.yaml | 119 |
| domain/hbo.yaml | 65 |
| domain/icloud.yaml | 53 |
| domain/instagram.yaml | 72 |
| domain/microsoft.yaml | 640 |
| domain/microsoft@cn.yaml | 88 |
| domain/mihoyo.yaml | 24 |
| domain/netflix.yaml | 28 |
| domain/onedrive.yaml | 11 |
| domain/openai.yaml | 23 |
| domain/oracle.yaml | 19 |
| domain/paypal.yaml | 245 |
| domain/primevideo.yaml | 23 |
| domain/private.yaml | 131 |
| domain/reddit.yaml | 12 |
| domain/speedtest.yaml | 14 |
| domain/spotify.yaml | 25 |
| domain/steam.yaml | 59 |
| domain/steam@cn.yaml | 10 |
| domain/telegram.yaml | 21 |
| domain/tiktok.yaml | 35 |
| domain/twitter.yaml | 24 |
| domain/whatsapp.yaml | 11 |
| domain/xai.yaml | 4 |
| domain/xbox.yaml | 45 |
| domain/youtube.yaml | 177 |
| ip/apple.yaml | 4 |
| ip/cloudflare.yaml | 22 |
| ip/cloudfront.yaml | 211 |
| ip/cn.yaml | 8930 |
| ip/fastly.yaml | 21 |
| ip/google.yaml | 145 |
| ip/private.yaml | 18 |
| ip/telegram.yaml | 12 |

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
