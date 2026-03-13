# Rules

这个仓库现在只做一件事：

**稳定同步上游已经构建好的规则文件**，整理成统一目录，方便直接订阅使用。

## 当前真实行为

### Domain
- `domain/surge/`
  - 来源：`nekolsd/not-sing-geosite` 的 `release/surge`
- `domain/sing-box/`
  - 来源：`nekolsd/sing-geosite` 的 `rule-set`
- `domain/mihomo/`
  - 当前为从 `domain/surge` 复制的文本文件
  - **不是严格意义上的 `.mrs` 二进制产物**

### IP
- `ip/surge/`
  - 来源：`nekolsd/geoip` 的 `release/surge`
- `ip/sing-box/`
  - 来源：`nekolsd/geoip` 的 `release/srs`
- `ip/mihomo/`
  - 来源：`nekolsd/geoip` 的 `release/mrs`

## 目录结构

```text
domain/
  surge/
  sing-box/
  mihomo/

ip/
  surge/
  sing-box/
  mihomo/

sources/
  domain/
    custom/
  ip/
```

## 自定义规则现状

当前 `sources/domain/custom/` 里的规则文件**已保留，但未接入当前主同步流程**。

也就是说现在 workflow 运行时：
- 不会自动把 custom 规则合并进 `domain/surge`
- 不会自动生成 custom 的 `domain/sing-box/*.srs`
- 不会自动生成 custom 的 `domain/mihomo/*`

## Workflow

当前 workflow 只执行：

- `scripts/sync-all.sh`

它负责直接同步上游预构建产物，不再做复杂编译。

## 上游来源

- Surge domain: <https://github.com/nekolsd/sing-geosite/tree/domain-set>
- sing-box domain: <https://github.com/nekolsd/sing-geosite/tree/rule-set>
- GeoIP release assets: <https://github.com/nekolsd/geoip/tree/release>

## 使用示例

### Surge

```ini
[Rule]
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/domain/surge/cn.txt,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/surge/cn.txt,DIRECT
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
      }
    ]
  }
}
```

### mihomo

```yaml
rule-providers:
  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/main/ip/mihomo/cn.mrs"
    interval: 86400
```

## 说明

后续如果要重新接入 custom 规则，建议单独做一条稳定的生成链，不要和当前“纯同步上游产物”的主流程混在一起。

## Custom 独立规则

`sources/domain/custom/*.list` 会独立生成，不并入主规则：

- `domain/custom-surge/*.txt`
- `domain/custom-sing-box/*.srs`
- `domain/custom-mihomo/*.mrs`
