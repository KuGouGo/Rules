# Rules

聚合并发布可直接订阅的规则集，目标是**稳定同步上游预构建产物**，同时保留少量独立维护的自定义规则。

## 当前行为

### Domain
- `domain/surge/`
  - 主体来源：`nekolsd/sing-geosite` 的 `domain-set` 分支
  - 自定义补充：`sources/domain/custom/*.list`
  - 格式：Surge `DOMAIN-SET` 文本
- `domain/sing-box/`
  - 主体来源：`nekolsd/sing-geosite` 的 `rule-set` 分支
  - 自定义补充：`sources/domain/custom/*.list`
  - 格式：sing-box 二进制规则集（`.srs`）
- `domain/mihomo/`
  - 主体来源：本仓库根据 `domain/surge/*.txt` 本地转换生成
  - 自定义补充：`sources/domain/custom/*.list`
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

`sources/domain/custom/*.list` 会直接生成到公共规则目录中，而不是单独放在外部目录：

- `domain/surge/<name>.txt`
- `domain/sing-box/<name>.srs`
- `domain/mihomo/<name>.mrs`

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

### 命名约定

自定义规则会直接占用公共文件名，因此应避免与上游已有规则重名。

推荐：
- 用有语义的名字，如 `emby`、`emby-cn`
- 尽量避免使用过于通用的名字，如 `media`、`global`、`proxy`

如果与上游同名，当前行为是**以本地自定义文件覆盖同步来的同名文件**。

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

## Workflow

GitHub Actions 会执行三步：

1. `scripts/sync-all.sh`
   - 同步上游已经构建好的 domain / ip 产物
   - 并将 `domain/surge/*.txt` 本地转换为 `domain/mihomo/*.mrs`
2. `scripts/build-custom.sh`
   - 将 `sources/domain/custom/*.list` 直接构建进公共 domain 目录
3. `scripts/guard-artifacts.sh`
   - 对关键目录做最小文件数校验
   - 并检查相对 `HEAD` 的单次删除/变更比例
   - 避免上游异常、同步逻辑错误或产物结构突变时直接提交“大面积清空/骤减”结果

触发方式：
- 手动触发 `workflow_dispatch`
- 每 6 小时定时同步一次

### 产物保护策略

当前采用两层轻量保护：

#### 1) 最小文件数阈值

- `domain/surge/*.txt` ≥ 1000
- `domain/sing-box/*.srs` ≥ 1000
- `domain/mihomo/*.mrs` ≥ 1000
- `ip/surge/*.txt` ≥ 8
- `ip/sing-box/*.srs` ≥ 8
- `ip/mihomo/*.mrs` ≥ 8

#### 2) 单次变更比例阈值

脚本会把当前工作区和 `HEAD` 基线进行比较，对每个产物目录检查：

- **删除比例** 默认不得超过 `30%`
- **总变更比例** 默认不得超过 `50%`

可通过环境变量调整：

- `MAX_DELETE_PERCENT`
- `MAX_CHANGE_PERCENT`

默认目标是拦住最危险的几类事故：
- 上游异常导致大面积删库
- 同步脚本跑偏，结果只生成一小部分文件
- 目录结构变化导致一整类产物被替换或清空

它仍然不是完整审计系统，但已经足够实用，能在自动提交前先踩一脚刹车。

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

## 说明

这个仓库的定位不是重新发明规则生成工具链，而是：
- 主规则尽量直接复用上游已构建产物
- mihomo domain 在当前阶段通过本地稳定转换补齐
- 自定义规则直接并入公共目录，方便统一订阅
- 对外提供统一且稳定的订阅目录结构
