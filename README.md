# Rules / Quantumult X

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic.list | 8 |
| domain/apple-apns.list | 2 |
| domain/apple-intelligence.list | 5 |
| domain/apple.list | 1585 |
| domain/apple@cn.list | 235 |
| domain/bahamut.list | 5 |
| domain/category-ads-all.list | 907 |
| domain/category-ai-chat-!cn.list | 179 |
| domain/cloudflare.list | 76 |
| domain/cn.list | 6055 |
| domain/discord.list | 28 |
| domain/disney.list | 222 |
| domain/emby.list | 10 |
| domain/epicgames.list | 30 |
| domain/facebook.list | 394 |
| domain/fakeip-filter.list | 87 |
| domain/geolocation-!cn.list | 23737 |
| domain/geolocation-!cn@cn.list | 597 |
| domain/github.list | 59 |
| domain/google-gemini.list | 41 |
| domain/google.list | 846 |
| domain/google@cn.list | 117 |
| domain/hbo.list | 65 |
| domain/icloud.list | 53 |
| domain/instagram.list | 72 |
| domain/microsoft.list | 640 |
| domain/microsoft@cn.list | 88 |
| domain/mihoyo.list | 23 |
| domain/netflix.list | 24 |
| domain/onedrive.list | 11 |
| domain/openai.list | 22 |
| domain/oracle.list | 19 |
| domain/paypal.list | 245 |
| domain/primevideo.list | 23 |
| domain/private.list | 130 |
| domain/reddit.list | 12 |
| domain/speedtest.list | 13 |
| domain/spotify.list | 25 |
| domain/steam.list | 59 |
| domain/steam@cn.list | 10 |
| domain/telegram.list | 21 |
| domain/tiktok.list | 35 |
| domain/twitter.list | 24 |
| domain/whatsapp.list | 11 |
| domain/xai.list | 4 |
| domain/xbox.list | 45 |
| domain/youtube.list | 177 |
| ip/apple.list | 4 |
| ip/cloudflare.list | 22 |
| ip/cloudfront.list | 211 |
| ip/cn.list | 8930 |
| ip/fastly.list | 21 |
| ip/google.list | 145 |
| ip/private.list | 18 |
| ip/telegram.list | 12 |

本分支存放 Quantumult X 客户端的自动构建产物。产物由 `main` 分支的持续集成流水线生成，并在每次推送 `main` 时整批覆盖更新；分支仅包含 `README.md`、`domain/` 与 `ip/`。如需固定版本，可锁定具体提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 与 `ip/` 使用 `.list` 格式。
- 域名规则：转换为 `HOST`、`HOST-SUFFIX`、`HOST-KEYWORD`；`DOMAIN-REGEX` 不写入产物，仅含正则的列表不会发布。
- IP 规则：支持 `IP-CIDR`、`IP6-CIDR`；第三字段为规则文件名，建议使用 `force-policy` 覆盖占位策略。
- 产物面向 Quantumult X 生成，不能假定与其他客户端的规则格式兼容。

## 最小示例

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```

## 域名数据 MIT 通知

本分支的域名产物包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游许可文本见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
