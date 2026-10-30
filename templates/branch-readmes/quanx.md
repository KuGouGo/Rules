# Rules / Quantumult X

<!-- artifact-table -->

这里是 Quantumult X 用的规则，每天跟着 `main` 重新构建，整支覆盖。分支里只有 `README.md`、`domain/` 和 `ip/`。想钉住某一天的结果，订阅地址里的分支名换成那个提交的 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 文件里有什么

- `domain/` 和 `ip/` 都是 `.list`。
- 域名转成 `HOST`、`HOST-SUFFIX`、`HOST-KEYWORD`。`DOMAIN-REGEX` 不写入；一个列表如果只剩正则，整份不发布。
- IP 保留 `IP-CIDR`、`IP6-CIDR`。第三字段是规则文件名，实际策略用 `force-policy` 覆盖。
- 这份产物只给 Quantumult X 用，格式和别的客户端不通用。

## 最小示例

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```

## 域名数据 MIT 通知

这里的域名规则包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)（MIT License），上游的许可原文见 [LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)。
