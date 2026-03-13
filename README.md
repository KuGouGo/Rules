# Rules

这个仓库的目标很简单：

把上游数据同步并整理成适合以下客户端直接使用的文件：

- **Surge**
  - geosite：纯文本 `domain-set`
  - geoip：纯文本 ruleset（也可直接复用 mihomo 生成逻辑导出的通用文本）
- **sing-box**
  - geosite：`.srs`
  - geoip：`.srs`
- **mihomo**
  - geoip：`.mrs`

## 上游仓库

- geosite: <https://github.com/nekolsd/sing-geosite>
- geoip: <https://github.com/nekolsd/geoip>

## 仓库原则

- **不重新发明解析器**，优先复用上游已有构建逻辑
- **不强调 release 产物**，主要是把上游同步到本仓库对应文件夹
- **目录清晰可直接引用**

## 目标目录结构

```text
geosite/
  mihomo/     # 预留，必要时放兼容产物
  surge/      # 纯文本 domain-set
  sing-box/   # .srs

geoip/
  mihomo/     # .mrs
  surge/      # 纯文本 ruleset
  sing-box/   # .srs
```

## 当前实现思路

- `sing-geosite` 负责生成：
  - 纯文本域名集合
  - sing-box `.srs`
- `geoip` 负责生成：
  - Surge 纯文本 ruleset
  - sing-box `.srs`
  - mihomo `.mrs`

## 后续要做的事

1. 完善同步脚本
2. 统一输出目录到仓库根目录
3. 配置 GitHub Actions 定时同步上游
4. 仅提交需要直接使用的结果文件
