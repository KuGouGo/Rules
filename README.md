# Rules

一个把上游规则整理成可直接使用文件的仓库。

## 目标

输出适合以下客户端直接引用的规则文件：

- **Surge**
- **sing-box**
- **mihomo**

## 目录结构

```text
sources/
  domain/      # 域名规则上游构建器源码 + 自定义域名规则
    custom/
      emby.list
      emby-cn.list
  ip/          # IP 规则上游构建器源码 + 自定义 IP 规则
    custom/

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
- `sources`：上游源码，同时允许放自定义源规则
- `sources/*/custom`：手工维护规则

## 当前自定义规则

- `sources/domain/custom/emby.list`
- `sources/domain/custom/emby-cn.list`

## 设计原则

- 命名直观，优先人能看懂
- 源、产物分离，但自定义规则贴近对应源
- 最终产物直接放仓库外层，方便订阅
- workflow 只做：同步、构建、提交
