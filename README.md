# Rules

一个把上游规则整理成可直接使用文件的仓库。

## 目录

```text
sources/
  domain/
    custom/
      README.md
      emby.list          # Surge 规则格式（DOMAIN/DOMAIN-SUFFIX）
      emby-domain.txt    # 纯域名列表（用于 mihomo 转换）
      emby-cn.list
      emby-cn-domain.txt
  ip/

domain/
  surge/         # Surge DOMAIN-SET 文件
  sing-box/      # sing-box .srs
  mihomo/        # mihomo .mrs

ip/
  surge/         # Surge/IP 规则文本
  sing-box/      # sing-box .srs
  mihomo/        # mihomo .mrs
```

## Surge 兼容性

### domain/surge

使用 **DOMAIN-SET** 格式：

- 每行一个域名
- `example.com`：精确匹配
- `.example.com`：匹配主域名及所有子域名

### 自定义规则转换

`sources/domain/custom/*.list` 文件会自动转换：

| 原始格式 | DOMAIN-SET 格式 |
|---------|----------------|
| `DOMAIN,xxx,Policy` | `xxx` |
| `DOMAIN-SUFFIX,xxx,Policy` | `.xxx` |

转换后的文件输出到 `domain/surge/*.txt`，可直接被 Surge 加载。

## 自定义规则

详见 [sources/domain/custom/README.md](sources/domain/custom/README.md)