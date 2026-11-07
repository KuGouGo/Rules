# Rules / Quantumult X

本分支存放 Quantumult X 专用规则，每日随 `main` 分支重新构建并整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。如需固定版本，可将订阅地址中的分支名替换为对应提交的 SHA。

## 规则说明

- **文件格式**：`domain/` 与 `ip/` 均为 `.list` 文本规则集。
- **域名规则**：转换为 `HOST`、`HOST-SUFFIX`、`HOST-KEYWORD`（不含 `DOMAIN-REGEX`）。
- **IP 规则**：包含 `IP-CIDR`、`IP6-CIDR`（第三字段为规则名，请通过 `force-policy` 指定实际策略）。

## 配置示例

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic.list | 21 |
| domain/apple-apns.list | 2 |
| domain/apple-intelligence.list | 5 |
| domain/apple.list | 1584 |
| domain/apple@cn.list | 238 |
| domain/bahamut.list | 5 |
| domain/category-ai-chat-!cn.list | 215 |
| domain/cloudflare.list | 76 |
| domain/cn.list | 6216 |
| domain/discord.list | 28 |
| domain/disney.list | 222 |
| domain/emby.list | 10 |
| domain/epicgames.list | 30 |
| domain/facebook.list | 395 |
| domain/fakeip-filter.list | 87 |
| domain/geolocation-!cn.list | 23931 |
| domain/geolocation-!cn@cn.list | 618 |
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
| ip/cn.list | 9114 |
| ip/google.list | 928 |
| ip/private.list | 18 |
| ip/telegram.list | 12 |

## 许可与来源

- 项目说明与许可范围见 [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)、[LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE) 与 [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)。
- 域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（[MIT License](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)）。
