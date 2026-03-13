# Custom Domain Rules

自定义域名规则文件。

## 文件说明

| 文件 | 格式 | 用途 |
|------|------|------|
| `*.list` | Surge 规则格式 | 直接用于 Surge，包含 `DOMAIN` / `DOMAIN-SUFFIX` 前缀 |
| `*-domain.txt` | 纯域名列表 | 用于转换为 sing-box `.srs` 和 mihomo `.mrs` |

## 命名约定

- `xxx.list`：主规则（如 `emby.list`）
- `xxx-cn.list`：中国/直连侧规则
- `xxx-domain.txt`：对应纯域名版本

## 当前规则

### emby
Emby 媒体服务相关域名。

- 走 Emby 代理的域名
- 包括多个 Emby 服务器地址

### emby-cn
Emby 直连/国内相关域名。

- 直连的 CDN 和服务域名

## 输出位置

构建后会输出到：

- `domain/surge/*.list`（Surge 格式）
- `domain/mihomo/emby.mrs` / `emby-cn.mrs`（mihomo 格式）
