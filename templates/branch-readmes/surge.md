# Rules / Surge

<!-- artifact-table -->

这里是 Surge 用的规则，每天跟着 `main` 重新构建，整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。想钉住某一天的结果，订阅地址里的分支名换成那个提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 和 `ip/` 都是 `.list`。
- 域名保留 `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD`。Surge 不支持 `DOMAIN-REGEX`，这类规则不写入；一个列表如果只剩正则，整份不发布。
- IP 保留 `IP-CIDR`、`IP-CIDR6`，带 `no-resolve`。
- 这份产物只给 Surge 用，格式和别的客户端不通用。

## 最小示例

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```

## 域名数据 MIT 通知

这里的域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游的许可原文见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
