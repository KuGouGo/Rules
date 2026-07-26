# 维护说明

## 常用命令

```bash
make check              # Shell、Python、配置和自定义规则检查
make validate           # 快速检查 + 全部测试
make build-custom-text  # 生成自定义文本产物
make build-custom       # 生成文本和二进制产物（Linux）
make clean              # 清理临时文件和产物
```

本地需要 Bash 5+、Python 3.11+、GNU Make 和 Git。二进制构建还需要 Linux；日常添加规则运行 `make check` 即可。

## 目录

```text
sources/custom/domain/  自定义域名规则
sources/custom/ip/      自定义 IP 规则
config/upstreams.json   上游地址和解析方式
config/tools-lock.json  sing-box / mihomo 工具版本
scripts/                同步、转换、校验和发布脚本
templates/              各产物分支 README 模板
```

不要手工修改 `.output/` 或五个平台产物分支。自定义规则或配置推送到 `main` 后，GitHub Actions 会自动生成并发布。

## 添加规则

规则文件使用 `.list` 扩展名，文件名只使用小写字母、数字和连字符。

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
IP-CIDR,192.0.2.0/24
```

不同文件允许重叠，以便绑定不同策略；同一文件内的重复、无效格式或被宽规则覆盖的条目会被检查拒绝。

新增上游时修改 `config/upstreams.json`，并按实际情况更新根目录的 `THIRD_PARTY_NOTICES.md`。

## 自动构建

- PR：只运行快速检查。
- `main`：检查、构建并发布五个平台分支。
- 定时任务：每天同步一次上游。
- 手动运行：Actions → Sync Rules，可选择 `auto`、`custom` 或 `full`。

构建失败时，先查看 Actions 日志中最早出现的错误。常见原因是规则格式错误、上游不可访问、上游条目数量异常或工具下载失败。
