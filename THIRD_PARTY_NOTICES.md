# 第三方来源

仓库代码使用 [MIT License](LICENSE)。下列上游数据仍遵循各自的许可证或服务条款，不因本仓库进行下载、合并或格式转换而变为 MIT 内容。

| 内容 | 来源 |
| --- | --- |
| 域名规则 | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT） |
| 中国大陆可直连域名补充 | [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) 发布的 `china-list.txt`（GPL-3.0；数据源为 [felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list)） |
| 中国 IP | <https://ispip.clang.cn/all_cn_ipv46.txt>、<https://ispip.clang.cn/all_cn_ipv46_apnic.txt>、[Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip) |
| Google IP | <https://www.gstatic.com/ipranges/goog.json> |
| Telegram IP | <https://core.telegram.org/resources/cidr.txt> |
| Cloudflare IP | <https://www.cloudflare.com/ips-v4>、<https://www.cloudflare.com/ips-v6> |
| AWS / CloudFront IP | <https://ip-ranges.amazonaws.com/ip-ranges.json> |
| Fastly IP | <https://api.fastly.com/public-ip-list> |
| GitHub IP | <https://api.github.com/meta> |
| Apple 网络范围 | <https://support.apple.com/en-us/101555> |
| ASN 前缀 | [RIPEstat](https://stat.ripe.net/) |

除 v2fly/domain-list-community 明确使用 MIT License 外，本仓库不对其他上游数据的再分发许可作保证。使用者应自行确认相关条款。

`fakeip-filter`、`emby`、`emby-cn` 和 `apple-apns` 的本地源位于 `sources/custom/`。当前完整上游配置以 [`config/upstreams.json`](config/upstreams.json) 为准。
