# 第三方数据来源与许可说明

本仓库的代码、文档及自维护规则（[`sources/custom/`](sources/custom)）采用 [MIT License](LICENSE) 授权。

从外部上游获取的数据及其转换产物仍遵循原项目的版权与许可条款，不因本仓库的合并或格式转换而变为 MIT 授权。除明确声明开源许可的数据源外，如需二次分发请自行核实上游条款。

## 上游数据源

| 规则类别 | 上游来源 | 说明与许可 |
| --- | --- | --- |
| 域名规则 (`domain/*`) | [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) | 社区维护的域名分流规则库（MIT License） |
| Fake-IP 过滤 (`domain/fakeip-filter`) | [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash) | `public/fake_ip_filter.list` 过滤列表 |
| 中国大陆 IP (`ip/cn`) | [Clang.CN](https://ispip.clang.cn/) | [中国 IPv4/IPv6 合并列表](https://ispip.clang.cn/all_cn_ipv46.txt)与 [APNIC 分配基线](https://ispip.clang.cn/all_cn_ipv46_apnic.txt) |
| 中国大陆 IP (`ip/cn`) | [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip) | 基于 CERNET / BGP 数据每日构建的中国运营商 CIDR |
| 中国大陆 IP (`ip/cn`) | [misakaio/chnroutes2](https://github.com/misakaio/chnroutes2) | 基于 APNIC BGP 数据提取的中国大陆路由段 |
| 中国大陆 IP (`ip/cn`) | [17mon/china_ip_list](https://github.com/17mon/china_ip_list) | IPIP.net 维护的免费中国大陆 IPv4 列表 |
| 服务 IP (`ip/apple`、`ip/google`、`ip/telegram`) | [iptoasn.com](https://iptoasn.com/) | 基于 BGP 路由的 IP2ASN 数据库（PDDL v1.0 公有领域），按 [`config/upstreams.json`](config/upstreams.json) 中的 ASN 提取 |
