# Custom Domain Rules

自定义域名规则源文件目录。

## 文件格式

所有自定义规则使用 `*.list` 文件，格式：

```
DOMAIN,example.com
DOMAIN-SUFFIX,example.com
```

- `DOMAIN` - 精确匹配
- `DOMAIN-SUFFIX` - 后缀匹配（匹配主域名及所有子域名）

## 生成产物

修改 `*.list` 文件后，workflow 会自动生成：

- `domain/surge/*.txt` - Surge DOMAIN-SET
- `domain/sing-box/*.srs` - sing-box 规则集
- `domain/mihomo/*.mrs` - mihomo 规则集

## 当前规则

- `emby.list` - Emby 媒体服务域名
- `emby-cn.list` - Emby 直连域名