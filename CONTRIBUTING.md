# 贡献指南

欢迎为 Rules 仓库贡献。仓库由持续集成流水线驱动,`main` 分支为构建源,产物发布到各平台分支;请勿直接修改已发布的产物分支。

## 环境要求

- Bash(仓库脚本基于 `bash`)
- Python 3.12+(`python3` 需要在 `PATH` 中)
- `make`、`git`

## 本地开发

```bash
git clone https://github.com/KuGouGo/Rules.git
cd Rules

make lint          # 语法、配置、规则质量检查
make test          # 全量 shell 测试
make test-python   # Python 单元测试
make validate      # lint + 全量测试
```

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `config/upstreams.json` | 上游来源与健康策略 |
| `sources/custom/domain/` | 自定义域名规则(直接维护) |
| `sources/builtin/ip/` | 内置 IP 保留/自定义源 |
| `scripts/tools/` | Python 处理工具(归一化、合并、渲染、校验) |
| `scripts/commands/` | 流水线命令入口 |
| `scripts/tests/` | 测试脚本与固定样本 |

## 规则修改指引

- **自定义规则**:在 `sources/custom/domain/` 下维护,格式为经典规则行(`DOMAIN` / `DOMAIN-SUFFIX` / `DOMAIN-KEYWORD` / `DOMAIN-REGEX`)。不要直接编辑上游克隆产物。
- **上游数据**:来源集中在 `config/upstreams.json`,解析后先过数据审计,硬性错误会阻断构建。
- **属性语义**:`@cn` / `@!cn` 用于闭合地理分区;`@ads` 仅参与基础列表过滤,不单独发布派生。请勿引入脱离分区模型的属性用法。

## 提交流程

1. Fork 并创建特性分支:`git checkout -b feat/xxx`
2. 修改并运行 `make validate` 确保全部通过
3. 提交信息遵循仓库风格(`feat:` / `fix:` / `chore:` 等)
4. 发起 Pull Request,说明改动动机、影响范围与验证结果

`main` 是唯一长期源码分支,普通开发分支在 PR 合并后删除,不维护额外的 `develop` 分支。`automation/dependency-updates` 仅供每日依赖更新任务临时使用;更新经过完整验证并压缩合并后自动删除。`surge`、`quanx`、`egern`、`sing-box` 与 `mihomo` 均为只读产物分支。

## 提交后

PR 合并到 `main` 会触发流水线重新构建并发布各平台产物分支。若你的改动影响上游来源或产物内容,请同步更新 `docs/architecture.md`、`THIRD_PARTY_NOTICES.md` 与分支模板。
