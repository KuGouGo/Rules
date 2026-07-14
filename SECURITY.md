# 安全政策

本文件说明安全支持范围和私密报告方式。规则内容错误、许可核对和一般构建失败分别按质量或治理问题处理。

## 支持范围

仅当前 `main` 及当前自动化生成的五个本仓库维护的发布分支受支持。历史提交、第三方分叉、镜像、用户修改规则和非支持环境不在支持范围内。

可能导致凭据泄露、工作流或发布分支被接管、任意代码执行、供应链污染或绕过发布守卫的问题属于安全问题。规则误分流、上游失效、普通构建错误和许可状态未知通常不是安全漏洞，请使用普通 Issue 或 Pull Request，但不要公开敏感信息。

工具下载当前依赖 GitHub Release 的 HTTPS 资产和版本匹配，不验证校验和。若发现资产替换、下载链路劫持或缓存投毒证据，请按安全问题私密报告。

## 私密报告

优先通过 [GitHub Security Advisory](https://github.com/KuGouGo/Rules/security/advisories/new) 私密报告。不要在公开 Issue、Pull Request、讨论区或规则文件中披露漏洞细节、令牌或可利用样例。若仓库未启用私密漏洞报告且没有可用的私密联系方式，可先提交一个不含漏洞细节的普通 Issue，请求维护者建立私密沟通渠道。

报告建议包含：

- 受影响提交、脚本、工作流或发布分支；
- 最小复现步骤、利用条件和影响；
- 已采取或建议的缓解措施；
- 希望采用的披露时间表。

请勿在未获授权时访问他人数据、持久化控制、破坏发布分支或高频测试第三方服务。

## 响应与凭据处理

维护者会尽力确认和评估，但不承诺固定响应时限。完成缓解后将按实际影响决定是否发布公告及致谢。

仓库不应接收真实令牌、Cookie、私钥或账号信息。凭据进入提交或日志后应立即在提供方撤销或轮换；删除 Git 历史不能替代轮换。

## 文档导航

- [`README.md`](README.md)：用户入口、平台示例和关键边界
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：贡献规则与人工评审清单
- [`docs/README.md`](docs/README.md)：文档职责与阅读路径
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)：环境、命令和开发流程
- [`docs/STRUCTURE.md`](docs/STRUCTURE.md)：构建、产物、守卫和发布结构
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)：常见失败与定位步骤
- [`SECURITY.md`](SECURITY.md)：安全支持范围和私密报告
- [`NOTICE`](NOTICE) / [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)：许可范围与第三方状态
