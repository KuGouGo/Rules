# Custom Domain Rules

自定义规则主源目录。

## 源文件格式

使用 `*.list`：

- `DOMAIN,example.com`
- `DOMAIN-SUFFIX,example.com`

## 独立产物目录

这些规则不会并入主规则，而是单独生成到：

- `domain/custom-surge/*.txt`
- `domain/custom-sing-box/*.srs`
- `domain/custom-mihomo/*.mrs`
