# KuGouGo Rules

[![GitHub last commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/master)

为网络代理工具提供的emby规则集，自动更新。

---

## 🚀 用法

直接使用文件的 Raw URL 即可。

**Raw 文件基础 URL:** `https://raw.githubusercontent.com/KuGouGo/Rules/master/`

---

**1. `emby.list` (通用域名列表)**

适用于 Surge / Loon / Stash / Clash (rule-provider) 等。

*   **示例 (Surge / Loon):**
    ```
    # Surge / Loon 的 [Rule] 段
    DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/master/emby.list,DIRECT
    ```
*   **示例 (Stash):**
    *   可以直接在 Stash 的覆写 (Overrides) 中引用，或在配置文件的 `rule-set` 部分引用。
*   **示例 (Clash Rule Provider):**
    ```yaml
    # Clash 配置文件的 rule-providers 段
    rule-providers:
      emby:
        type: http
        behavior: domain # 如果是 IP 列表用 ipcidr，如果是完整规则用 classical
        url: "https://raw.githubusercontent.com/KuGouGo/Rules/master/emby.list"
        path: ./ruleset/emby.yaml # 本地缓存路径
        interval: 86400 # 更新间隔 (秒, 86400 为 1 天)

    # Clash 配置文件的 rules 段
    rules:
      - RULE-SET,emby,DIRECT # 或其他你希望走的策略
    ```

---

**2. `emby.srs` (sing-box 规则集)**

用于 sing-box 的 `route.rules`。

*   **定义 Rule Set (在 `route.rule_set` 数组中):**
    ```json
    {
      "tag": "emby-rules",      // 自定义标签名
      "type": "remote",         // 类型为远程
      "format": "source",       // 格式为 source (明文规则)
      "url": "https://raw.githubusercontent.com/KuGouGo/Rules/master/emby.srs", // 文件 URL
      "download_detour": "DIRECT" // 下载规则时使用的出口 (outbound)
      // 可选: "update_interval": "1d" // 更新间隔，例如 "1d" 代表一天
    }
    ```
*   **在规则中引用 (在 `route.rules` 数组中):**
    ```json
    {
      "rule_set": "emby-rules", // 引用上面定义的 rule_set 标签
      "outbound": "DIRECT"      // 符合该规则集的流量的目标出口 (outbound)
    }
    ```

---

## ⚠️ 注意

*   规则通过 GitHub Actions 自动更新。
*   请自行承担使用风险，不当配置可能导致网络问题。
