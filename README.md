# Rules

> A cleaner, sharper rule repo for **Surge / sing-box / mihomo**.

聚合、整理、发布可直接订阅的规则集。  
这个仓库的目标不是“重新发明一套规则生态”，而是把**上游成熟产物** + **少量自定义规则**，做成一个更统一、更稳定、也更顺手的订阅入口。

---

## ✨ Why this repo exists

很多规则仓库都有一个共同问题：
- 目录风格不统一
- 自定义规则和公共规则割裂
- 自动同步能跑，但出问题时难排查
- 文档能看懂，但不够顺手

`Rules` 想做的事很直接：

- **统一目录结构**：domain / ip 分层清楚
- **统一订阅入口**：自定义规则也并入公共目录
- **偏工程化维护**：自动同步、构建、防翻车、诊断信息都补齐
- **尽量贴近真实使用**：面向日常配置订阅，而不是只为“仓库看起来完整”

---

## 🚀 What you get

### Domain rules

- `domain/surge/`
  - 主体来源：`nekolsd/sing-geosite` `domain-set`
  - 格式：Surge `DOMAIN-SET` 文本
- `domain/sing-box/`
  - 主体来源：`nekolsd/sing-geosite` `rule-set`
  - 格式：sing-box 二进制规则集（`.srs`）
- `domain/mihomo/`
  - 主体来源：基于 `domain/surge/*.txt` 本地转换生成
  - 格式：mihomo 二进制规则集（`.mrs`）

### IP rules

- `ip/surge/`
  - 来源：`nekolsd/geoip` `release/surge`
  - 格式：Surge IP 规则文本
- `ip/sing-box/`
  - 来源：`nekolsd/geoip` `release/srs`
  - 格式：sing-box 二进制规则集（`.srs`）
- `ip/mihomo/`
  - 来源：`nekolsd/geoip` `release/mrs`
  - 格式：mihomo 二进制规则集（`.mrs`）

### Custom rules

`sources/domain/custom/*.list` 会**直接生成进公共目录**，而不是挂在额外的 `custom-*` 目录外面：

- `domain/surge/<name>.txt`
- `domain/sing-box/<name>.srs`
- `domain/mihomo/<name>.mrs`

目前内置：
- `emby.list`
- `emby-cn.list`

---

## 🗂 Structure

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

scripts/
  sync-all.sh
  build-custom.sh
  guard-artifacts.sh
  lint-custom-rules.sh
```

---

## 🧩 Custom rules

### Syntax

支持两种写法：

```text
# Emby nodes
DOMAIN,example.com
DOMAIN-SUFFIX,example.com
```

转换逻辑：

- **Surge**
  - `DOMAIN,example.com` → `example.com`
  - `DOMAIN-SUFFIX,example.com` → `.example.com`
- **sing-box / mihomo**
  - 统一生成域后缀规则集

说明：
- 空行会忽略
- `#` 注释会忽略
- 域名前不要带 `.`

### Naming

因为自定义规则会直接进入公共目录，所以命名要克制一点。

要求：
- 只允许 `a-z`、`0-9`、`-`
- 建议使用清晰语义名：`emby`、`emby-cn`
- 不建议用过于泛化的名字：`global`、`media`、`proxy`

如果与上游公共规则重名，CI 会**直接失败**，不会静默覆盖。

### Lint rules

CI 在构建前会检查 `sources/domain/custom/*.list`：

- 文件名是否合法
- 文件是否至少包含一条有效规则
- 每条规则是否符合格式：
  - `DOMAIN,example.com`
  - `DOMAIN-SUFFIX,example.com`
- 域名前是否误带 `.`

---

## ⚙️ Workflow

GitHub Actions 当前执行链路：

1. **Lint custom rules**
   - 先检查自定义规则命名和格式
2. **Sync all rules**
   - 同步上游 domain / ip 产物
   - 本地补齐 `domain/mihomo/*.mrs`
3. **Build custom rules**
   - 将 `sources/domain/custom/*.list` 构建进公共 `domain/*`
4. **Guard artifacts**
   - 校验文件数量
   - 校验单次删除比例 / 总变更比例
   - 失败时输出样本 diff
5. **Show summary**
   - 无论成功失败都输出概要
6. **Commit**
   - 仅在前面全部成功时提交

触发方式：
- `workflow_dispatch`
- 每 6 小时自动同步一次

---

## 🛡 Guard rails

这个仓库现在不是“只要能跑就提交”，而是加了几道刹车。

### 1. Minimum artifact count

- `domain/surge/*.txt` ≥ `1000`
- `domain/sing-box/*.srs` ≥ `1000`
- `domain/mihomo/*.mrs` ≥ `1000`
- `ip/surge/*.txt` ≥ `8`
- `ip/sing-box/*.srs` ≥ `8`
- `ip/mihomo/*.mrs` ≥ `8`

### 2. Diff ratio guard

默认阈值：
- **删除比例** 不得超过 `30%`
- **总变更比例** 不得超过 `50%`

可通过环境变量覆盖：
- `MAX_DELETE_PERCENT`
- `MAX_CHANGE_PERCENT`

### 3. Conflict protection

如果 custom 规则名撞上已有公共规则：
- 直接报错
- 列出冲突文件
- 停止构建

### 4. No-op write avoidance

如果生成结果内容没变：
- 不改写目标文件
- 不制造无意义 diff
- `git status` 更干净

---

## 📦 Sources

- Domain Surge / sing-box:  
  <https://github.com/nekolsd/sing-geosite>
- IP Surge / sing-box / mihomo:  
  <https://github.com/nekolsd/geoip>
- mihomo conversion tool:  
  <https://github.com/MetaCubeX/mihomo>

---

## 🔗 Usage

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

---

## 🧠 Design notes

这个仓库的思路很明确：

- 主规则尽量复用上游成熟产物
- mihomo domain 在当前阶段通过本地稳定转换补齐
- 自定义规则直接并入公共目录，订阅路径更统一
- 自动同步不是目的，**可维护、可诊断、可持续跑** 才是目的

如果你只想拿来订阅，它应该够直接。  
如果你想长期维护，它现在也已经比较像一个正经工程仓库了。
