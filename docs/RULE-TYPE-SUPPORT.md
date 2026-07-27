# 规则类型平台支持说明

## 域名规则类型支持矩阵

| 规则类型 | Surge | QuanX | Egern | sing-box | mihomo |
|---------|-------|-------|-------|----------|--------|
| DOMAIN | ✅ | ✅ | ✅ | ✅ | ✅ |
| DOMAIN-SUFFIX | ✅ | ✅ | ✅ | ✅ | ✅ |
| DOMAIN-KEYWORD | ✅ | ✅ | ✅ | ✅ | ❌ |
| DOMAIN-REGEX | ❌ | ❌ | ✅ | ✅ | ❌ |

---

## DOMAIN-REGEX 不支持的影响

### 受影响平台
- **Surge**：不支持 DOMAIN-REGEX，规则会被跳过
- **QuanX**：不支持 DOMAIN-REGEX，规则会被跳过
- **mihomo**：不支持 DOMAIN-REGEX，规则会被跳过

### 当前使用情况
本仓库中 DOMAIN-REGEX 规则主要用于 `fakeip-filter.list`，用于排除 Fake-IP 以避免连接失败。

**关键场景**：
- **NTP 时间同步**：`^time\.[^.]+\.com$` 匹配 `time.windows.com`、`time.apple.com` 等
- **Xbox Live**：`^xbox\.[^.]+\.microsoft\.com$` 匹配 Xbox 服务发现域名
- **STUN 穿透**：`^(?:.+\.)?stun(?:\.[^.]+){2,5}$` 匹配各类 STUN 服务器
- **微信本地调试**：`^localhost\.[^.]+\.weixin\.qq\.com$`

### 缓解方案

#### 方案一：使用支持 REGEX 的客户端（推荐）
- **Egern**（iOS）：完整支持 DOMAIN-REGEX
- **sing-box**（全平台）：完整支持 DOMAIN-REGEX

#### 方案二：使用 SUFFIX 备选规则（已实施）
`fakeip-filter.list` 已为关键服务增加 SUFFIX 备选规则：

```
# REGEX（精确）
DOMAIN-REGEX,^xbox\.[^.]+\.microsoft\.com$

# SUFFIX 备选（兼容 Surge/QuanX/mihomo，稍宽松）
DOMAIN-SUFFIX,xboxlive.com
DOMAIN-SUFFIX,xboxservices.com
```

**优点**：兼容所有平台  
**缺点**：SUFFIX 匹配范围更广，可能包含不需要排除的子域名

#### 方案三：手工为不支持平台添加白名单
在客户端配置中手工添加常见服务域名到 DNS 直连白名单：

**Surge 示例**：
```
[Rule]
DOMAIN-SUFFIX,time.windows.com,DIRECT
DOMAIN-SUFFIX,xboxlive.com,DIRECT
DOMAIN-SUFFIX,stunprotocol.org,DIRECT
```

**mihomo (Clash) 示例**：
```yaml
rules:
  - DOMAIN-SUFFIX,time.windows.com,DIRECT
  - DOMAIN-SUFFIX,xboxlive.com,DIRECT
  - DOMAIN-SUFFIX,stunprotocol.org,DIRECT
```

---

## DOMAIN-KEYWORD 不支持的影响

### 受影响平台
- **mihomo**：不支持 DOMAIN-KEYWORD，规则会被跳过

### 缓解方案
DOMAIN-KEYWORD 通常可以拆分为多条 DOMAIN-SUFFIX 规则：

**转换前**：
```
DOMAIN-KEYWORD,google
```

**转换后**：
```
DOMAIN-SUFFIX,google.com
DOMAIN-SUFFIX,google.co.jp
DOMAIN-SUFFIX,google.com.hk
DOMAIN-SUFFIX,googleapis.com
DOMAIN-SUFFIX,googleusercontent.com
```

---

## IP 规则类型支持矩阵

| 规则类型 | Surge | QuanX | Egern | sing-box | mihomo |
|---------|-------|-------|-------|----------|--------|
| IP-CIDR | ✅ | ✅ | ✅ | ✅ | ✅ |
| IP-CIDR6 | ✅ | ✅ | ✅ | ✅ | ✅ |

**注**：QuanX 使用 `IP6-CIDR` 代替 `IP-CIDR6`，本仓库自动转换。

---

## 规则顺序与优先级

### 不保证顺序的平台
- **sing-box**：rule-set 内部按类型分组，类型间顺序不保证
- **mihomo**：二进制格式，顺序由编译器决定

### 最佳实践
❌ **不应依赖规则源文件顺序**  
✅ **应通过规则精确度控制匹配优先级**

规则精确度（从高到低）：
1. `DOMAIN`：完全匹配（最精确）
2. `DOMAIN-SUFFIX`：后缀匹配
3. `DOMAIN-KEYWORD`：子串匹配
4. `DOMAIN-REGEX`：正则匹配（取决于模式复杂度）

**示例**：
```
# 好的实践（通过精确度控制）
DOMAIN,exact.example.com          # 优先级最高
DOMAIN-SUFFIX,example.com         # 次优先
DOMAIN-KEYWORD,example            # 最低

# 不推荐（依赖顺序）
DOMAIN-KEYWORD,example            # 可能误匹配
DOMAIN,exact.example.com          # 顺序不保证
```

---

## 构建输出说明

构建时会输出每个规则集的统计信息：

```
Building domain rules for emby: 15 rules (DOMAIN=5, SUFFIX=8, KEYWORD=2, REGEX=0)
domain summary: emby skips unsupported rules for surge: DOMAIN-REGEX=0
domain summary: emby skips unsupported rules for quanx: DOMAIN-REGEX=0
domain summary: emby skips unsupported rules for mihomo: DOMAIN-KEYWORD=2, DOMAIN-REGEX=0
```

**mihomo MRS 警告**：
当跳过规则超过 30% 时会打印警告：
```
mihomo mrs warning: fakeip-filter skips 50% unsupported rules (threshold 30%)
```

---

## 相关资源

- [Surge 规则语法](https://manual.nssurge.com/rule/)
- [Quantumult X 规则语法](https://github.com/crossutility/Quantumult-X)
- [Egern 规则语法](https://book.egernapp.com/)
- [sing-box rule-set 规范](https://sing-box.sagernet.org/configuration/rule-set/)
- [Clash Premium 规则提供器](https://dreamacro.github.io/clash/premium/rule-providers.html)
