# KuGouGo Rules for Emby

[![GitHub last commit](https://img.shields.io/github/last-commit/KuGouGo/Rules?label=Last%20Updated)](https://github.com/KuGouGo/Rules/commits/main)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/update-rules.yml?branch=main&label=Auto%20Update)](https://github.com/KuGouGo/Rules/actions/workflows/update-rules.yml)

**自动更新**的 Emby 专用网络代理规则集。

---

## ✨ 文件说明

*   **`emby.list`**: 纯文本域名列表，兼容多数客户端。
*   **`emby.json`**: sing-box JSON 规则源片段。
*   **`emby.srs`**: sing-box 编译后的二进制规则集 (推荐 sing-box 使用)。

---

## 🚀 使用方法

### 规则列表 URL (通用)

https://raw.githubusercontent.com/KuGouGo/Rules/master/emby.list

### 客户端配置

**通用说明:**
*   以下示例中 `DIRECT` 策略表示直连。请根据你的需求将其替换为希望使用的策略名称（例如 `PROXY` 或特定的策略组）。
*   确保规则在客户端的规则列表中**优先级较高**，避免被后续的通用规则（如 `FINAL` 或 `MATCH`）覆盖。

**1. Surge / Loon / Quantumult X (UI 添加)**

*   **在 App 的 **规则 (Rules)** 或 **规则集 (Rule Sets)** / **外部资源 (External Resources)** / **远程规则 (Remote Rule)** 部分添加新规则。

**2. Stash / Clash (Mihomo/Meta Core) (文本配置)**

*   **添加到 `rule-providers` (或 Stash `rule-set`) 段:**
    ```yaml
    emby:
      type: http
      behavior: classical
      format: text
      url: "https://raw.githubusercontent.com/KuGouGo/Rules/master/emby.list"
      interval: 86400         
    ```
**3. sing-box (文本配置)**

*   **规则集 URL (推荐):** `https://raw.githubusercontent.com/KuGouGo/Rules/master/emby.srs`
*   **添加到 `route.rule_set` 数组:**
    ```json
    {
      "tag": "emby-rules",
      "type": "remote",
      "format": "binary",
      "url": "https://raw.githubusercontent.com/KuGouGo/Rules/master/emby.srs",
      "download_detour": "DIRECT", 
      "update_interval": "1d"      
    }
    ```
---

## ⚙️ 自动更新

本仓库使用 [GitHub Actions](https://github.com/KuGouGo/Rules/actions) 自动处理 `emby.list` 文件，并生成 `emby.json` 和 `emby.srs`。

---

## ⚠️ 注意事项

*   规则集旨在匹配 Emby 相关域名和 IP。请根据网络环境选择合适的策略（如 `DIRECT` 或 `PROXY`）。
*   使用风险自负。不当配置可能导致网络问题。
