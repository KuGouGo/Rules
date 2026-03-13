# Rules

一个把上游 geosite / geoip 数据整理为可直接使用文件的仓库。

## 目标

输出适合以下客户端直接引用的规则文件：

- **Surge**
- **sing-box**
- **mihomo**

## 推荐目录结构

```text
custom/
  domain/
    emby.list
    emby-cn.list

sources/
  geosite/      # 上游 geosite 源构建器
  geoip/        # 上游 geoip 源构建器

output/
  geosite/
    surge/
    sing-box/
    mihomo/
  geoip/
    surge/
    sing-box/
    mihomo/

configs/
  geoip-convert.json

scripts/
  sync-upstream.sh
  build-geosite.sh
  build-geoip.sh
  merge-custom.sh

.github/workflows/
  sync.yml
```

## 当前规划

### geosite 输出

- `output/geosite/surge/`：纯文本 domain-set
- `output/geosite/sing-box/`：`.srs`
- `output/geosite/mihomo/`：兼容产物或映射文件

### geoip 输出

- `output/geoip/surge/`：Surge 规则文本
- `output/geoip/sing-box/`：`.srs`
- `output/geoip/mihomo/`：`.mrs`

## 自定义规则

当前自定义规则：

- `custom/domain/emby.list`
- `custom/domain/emby-cn.list`

约定：

- `*-cn`：直连/中国或直连侧规则
- 主名文件：业务规则本体

## 设计原则

- 上游源码和输出产物分离
- 自定义规则和上游规则分离
- 输出目录稳定，方便订阅
- workflow 只做三件事：同步、构建、提交
