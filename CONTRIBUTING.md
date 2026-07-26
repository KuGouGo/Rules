# 贡献说明

本仓库以个人使用为主，主要维护自定义规则并整合上游数据。提交规则时保持内容清晰、可生成即可，不设置复杂审批流程。

## 自定义规则

- 域名规则：`sources/custom/domain/*.list`
- IP 规则：`sources/custom/ip/*.list`
- 文件名使用小写字母、数字和连字符。
- 规则类型和值保持规范格式，例如：

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
IP-CIDR,192.0.2.0/24
IP-CIDR6,2001:db8::/32
```

不同文件可以有意重叠，以便分别绑定不同策略；同一文件内不应保留重复或被更宽规则覆盖的条目。使用首条命中的客户端时，细分规则应放在宽泛规则之前，例如先加载 `emby-cn`，再加载 `emby`。

## 修改与验证

日常修改可直接提交，也可通过 Pull Request 合并。建议至少运行：

```bash
make validate
```

需要预览自定义文本产物时运行：

```bash
make build-custom-text
```

涉及完整上游同步或二进制格式时，由 `main` 分支的发布工作流统一构建。不要提交 `.output/`、`.tmp/`、`.artifacts/`、`.bin/`、凭据或本机缓存。

新增上游时，在 `config/upstreams.json` 中填写来源和健康阈值，并按实际情况更新第三方来源说明。仓库代码使用 MIT 许可证；上游数据仍遵循各自条款。
