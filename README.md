# Rules

一个按客户端分支发布的规则仓库，面向 **Surge / sing-box / mihomo**。

## 分支

- `main`：源码、脚本、工作流、说明文档
- `surge`：Surge 产物分支
- `sing-box`：sing-box 产物分支
- `mihomo`：mihomo 产物分支

## 快速跳转

- [Surge](https://github.com/KuGouGo/Rules/tree/surge)
- [sing-box](https://github.com/KuGouGo/Rules/tree/sing-box)
- [mihomo](https://github.com/KuGouGo/Rules/tree/mihomo)

## 仓库结构

```text
.
├── .github/
├── scripts/
├── sources/
├── domain/
├── ip/
└── README.md
```

## 发布流程

GitHub Actions 会自动执行：

1. 检查规则源文件
2. 同步上游规则
3. 构建规则产物
4. 校验产物数量和变更比例
5. 发布到对应客户端分支

触发方式：
- 手动触发 `workflow_dispatch`
- 每 6 小时自动同步一次

## 上游来源

- Domain Surge / sing-box：<https://github.com/nekolsd/sing-geosite>
- IP Surge / sing-box / mihomo：<https://github.com/nekolsd/geoip>
- mihomo 转换工具：<https://github.com/MetaCubeX/mihomo>
