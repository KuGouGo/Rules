# 第三方来源与许可范围

本仓库代码使用 [MIT License](LICENSE) 授权，且仅覆盖仓库自有的代码、文档与原创规则内容。第三方数据、规则、服务响应、商标及其派生产物不因本仓库下载、合并或转换而变为 MIT 内容，仍遵循各自的版权、许可与条款；除明确以 MIT 授权的来源外，本仓库不保证其他数据可再分发，使用前请自行核实相关条款。

下列上游数据为已知第三方来源（记录可能不完整，仅供参考，不构成法律意见）：

| 内容 | 来源 |
| --- | --- |
| 域名规则 | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License） |
| Fake-IP 过滤列表 `fakeip-filter` | [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash) 的 `public/fake_ip_filter.list` |
| 中国 IP | Clang.CN 的完整 [IPv4](https://ispip.clang.cn/all_cn.txt) / [IPv6](https://ispip.clang.cn/all_cn_ipv6.txt) 列表及 [APNIC 注册分配基线](https://ispip.clang.cn/all_cn_ipv46_apnic.txt) |
| 中国 IP 补充 `cn` | [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip) 的 `release/text/cn.txt`（CC-BY-SA-4.0，聚合 chnroutes2 / ipip / APNIC 等多源） |
| 中国 IP 补充 `cn` | [17mon/china_ip_list](https://github.com/17mon/china_ip_list)（iPIP 免费中国 IPv4 列表，仓库未声明许可，按实用地理视角收录注册表视角之外的中国实用段） |
| Google / Telegram IP | 各官方发布地址（见 [`config/upstreams.json`](config/upstreams.json)） |
| ASN 前缀 | [RIPEstat](https://stat.ripe.net/) |

> `apple` 与 `private` IP 为仓库自维护列表（[`sources/custom/ip/`](sources/custom/ip)），不依赖远程抓取。

上游内容可能随时变化，使用者应自行评估并保留可回退版本。
