# 第三方来源

仓库代码使用 [MIT License](LICENSE)。下列上游数据遵循各自许可或条款，不因本仓库下载、合并或转换而变为 MIT 内容。除明确以 MIT 授权的来源外，本仓库不保证其他数据可再分发；使用前请自行核实相关条款。

| 内容 | 来源 |
| --- | --- |
| 域名规则 | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT） |
| 域名属性过滤策略参考 | [Loyalsoldier/domain-list-custom](https://github.com/Loyalsoldier/domain-list-custom)（GPL-3.0；不直接分发其构建产物） |
| 中国大陆 DNS 分流域名 `china-list` | [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) 的 `china-list.txt`（GPL-3.0） |
| Fake-IP 过滤列表 `fakeip-filter` | [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash) 的 `public/fake_ip_filter.list` |
| 中国 IP | <https://ispip.clang.cn/all_cn_ipv46.txt>、<https://ispip.clang.cn/all_cn_ipv46_apnic.txt> |
| Google / Telegram / Cloudflare / AWS / Fastly / Apple IP | 各官方发布地址（见 [`config/upstreams.json`](config/upstreams.json)） |
| ASN 前缀 | [RIPEstat](https://stat.ripe.net/) |

上游内容可能随时变化，使用者应自行评估并保留可回退版本。
