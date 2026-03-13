# Rules

把上游 geosite / geoip 数据整理成适合以下客户端直接使用的规则文件：

- **Surge**
- **sing-box**
- **mihomo**

## 目录结构

```text
sources/
  domain/
    custom/
  ip/

domain/
  surge/      # Surge DOMAIN-SET
  sing-box/   # sing-box .srs
  mihomo/     # mihomo .mrs

ip/
  surge/      # Surge IP 规则文本
  sing-box/   # sing-box .srs
  mihomo/     # mihomo .mrs
```

## 规则说明

### domain/surge

使用 Surge 的 **DOMAIN-SET** 格式：

- 每行一个域名
- `example.com`：精确匹配
- `.example.com`：匹配主域名及所有子域名

### 自定义域名规则

`source/domain/custom/*.list` 会自动转换为 `domain/surge/*.txt`：

- `DOMAIN,example.com,Policy` → `example.com`
- `DOMAIN-SUFFIX,example.com,Policy` → `.example.com`

`source/domain/custom/*-domain.txt` 用于生成 `domain/mihomo/*.mrs`。
