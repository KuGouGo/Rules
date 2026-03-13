# Rules

规则源码与发布仓库。

## 分支说明

- `main`
  - 源码、脚本、工作流、说明文档
- `surge`
  - Surge 产物分支
- `sing-box`
  - sing-box 产物分支
- `mihomo`
  - mihomo 产物分支

## 快速跳转

- **Surge**
  - [surge branch](https://github.com/KuGouGo/Rules/tree/surge)
- **sing-box**
  - [sing-box branch](https://github.com/KuGouGo/Rules/tree/sing-box)
- **mihomo**
  - [mihomo branch](https://github.com/KuGouGo/Rules/tree/mihomo)

## 仓库内容

```text
.
├── .github/
├── scripts/
├── sources/
├── domain/
├── ip/
└── README.md
```

## 同步说明

GitHub Actions 会执行：

1. 检查规则源文件
2. 同步上游规则
3. 构建规则产物
4. 校验产物数量和变更比例
5. 发布到对应客户端分支

触发方式：
- 手动触发 `workflow_dispatch`
- 每 6 小时自动同步一次

## 上游来源

- Domain Surge / sing-box: <https://github.com/nekolsd/sing-geosite>
- IP Surge / sing-box / mihomo: <https://github.com/nekolsd/geoip>
- mihomo 转换工具: <https://github.com/MetaCubeX/mihomo>
