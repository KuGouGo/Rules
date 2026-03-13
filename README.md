# Rules

聚合并发布可直接订阅的规则集，目标是**稳定同步上游预构建产物**，同时保留少量独立维护的自定义规则。

## 当前行为

### Domain
- `domain/surge/`
  - 来源：`nekolsd/sing-geosite` 的 `domain-set` 分支
  - 格式：Surge `DOMAIN-SET` 文本
- `domain/sing-box/`
  - 来源：`nekolsd/sing-geosite` 的 `rule-set` 分支
  - 格式：sing-box 二进制规则集（`.srs`）
- `domain/mihomo/`
  - 来源：本仓库根据 `domain/surge/*.txt` 本地转换生成
  - 格式：mihomo 二进制规则集（`.mrs`）
  - 说明：当前仍不是直接同步上游单独发布分支，而是由 Surge domain-set 文本稳定转换得到

### IP
- `ip/surge/`
  - 来源：`nekolsd/geoip` 的 `release/surge`
  - 格式：Surge IP 规则文本
- `ip/sing-box/`
  - 来源：`nekolsd/geoip` 的 `release/srs`
  - 格式：sing-box 二进制规则集（`.srs`）
- `ip/mihomo/`
  - 来源：`nekolsd/geoip` 的 `release/mrs`
  - 格式：mihomo 二进制规则集（`.mrs`）

## 自定义规则

`sources/domain/custom/*.list` 会独立生成，不并入上游主规则：

- `domain/custom-surge/*.txt`
- `domain/custom-sing-box/*.srs`
- `domain/custom-mihomo/*.mrs`

目前仓库内置了：
- `emby.list`
- `emby-cn.list`

### 自定义规则写法

支持以下两种：

```text
DOMAIN,example.com
DOMAIN-SUFFIX,example.com
```

生成逻辑：
- Surge：保留 `DOMAIN-SET` 语义
  - `DOMAIN,example.com` -> `example.com`
  - `DOMAIN-SUFFIX,example.com` -> `.example.com`
- sing-box / mihomo：统一按域后缀规则集生成

空行和 `#` 注释会被忽略。

## 目录结构

```text
domain/
  surge/
  sing-box/
  mihomo/
  custom-surge/
  custom-sing-box/
  custom-mihomo/

ip/
  surge/
  sing-box/
  mihomo/

sources/
  domain/
    custom/
  ip/
```

## Workflow

GitHub Actions 会执行两步：

1. `scripts/sync-all.sh`
   - 同步上游已经构建好的 domain / ip 产物
   - 并将 `domain/surge/*.txt` 本地转换为 `domain/mihomo/*.mrs`
2. `scripts/build-custom.sh`
   - 将 `sources/domain/custom/*.list` 构建为 Surge / sing-box / mihomo 三种格式

触发方式：
- 手动触发 `workflow_dispatch`
- 每 6 小时定时同步一次

## 上游来源

- Domain Surge / sing-box:
  - <https://github.com/nekolsd/sing-geosite>
- IP Surge / sing-box / mihomo:
  - <https://github.com/nekolsd/geoip>
- mihomo 二进制规则转换工具：
  - <https://github.com/MetaCubeX/mihomo>

## 使用示例

### Surge

```ini
[Rule]
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/cn.txt,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/surge/cn.txt,DIRECT
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/custom-surge/emby.txt,PROXY
```

### sing-box

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/sing-box/cn.srs"
      },
      {
        "tag": "cn-ip",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/sing-box/cn.srs"
      },
      {
        "tag": "emby",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/custom-sing-box/emby.srs"
      }
    ]
  }
}
```

### mihomo

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/mihomo/cn.mrs"
    interval: 86400

  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/mihomo/cn.mrs"
    interval: 86400

  emby:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/custom-mihomo/emby.mrs"
    interval: 86400
```

## 说明

这个仓库的定位不是重新发明规则生成工具链，而是：
- 主规则尽量直接复用上游已构建产物
- mihomo domain 在当前阶段通过本地稳定转换补齐
- 自定义规则保持独立、简单、可维护
- 对外提供统一且稳定的订阅目录结构
