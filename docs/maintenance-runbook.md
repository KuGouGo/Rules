# 维护与发布手册

## 日常修改流程

1. 修改 `sources/custom/domain/*.list` 或 `sources/custom/ip/*.list`。
2. 运行本地校验。
3. 推送到 `main` 后，GitHub Actions 会根据变更范围选择 `custom` 或 `full` 构建。
4. 构建成功后，产物会发布到各平台分支。

## 本地校验

推荐顺序：

```bash
shellcheck scripts/*.sh scripts/lib/*.sh
scripts/lint-custom-rules.sh
scripts/test-domain-parsing.sh
scripts/test-shell-utils.sh
scripts/build-custom.sh
```

如果需要完整同步上游源，再运行：

```bash
scripts/sync-upstream.sh
scripts/fetch-fakeip-filter.sh
scripts/guard-artifacts.sh
```

完整同步会访问多个外部数据源，适合在 CI 或需要验证上游变化时运行。

## GitHub Actions 构建范围

`.github/workflows/build.yml` 支持以下手动输入：

- `auto`：手动触发时等同于 `full`。
- `custom`：只重建自定义规则，并从远端发布分支恢复其他既有产物。
- `full`：同步上游数据源、重建全部产物并发布。

Push 到 `main` 时：

- 只修改 `sources/custom/**` 且没有删除自定义源文件时，运行 `custom`。
- 修改脚本、工作流或删除自定义源文件时，运行 `full`。
- 定时任务每天 UTC 08:00 运行 `full`。

## 发布失败排查

- `lint-custom-rules.sh` 失败：检查自定义规则前缀、文件名和 CIDR 格式。
- `test-domain-parsing.sh` 失败：检查域名解析或格式转换逻辑是否被意外改变。
- `guard-artifacts.sh` 失败：检查 `.output/` 是否缺少大量产物，或上游源是否出现异常大规模变更。
- `publish-branches.sh` 失败：检查 `GITHUB_TOKEN` 权限、远端分支状态和分支布局校验。

## 添加上游源

当前上游源定义主要位于 `scripts/sync-upstream.sh`。添加前应确认：

- 数据源稳定且可公开访问。
- 源格式可以由 `scripts/normalize-ip-source.py` 或域名导出逻辑解析。
- 已设置合理的最小条目数或产物守卫。
- 已在 README 或相关文档中说明来源。

