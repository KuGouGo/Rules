# Custom Domain Rules

放手工维护的域名规则。

## 文件约定

- `*.list`
  - 规则源文件
  - 格式：`DOMAIN,example.com` 或 `DOMAIN-SUFFIX,example.com`
  - 不包含策略名（如 `,DIRECT` 或 `,Proxy`）

- `*-domain.txt`
  - 纯域名列表
  - 每行一个域名
  - 用于生成 mihomo `.mrs`

## 当前规则

- `emby.list` / `emby-domain.txt`
- `emby-cn.list` / `emby-cn-domain.txt`