# 使用 geolocation-!cn 规则集

本仓库每日自动同步 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) 的数据，包括 `geolocation-!cn`（非中国大陆域名）规则集。

## 可用的规则集

### 综合规则
- **geolocation-!cn** - 所有非中国大陆域名（340+ 条规则）

### 分类规则
- **category-ai-!cn** - AI 服务（OpenAI, Anthropic 等）
- **category-ai-chat-!cn** - AI 聊天服务
- **category-browser-!cn** - 浏览器相关
- **category-cdn-!cn** - CDN 服务
- **category-games-!cn** - 游戏平台
- **category-scholar-!cn** - 学术资源
- **category-social-media-!cn** - 社交媒体

更多分类请查看：https://github.com/v2fly/domain-list-community/tree/master/data

## 使用方法

### Surge

```ini
[Rule]
# 使用完整的非中国大陆规则集
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/geolocation-!cn.list,PROXY

# 或使用分类规则集
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/category-ai-!cn.list,PROXY
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/category-games-!cn.list,PROXY
```

### sing-box

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "geolocation-not-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/geolocation-!cn.srs"
      }
    ],
    "rules": [
      {"rule_set": ["geolocation-not-cn"], "outbound": "proxy"}
    ]
  }
}
```

### mihomo (Clash Meta)

```yaml
rule-providers:
  geolocation-not-cn:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/geolocation-!cn.mrs"
    interval: 86400

rules:
  - RULE-SET,geolocation-not-cn,PROXY
```

### Quantumult X

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/geolocation-!cn.list, tag=非中国大陆, force-policy=proxy, enabled=true
```

### Egern

```yaml
rule-sets:
  geolocation-not-cn:
    type: http
    format: yaml
    url: https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/geolocation-!cn.yaml
    interval: 86400

rules:
  - rule-set: geolocation-not-cn
    policy: proxy
```

## 更新频率

- **自动更新**：每日 UTC 08:00（北京时间 16:00）
- **数据来源**：v2fly/domain-list-community
- **支持平台**：Surge, Quantumult X, Egern, sing-box, mihomo

## 注意事项

1. **文件名中的感叹号**：
   - 在 URL 中使用 `geolocation-!cn`（保持原样）
   - 某些系统可能需要转义：`geolocation-\!cn`

2. **与 geolocation-cn 的区别**：
   - `geolocation-cn` - 中国大陆域名（直连）
   - `geolocation-!cn` - 非中国大陆域名（代理）

3. **规则优先级**：
   - 建议先匹配 `cn` 规则（直连）
   - 再匹配 `!cn` 规则（代理）
   - 最后使用默认策略

## 完整配置示例

### Surge 完整配置

```ini
[Rule]
# 1. 广告拦截
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/awavenue-ads.list,REJECT

# 2. 中国大陆直连
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT

# 3. 非中国大陆代理
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/geolocation-!cn.list,PROXY

# 4. 默认策略
FINAL,DIRECT
```

## 数据来源

- [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) - 域名规则
- [TG-Twilight/AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule) - 广告拦截
- 各官方 API - IP 规则（Google, Telegram, Cloudflare, AWS 等）

## 相关链接

- [v2fly/domain-list-community#390](https://github.com/v2fly/domain-list-community/issues/390) - 关于 @!cn 属性的讨论
- [项目主页](https://github.com/KuGouGo/Rules)
- [GitHub Actions 构建状态](https://github.com/KuGouGo/Rules/actions)
