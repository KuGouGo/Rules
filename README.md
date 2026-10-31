# Rules / Egern

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic.yaml | 19 |
| domain/apple-apns.yaml | 2 |
| domain/apple-intelligence.yaml | 5 |
| domain/apple.yaml | 1584 |
| domain/apple@cn.yaml | 237 |
| domain/bahamut.yaml | 5 |
| domain/category-ai-chat-!cn.yaml | 214 |
| domain/cloudflare.yaml | 76 |
| domain/cn.yaml | 6144 |
| domain/discord.yaml | 28 |
| domain/disney.yaml | 223 |
| domain/emby.yaml | 10 |
| domain/epicgames.yaml | 33 |
| domain/facebook.yaml | 395 |
| domain/fakeip-filter.yaml | 114 |
| domain/geolocation-!cn.yaml | 24064 |
| domain/geolocation-!cn@cn.yaml | 622 |
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
| ip/cn.yaml | 9113 |
| ip/google.yaml | 1070 |
| ip/private.yaml | 18 |
| ip/telegram.yaml | 12 |

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
