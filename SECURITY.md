# 安全策略

## 适用范围

本仓库生成并发布可被客户端直接订阅的规则产物(域名与 IP 规则集),内容来自公开上游数据与社区维护的自定义规则。潜在安全问题主要集中在:

- 产物内容被篡改或注入恶意条目
- 上游数据源被劫持或投毒
- 构建/发布流水线凭证泄露

## 报告漏洞

请勿公开披露安全相关问题。请通过 GitHub 私信联系 <https://github.com/KuGouGo>,或直接联系仓库所有者:

- 描述问题、影响范围与复现方式
- 附上受影响的产物/文件路径

## 响应流程

1. 确认问题并评估影响
2. 针对流水线与数据来源完成修复
3. 受影响的上游来源将暂时隔离,直至确认可信
4. 修复完成后发布公开说明(如需)

## 上游依赖

- 域名规则:[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)(MIT)
- 数据来源与健康策略见 [`config/upstreams.json`](config/upstreams.json) 与 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
