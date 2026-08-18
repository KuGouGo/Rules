# 第三方来源

仓库代码使用 [MIT License](LICENSE)。下列上游数据遵循各自许可或条款，不因本仓库下载、合并或转换而变为 MIT 内容。除明确以 MIT 授权的来源外，本仓库不保证其他数据可再分发；使用前请自行核实相关条款。

| 内容 | 来源 |
| --- | --- |
| 域名规则 | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License） |
| Fake-IP 过滤列表 `fakeip-filter` | [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash) 的 `public/fake_ip_filter.list` |
| 中国 IP | Clang.CN 的完整 [IPv4](https://ispip.clang.cn/all_cn.txt) / [IPv6](https://ispip.clang.cn/all_cn_ipv6.txt) 列表及 [APNIC 注册分配基线](https://ispip.clang.cn/all_cn_ipv46_apnic.txt) |
| Google / Telegram / Cloudflare / CloudFront / Fastly IP | 各官方发布地址（见 [`config/upstreams.json`](config/upstreams.json)） |
| ASN 前缀 | [RIPEstat](https://stat.ripe.net/) |

> `apple` IP 为仓库内置自定义源（`sources/builtin/ip/apple.list`），源自 Apple 官方网络范围页面，不依赖远程抓取。

上游内容可能随时变化，使用者应自行评估并保留可回退版本。
