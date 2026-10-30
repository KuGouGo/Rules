# 第三方来源与许可范围

仓库自己的代码、文档和原创规则用 [MIT License](LICENSE)。从上游取来的数据、规则、服务响应和商标不是 MIT 内容，合并、转换之后也不变成 MIT，各自仍遵循原来的版权和条款。除了明确以 MIT 授权的来源，其余数据能不能再分发，使用前请自己核对。

下面是已知的第三方来源。这份清单可能不全，只供参考，不是法律意见。

| 内容 | 来源 |
| --- | --- |
| 域名规则 | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License） |
| Fake-IP 过滤列表 `fakeip-filter` | [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash) 的 `public/fake_ip_filter.list` |
| 中国 IP | Clang.CN 的 [IPv4+IPv6 合并列表](https://ispip.clang.cn/all_cn_ipv46.txt)及 [APNIC 注册分配基线](https://ispip.clang.cn/all_cn_ipv46_apnic.txt) |
| 中国 IP 补充 `cn` | [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip)，基于 CERNET/BGP 数据每天汇聚的中国运营商 CIDR |
| 中国 IP 补充 `cn` | [misakaio/chnroutes2](https://github.com/misakaio/chnroutes2)，从 APNIC BGP 数据提取的中国路由段 |
| 中国 IP 补充 `cn` | [17mon/china_ip_list](https://github.com/17mon/china_ip_list)，iPIP 的免费中国 IPv4 列表，仓库没有声明许可，按实用地理视角收录注册表之外的中国实用段 |
| Google / Telegram / Apple IP | [iptoasn.com](https://iptoasn.com/) 的 IP2ASN 数据库（PDDL v1.0，公有领域），基于 Route Views / RIPE RIS 的 BGP 路由，每小时更新，按 [`config/upstreams.json`](config/upstreams.json) 的 `asn_groups` 提取 |

`private` 的 IP 是仓库自己维护的（[`sources/custom/ip/`](sources/custom/ip)），不从远程抓取。apple、google、telegram 的 IP 段从 iptoasn 的 BGP 快照按 ASN 提取，每天的构建自动更新。

上游内容随时会变，使用时自己评估，留一份可以回退的版本。
