# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)
[![Repo Size](https://img.shields.io/github/repo-size/KuGouGo/Rules)](https://github.com/KuGouGo/Rules)
[![Surge](https://img.shields.io/badge/client-Surge-orange)](https://github.com/KuGouGo/Rules/tree/surge)
[![sing-box](https://img.shields.io/badge/client-sing--box-blue)](https://github.com/KuGouGo/Rules/tree/sing-box)
[![mihomo](https://img.shields.io/badge/client-mihomo-green)](https://github.com/KuGouGo/Rules/tree/mihomo)

一个按客户端分支发布的规则仓库，面向 **Surge / sing-box / mihomo**。

## Branches

- `main`：源码、脚本、工作流、说明文档
- `surge`：Surge 产物分支
- `sing-box`：sing-box 产物分支
- `mihomo`：mihomo 产物分支

## Quick Links

- [Surge](https://github.com/KuGouGo/Rules/tree/surge)
- [sing-box](https://github.com/KuGouGo/Rules/tree/sing-box)
- [mihomo](https://github.com/KuGouGo/Rules/tree/mihomo)

## Layout

```text
.
├── .github/
├── scripts/
├── sources/
├── domain/
├── ip/
└── README.md
```

## Workflow

GitHub Actions 会自动执行：

1. 检查规则源文件
2. 同步上游规则
3. 构建规则产物
4. 校验产物数量和变更比例
5. 发布到对应客户端分支

触发方式：

- 手动触发 `workflow_dispatch`
- 每 6 小时自动同步一次

## Upstream

- Domain Surge / sing-box：<https://github.com/nekolsd/sing-geosite>
- IP Surge / sing-box / mihomo：<https://github.com/nekolsd/geoip>
- mihomo 转换工具：<https://github.com/MetaCubeX/mihomo>
