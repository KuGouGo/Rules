# Rules

一个把上游规则整理成可直接使用文件的仓库。

## 目标

输出适合以下客户端直接引用的规则文件：

- **Surge**
- **sing-box**
- **mihomo**

## 目录结构

```text
custom/
  domain/
    emby.list
    emby-cn.list
  ip/

sources/
  domain/      # 域名规则上游构建器源码
  ip/          # IP 规则上游构建器源码

domain/
  surge/
  sing-box/
  mihomo/

ip/
  surge/
  sing-box/
  mihomo/

configs/
  geoip-convert.json

scripts/
  sync-upstream.sh
  build-domain.sh
  build-ip.sh
  merge-custom.sh

.github/workflows/
  build.yml
```

## 约定

- `domain`：最终域名类规则产物
- `ip`：最终 IP / CIDR / ASN 类规则产物
- `sources`：上游源码
- `custom`：手工维护规则

## 当前自定义规则

- `custom/domain/emby.list`
- `custom/domain/emby-cn.list`

## 设计原则

- 命名直观，优先人能看懂
- 上游源码、产物、自定义规则三层分离
- 最终产物直接放仓库外层，方便订阅
- workflow 只做：同步、构建、提交
