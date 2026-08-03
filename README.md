# Rules / Quantumult X

这里放 Quantumult X 的自动构建产物，每次推送 `main` 都会整批覆盖更新。里面只有 `README.md`、`domain/` 和 `ip/`；想固定版本就锁定提交 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 与 `ip/` 均使用 `.list` 扩展名。
- 域名规则：转换为 `HOST`、`HOST-SUFFIX`、`HOST-KEYWORD`；`DOMAIN-REGEX` 不写入产物，仅含正则的列表不会发布。
- IP 规则：支持 `IP-CIDR`、`IP6-CIDR`；第三字段是规则文件名，建议用 `force-policy` 覆盖占位策略。
- 产物面向 Quantumult X 生成，不能假定与其他客户端的规则格式兼容。

## 最小示例

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```

## v2fly/domain-list-community MIT 通知

本分支的域名产物包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），完整许可文本见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
