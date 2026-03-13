# multi-client-rules

一个用于**统一生成 sing-box / Clash / Surge 规则文件**的轻量仓库。

## 本次更新重点

- 源数据使用 `.list` 文档维护。
- 内置两套 Emby 规则：
  - `emby`（Emby 国际线路，走代理）
  - `emby-cn`（Emby 国内线路，走直连）

## 功能

- 维护多份源规则（`data/*.list`）
- 一键为每个 profile 生成：
  - sing-box 规则片段（JSON）
  - Clash 规则列表（YAML）
  - Surge 规则列表（`.list`）
- 支持规则类型：
  - `DOMAIN-SUFFIX`
  - `DOMAIN`
  - `DOMAIN-KEYWORD`
  - `IP-CIDR`

## 目录结构

```text
.
├── data/
│   ├── emby.list              # Emby 代理规则源
│   └── emby-cn.list           # Emby 直连规则源
├── output/                    # 生成结果
├── scripts/
│   └── generate_rules.py      # 生成脚本
└── README.md
```

## 源规则格式（.list）

每行一条规则，格式：

```text
RULE-TYPE,VALUE
```

示例：

```text
DOMAIN-SUFFIX,emby.media
DOMAIN,app.emby.media
DOMAIN-KEYWORD,emby
IP-CIDR,104.16.0.0/13
```

支持注释和空行：

- `#` 开头行为注释
- 空行会被忽略

## 使用方式

```bash
python3 scripts/generate_rules.py
```

可选参数：

```bash
python3 scripts/generate_rules.py \
  --input-dir data \
  --output-dir output
```

## 输出文件命名

按 profile 自动输出：

- `output/<profile>.sing-box.json`
- `output/<profile>.clash.yaml`
- `output/<profile>.surge.list`

例如：

- `output/emby.sing-box.json`
- `output/emby.clash.yaml`
- `output/emby.surge.list`
- `output/emby-cn.sing-box.json`
- `output/emby-cn.clash.yaml`
- `output/emby-cn.surge.list`

## 出站策略约定

脚本会根据文件名后缀自动设置目标策略：

- `*-cn.list` / `*_cn.list` / `*_direct.list` -> `DIRECT`
- `emby.list` -> `Emby`
- 其他 -> `PROXY`

