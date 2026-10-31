# Rules / mihomo

## 产物清单

| 列表 | 条目数 |
| --- | ---: |
| domain/anthropic | 19 |
| domain/apple-apns | 2 |
| domain/apple-intelligence | 5 |
| domain/apple | 1584 |
| domain/apple@cn | 237 |
| domain/bahamut | 5 |
| domain/category-ai-chat-!cn | 214 |
| domain/cloudflare | 76 |
| domain/cn | 6144 |
| domain/discord | 28 |
| domain/disney | 223 |
| domain/emby | 10 |
| domain/epicgames | 33 |
| domain/facebook | 395 |
| domain/fakeip-filter | 114 |
| domain/geolocation-!cn | 24064 |
| domain/geolocation-!cn@cn | 622 |
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
| ip/cn | 9113 |
| ip/google | 1070 |
| ip/private | 18 |
| ip/telegram | 12 |

这里是 mihomo 用的规则，每天跟着 `main` 重新构建，整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。想钉住某一天的结果，订阅地址里的分支名换成那个提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 和 `ip/` 都是二进制 `.mrs`。
- 域名只保留精确域名和后缀。关键词和正则会被丢掉；一个列表如果只剩这两类，整份不发布。
- IP 保留 IPv4 和 IPv6 的 CIDR。
- 这份产物只给 mihomo 用，是二进制格式，和别的客户端不通用。

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

这里的域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游的许可原文见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
