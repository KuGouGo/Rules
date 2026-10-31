# Rules / Quantumult X

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic.list | 19 |
| domain/apple-apns.list | 2 |
| domain/apple-intelligence.list | 5 |
| domain/apple.list | 1584 |
| domain/apple@cn.list | 237 |
| domain/bahamut.list | 5 |
| domain/category-ai-chat-!cn.list | 213 |
| domain/cloudflare.list | 76 |
| domain/cn.list | 6141 |
| domain/discord.list | 28 |
| domain/disney.list | 222 |
| domain/emby.list | 10 |
| domain/epicgames.list | 30 |
| domain/facebook.list | 395 |
| domain/fakeip-filter.list | 87 |
| domain/geolocation-!cn.list | 23913 |
| domain/geolocation-!cn@cn.list | 617 |
| domain/github.list | 59 |
| domain/google-gemini.list | 49 |
| domain/google.list | 847 |
| domain/google@cn.list | 117 |
| domain/hbo.list | 65 |
| domain/icloud.list | 52 |
| domain/instagram.list | 72 |
| domain/microsoft.list | 640 |
| domain/microsoft@cn.list | 88 |
| domain/netflix.list | 24 |
| domain/openai.list | 24 |
| domain/oracle.list | 19 |
| domain/paypal.list | 245 |
| domain/primevideo.list | 24 |
| domain/private.list | 132 |
| domain/reddit.list | 12 |
| domain/speedtest.list | 20 |
| domain/spotify.list | 25 |
| domain/steam.list | 60 |
| domain/steam@cn.list | 10 |
| domain/telegram.list | 21 |
| domain/tiktok.list | 39 |
| domain/twitter.list | 24 |
| domain/whatsapp.list | 11 |
| domain/xai.list | 4 |
| domain/youtube.list | 177 |
| ip/apple.list | 21 |
| ip/cn.list | 9113 |
| ip/google.list | 1070 |
| ip/private.list | 18 |
| ip/telegram.list | 12 |

这里是 Quantumult X 用的规则，每天跟着 `main` 重新构建，整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。想钉住某一天的结果，订阅地址里的分支名换成那个提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 和 `ip/` 都是 `.list`。
- 域名转成 `HOST`、`HOST-SUFFIX`、`HOST-KEYWORD`。`DOMAIN-REGEX` 不写入；一个列表如果只剩正则，整份不发布。
- IP 保留 `IP-CIDR`、`IP6-CIDR`。第三字段是规则文件名，实际策略用 `force-policy` 覆盖。
- 这份产物只给 Quantumult X 用，格式和别的客户端不通用。

## 最小示例

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```

## 域名数据 MIT 通知

这里的域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游的许可原文见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
