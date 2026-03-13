# Rules

一个把上游规则整理成可直接使用文件的仓库。

## 目录

```text
sources/
  domain/
    custom/
  ip/

domain/
  surge/
  sing-box/
  mihomo-input/
  mihomo/

ip/
  surge/
  sing-box/
  mihomo-input/
  mihomo/

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
- `mihomo-input/`：供 mihomo 进一步处理的输入文件
- `mihomo/`：最终 `.mrs` 产物

## 自定义规则

- `sources/domain/custom/emby.list`
- `sources/domain/custom/emby-cn.list`
