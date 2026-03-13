# Custom Domain Rules

自定义 domain 规则源目录。

这些 `*.list` 文件会直接构建进公共规则目录：

- `domain/surge/<name>.txt`
- `domain/sing-box/<name>.srs`
- `domain/mihomo/<name>.mrs`

## 文件格式

支持两种规则：

- `DOMAIN,example.com`
- `DOMAIN-SUFFIX,example.com`

额外约定：

- 支持空行
- 支持 `#` 注释
- 域名前不要带 `.`
- 文件名仅允许 `a-z`、`0-9`、`-`
- 避免与公共规则重名；若重名，CI 会直接失败
