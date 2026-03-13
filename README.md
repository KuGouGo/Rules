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
  domain/
    custom/
  ip/
    custom/

domain/
  surge/
  sing-box/
  mihomo-text/
  mihomo/

ip/
  surge/
  sing-box/
  mihomo-text/
  mihomo/

configs/
  geoip-convert.json
scripts/
  sync-upstream.sh
  build-domain.sh
  build-ip.sh
  build-mihomo-mrs.sh
  merge-custom.sh
```

## 说明

- `surge/`：通用文本规则
- `sing-box/`：sing-box 规则集
- `mihomo-text/`：供 mihomo 转换 `.mrs` 的中间文本产物
- `mihomo/`：最终 `.mrs` 产物

## 自定义规则

- `sources/domain/custom/emby.list`
- `sources/domain/custom/emby-cn.list`
