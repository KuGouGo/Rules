# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)

一个面向中文用户的多平台代理规则仓库，支持：
- Surge
- Quantumult X（QuanX）
- Egern
- sing-box
- mihomo

项目特点：
- 统一维护，多端输出
- 每天自动同步并发布
- 支持自定义规则扩展
- 同时提供 Domain 和 IP 两类规则

每日自动同步时间：08:00 UTC

==================================================

## 一、5 分钟上手（先看这个）

如果你不想研究仓库结构，只想先用起来，按这个顺序操作：

### 第 1 步：先选最常用规则
大多数人先用这几组就够了：
- 国内直连：`cn`
- 国外常用：`google` `telegram` `github` `openai`
- 苹果服务：`apple`
- CDN/补充分流：`cloudflare`

如果你有这些需求，再额外加：
- 流媒体：`netflix` `spotify` `disney`
- 广告拦截：`awavenue-ads`
- Emby：`emby` `emby-cn`

### 第 2 步：先按“Domain + IP”成对使用
对大多数用户，推荐这样搭配：
- `cn` + `cn-ip`
- `google` + `google-ip`

虽然不同客户端里名字表现不一定完全写成 `*-ip`，但思路就是：
- Domain 规则负责按域名分流
- IP 规则负责补充 IP 范围

一句话理解：
- 能用 Domain 的地方优先 Domain
- 需要补足 IP 范围时再配套加 IP

### 第 3 步：直接抄下面的配置示例
如果你是：
- Surge 用户：看“Surge 示例”
- QuanX 用户：看“QuanX 示例”
- sing-box 用户：看“sing-box 示例”
- mihomo 用户：看“mihomo 示例”
- Egern 用户：看“Egern 示例”

--------------------------------------------------

## 二、最推荐的几套组合（适合中国用户）

### 1. 最省心基础版
适合：大多数日常上网用户

推荐规则：
- `cn`
- `google`
- `telegram`
- `apple`
- `github`

用途：
- 国内走直连
- 常见海外服务走代理
- 苹果/GitHub/Telegram 基本都能覆盖

### 2. 常用增强版
适合：经常用 AI、开发工具、海外服务的用户

推荐规则：
- `cn`
- `google`
- `telegram`
- `apple`
- `github`
- `openai`
- `cloudflare`

用途：
- 比基础版更适合开发者和 AI 用户

### 3. 流媒体版
适合：有 Netflix / Spotify / Disney+ 需求的用户

在“常用增强版”基础上增加：
- `netflix`
- `spotify`
- `disney`

### 4. 广告拦截版
适合：希望尽量减少广告和骚扰域名

在原有规则上增加：
- `awavenue-ads`

### 5. Emby 分流版
适合：自己有 Emby / 媒体服务分流需求

增加：
- `emby`
- `emby-cn`

--------------------------------------------------

## 三、订阅地址怎么选？

你只需要先确认两件事：
- 你用的是什么客户端
- 你要的是 Domain 规则还是 IP 规则

通用地址模板：

```text
Surge Domain     https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/{name}.list
Surge IP         https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/{name}.list
QuanX Domain     https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/{name}.list
QuanX IP         https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/{name}.list
Egern Domain     https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/{name}.yaml
Egern IP         https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/{name}.yaml
sing-box Domain  https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/{name}.srs
sing-box IP      https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/{name}.srs
mihomo Domain    https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/{name}.mrs
mihomo IP        https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/{name}.mrs
```

说明：
- `{name}` 替换成规则名，例如：`cn`、`google`、`telegram`
- 一般来说：
  - Domain 更适合按域名分流
  - IP 更适合补充直连/代理范围
- 实战里通常 Domain + IP 搭配使用

--------------------------------------------------

## 四、直接可抄的配置示例

### 1. Surge

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/google.list,PROXY
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/google.list,PROXY
```

### 2. Quantumult X（QuanX）

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/google.list, tag=GOOGLE-DOMAIN, force-policy=proxy, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/google.list, tag=GOOGLE-IP, force-policy=proxy, enabled=true
```

### 3. sing-box

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs"
      },
      {
        "tag": "cn-ip",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/cn.srs"
      }
    ]
  }
}
```

### 4. mihomo

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/cn.mrs"
    interval: 86400

  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/cn.mrs"
    interval: 86400
```

### 5. Egern

```text
Domain https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml
IP     https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml
```

--------------------------------------------------

## 五、常用规则组推荐

### 常用 Domain 规则
- cn
- google
- youtube
- apple
- telegram
- netflix
- spotify
- disney
- github
- openai
- cloudflare

### 广告规则
- awavenue-ads

### 常用 IP 规则
- cn
- google
- telegram
- cloudflare
- cloudfront
- aws
- fastly
- github
- apple
- netflix
- spotify
- disney

推荐搭配：
- 国内直连：cn
- 国外代理：google / telegram / github / openai
- 流媒体：netflix / spotify / disney
- 广告拦截：awavenue-ads

--------------------------------------------------

## 六、不同客户端的文件格式说明

