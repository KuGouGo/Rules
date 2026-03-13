# Rules

一个把上游规则整理成可直接使用文件的仓库。

## 目录

```text
sources/
  domain/
    custom/
      emby.list          # Surge 格式（DOMAIN/DOMAIN-SUFFIX）
      emby-domain.txt    # 纯域名列表（用于 mihomo 转换）
      emby-cn.list
      emby-cn-domain.txt
  ip/

domain/
  surge/         # Surge DOMAIN-SET 文件
  sing-box/      # sing-box .srs
  mihomo/        # mihomo .mrs（含自定义规则）
  custom-source/ # 自定义域名源文件（保留原始写法）

ip/
  surge/         # Surge/IP 规则文本
  sing-box/      # sing-box .srs
  mihomo/        # mihomo .mrs
```

## Surge 兼容性约定

### domain/surge

这里使用 **DOMAIN-SET** 语义：

- 每行一个域名
- 若以 `.` 开头，则匹配该域名本身及所有子域名
- 不转换成 `DOMAIN-SUFFIX` / `DOMAIN` / `DOMAIN-KEYWORD`

这更适合 Surge 的外部规则集加载方式。

### ip/surge

这里使用 Surge 可识别的 IP 规则文本。

## 自定义规则

### 文件说明

| 文件 | 用途 |
|------|------|
| `*.list` | Surge 格式规则 |
| `*-domain.txt` | 纯域名列表，用于转换为 sing-box/mihomo 格式 |

### 当前自定义规则

- `emby`：Emby 服务域名
- `emby-cn`：Emby 直连/国内域名

### 输出位置

- Surge：`domain/surge/*.list`
- mihomo：`domain/mihomo/emby.mrs` / `emby-cn.mrs`