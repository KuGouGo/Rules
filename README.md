# Rules / Egern

本分支存放 Egern 专用规则，每日随 `main` 分支重新构建并整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。如需固定版本，可将订阅地址中的分支名替换为对应提交的 SHA。

## 规则说明

- **文件格式**：`domain/` 与 `ip/` 均为 `.yaml` 规则集。
- **域名规则**：包含 `domain_set`、`domain_suffix_set`、`domain_keyword_set`、`domain_regex_set`。
- **IP 规则**：包含 `ip_cidr_set`（IPv4）与 `ip_cidr6_set`（IPv6），默认启用 `no_resolve: true`。

## 配置示例

```yaml
rules:
  - rule_set:
      match: "https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml"
      policy: DIRECT
  - rule_set:
      match: "https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml"
      policy: DIRECT
```

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic.yaml | 21 |
| domain/apple-apns.yaml | 2 |
| domain/apple-intelligence.yaml | 5 |
| domain/apple.yaml | 1584 |
| domain/apple@cn.yaml | 238 |
| domain/bahamut.yaml | 5 |
| domain/category-ai-chat-!cn.yaml | 216 |
| domain/cloudflare.yaml | 76 |
| domain/cn.yaml | 6219 |
| domain/discord.yaml | 28 |
| domain/disney.yaml | 223 |
| domain/emby.yaml | 10 |
| domain/epicgames.yaml | 33 |
| domain/facebook.yaml | 395 |
| domain/fakeip-filter.yaml | 114 |
| domain/geolocation-!cn.yaml | 24082 |
| domain/geolocation-!cn@cn.yaml | 623 |
| domain/github.yaml | 59 |
| domain/google-gemini.yaml | 49 |
| domain/google.yaml | 849 |
| domain/google@cn.yaml | 119 |
| domain/hbo.yaml | 65 |
| domain/icloud.yaml | 52 |
| domain/instagram.yaml | 72 |
| domain/microsoft.yaml | 640 |
| domain/microsoft@cn.yaml | 88 |
| domain/netflix.yaml | 28 |
| domain/openai.yaml | 25 |
| domain/oracle.yaml | 19 |
| domain/paypal.yaml | 245 |
| domain/primevideo.yaml | 24 |
| domain/private.yaml | 133 |
| domain/reddit.yaml | 12 |
| domain/speedtest.yaml | 21 |
| domain/spotify.yaml | 25 |
| domain/steam.yaml | 60 |
| domain/steam@cn.yaml | 10 |
| domain/telegram.yaml | 21 |
| domain/tiktok.yaml | 39 |
| domain/twitter.yaml | 24 |
| domain/whatsapp.yaml | 11 |
| domain/xai.yaml | 4 |
| domain/youtube.yaml | 177 |
| ip/apple.yaml | 21 |
| ip/cn.yaml | 9114 |
| ip/google.yaml | 928 |
| ip/private.yaml | 18 |
| ip/telegram.yaml | 12 |

## 许可与来源

- 项目说明与许可范围见 [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)、[LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE) 与 [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)。
- 域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（[MIT License](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)）。