### Surge
- Domain：`.list`
- IP：`.list`

### QuanX
- Domain：`.list`
- IP：`.list`
- 规则中会带策略字段，建议配合 `force-policy`

### Egern
- Domain：`.yaml`
- IP：`.yaml`

### sing-box
- Domain：`.srs`
- IP：`.srs`
- 二进制规则集，适合 remote rule_set

### mihomo
- Domain：`.mrs`
- IP：`.mrs`
- 二进制规则集，适合 rule-providers

--------------------------------------------------

## 七、常见问题（FAQ）

### 1. Domain 和 IP 到底有什么区别？
简单理解：
- Domain：按域名匹配，通常更直观、更常用
- IP：按 IP 段匹配，适合补充分流范围

建议：
- 普通用户优先用 Domain
- 如果规则不完整或客户端配置需要，再补 IP

### 2. 我到底要不要两个都加？
建议：
- 大多数情况下，加 Domain + IP 更稳
- 如果你只想先快速用起来，也可以先只上 Domain，后续再补 IP

### 3. 我应该先从哪些规则开始？
最常见起步组合：
- `cn`
- `google`
- `telegram`
- `apple`
- `github`

### 4. 我不懂这些规则名是什么意思怎么办？
你可以直接把它们理解成“网站/服务分类”即可，例如：
- `cn`：国内常用
- `google`：Google 相关
- `telegram`：Telegram 相关
- `apple`：Apple 相关
- `github`：GitHub 相关
- `openai`：OpenAI 相关

### 5. 自定义规则会不会覆盖原规则？
不会直接覆盖已有官方规则组。
但你新增自定义规则时：
- 名字不能和已有规则组重名

--------------------------------------------------

## 八、自定义规则怎么加？

如果仓库自带规则不够，你可以自己加。

### 1. 自定义 Domain 规则
在目录里新建文件：
- `sources/custom/domain/{name}.list`

示例：

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,keyword
```

### 2. 自定义 IP 规则
在目录里新建文件：
- `sources/custom/ip/{name}.list`

示例：

```text
IP-CIDR,1.2.3.0/24
IP-CIDR6,2403:300::/32
```

### 3. 规则书写说明
- Domain 类型大小写不敏感
- `_` 和 `-` 等价
  - 例如：`DOMAIN_SUFFIX` = `DOMAIN-SUFFIX`
- 构建时会自动标准化：
  - `DOMAIN` / `DOMAIN-SUFFIX` 转小写并去掉末尾 `.`
  - `DOMAIN-KEYWORD` 转小写
- 上游导出兼容别名：
  - `domain-suffix`
  - `domain_suffix`
  - `suffix`
  - `domain-full`
  - `domain-keyword`
  - `domain-regex`
  - `regex`

### 4. 注意事项
- 自定义规则名不要和已有规则组重名
- 新增后会自动参与构建和发布流程

--------------------------------------------------

## 九、仓库结构怎么理解？

```text
README.md                     项目说明
.github/workflows/build.yml   自动构建与发布流程
scripts/                      构建、同步、校验脚本
sources/custom/               自定义规则源
```

你一般只需要关心：
- 使用者：看 README + 订阅地址
- 自定义维护者：看 `sources/custom/`
- 开发维护者：看 `scripts/` 和 workflow

--------------------------------------------------

## 十、这个仓库会自动做什么？

GitHub Actions 会自动完成：
- 检查脚本
- 校验自定义规则
- 测试域名解析逻辑
- 同步上游规则
- 构建多客户端产物
- 发布到对应分支

主要发布分支：
- surge
- quanx
- egern
- sing-box
- mihomo

主分支 `main`：
- 存放源码、脚本、工作流、自定义规则

--------------------------------------------------

## 十一、上游来源

### Domain 来源
- v2fly domain-list-community
- AWAvenue Ads Rule（广告规则）

### IP 来源
- ispip clang
- china-operator-ip
- Google
- Telegram
- Cloudflare
- AWS / CloudFront
- Fastly
- GitHub
- Apple
- RIPE NCC Stat

详细实现可查看：
- `scripts/sync-upstream.sh`

--------------------------------------------------

## 十二、适合谁用？

适合：
- 想直接抄规则地址的人
- 同时维护多个客户端规则的人
- 需要自定义分流规则的人
- 用 sing-box / mihomo / Surge / QuanX / Egern 的用户

如果你只是普通用户：
- 直接看“5 分钟上手”“最推荐的几套组合”“配置示例”就够了

如果你要自己维护：
- 重点看“自定义规则怎么加”和仓库里的 `scripts/`

--------------------------------------------------

## 十三、这版 README 的阅读顺序建议

按中文用户最常见的阅读路径，推荐这样看：
1. 先看“5 分钟上手”
2. 再看“最推荐的几套组合”
3. 然后直接抄“配置示例”
4. 有需要再看“FAQ”
5. 最后才看“自定义规则”和“仓库结构”

这样更符合中文用户的使用习惯：
- 先解决能不能用
- 再解决怎么配置
- 最后再看原理和维护细节
