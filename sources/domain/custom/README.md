# Custom Domain Rules

放手工维护的域名规则。

## 文件约定

- `*.list`
  - 原始规则源
  - 使用 `DOMAIN` / `DOMAIN-SUFFIX` 形式
  - 用于自动生成 Surge 的 DOMAIN-SET 文件

- `*-domain.txt`
  - 纯域名列表
  - 用于生成 mihomo `.mrs`

## 当前规则

- `emby.list` / `emby-domain.txt`
- `emby-cn.list` / `emby-cn-domain.txt`
