# Rules

一个可直接订阅的规则仓库，面向 **Surge / sing-box / mihomo**。

## 仓库内容

### Domain

- `domain/surge/`
  - 来源：`nekolsd/sing-geosite` `domain-set`
  - 格式：Surge `DOMAIN-SET` 文本
- `domain/sing-box/`
  - 来源：`nekolsd/sing-geosite` `rule-set`
  - 格式：sing-box 二进制规则集（`.srs`）
- `domain/mihomo/`
  - 来源：基于 `domain/surge/*.txt` 本地转换生成
  - 格式：mihomo 二进制规则集（`.mrs`）

### IP

- `ip/surge/`
  - 来源：`nekolsd/geoip` `release/surge`
  - 格式：Surge IP 规则文本
- `ip/sing-box/`
  - 来源：`nekolsd/geoip` `release/srs`
  - 格式：sing-box 二进制规则集（`.srs`）
- `ip/mihomo/`
  - 来源：`nekolsd/geoip` `release/mrs`
  - 格式：mihomo 二进制规则集（`.mrs`）

## 自定义规则

自定义源文件位于：

- `sources/domain/custom/*.list`

构建后会直接进入公共目录：

- `domain/surge/<name>.txt`
- `domain/sing-box/<name>.srs`
- `domain/mihomo/<name>.mrs`

支持格式：

```text
DOMAIN,example.com
DOMAIN-SUFFIX,example.com
```

约定：
- 支持空行和 `#` 注释
- 文件名仅允许 `a-z`、`0-9`、`-`
- 避免与已有公共规则重名；重名时 CI 会失败

## 使用示例

### Surge

```ini
[Rule]
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/cn.txt,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/surge/cn.txt,DIRECT
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/emby.txt,PROXY
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
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/sing-box/emby.srs"
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
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/mihomo/emby.mrs"
    interval: 86400
```

## 同步说明

GitHub Actions 会执行：

1. 检查自定义规则格式
2. 同步上游规则
3. 构建自定义规则
4. 校验产物数量和变更比例
5. 成功后自动提交

触发方式：
- 手动触发 `workflow_dispatch`
- 每 6 小时自动同步一次

## 上游来源

- Domain Surge / sing-box: <https://github.com/nekolsd/sing-geosite>
- IP Surge / sing-box / mihomo: <https://github.com/nekolsd/geoip>
- mihomo 转换工具: <https://github.com/MetaCubeX/mihomo>
