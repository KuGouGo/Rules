# 规则类型与平台转换

仓库以规范化的 classical 规则作为中间表示，再按客户端能力生成文本或二进制产物。

## 域名规则

| 规范类型 | Surge | Quantumult X | Egern | sing-box | mihomo MRS |
| --- | --- | --- | --- | --- | --- |
| `DOMAIN` | `DOMAIN` | `HOST` | `domain_set` | `domain` | plain domain |
| `DOMAIN-SUFFIX` | `DOMAIN-SUFFIX` | `HOST-SUFFIX` | `domain_suffix_set` | `domain_suffix` | leading-dot domain |
| `DOMAIN-KEYWORD` | `DOMAIN-KEYWORD` | `HOST-KEYWORD` | `domain_keyword_set` | `domain_keyword` | unsupported |
| `DOMAIN-REGEX` | unsupported | unsupported | `domain_regex_set` | `domain_regex` | unsupported |

不支持的规则不会被近似转换，因为用更宽泛的 `DOMAIN-SUFFIX` 或 `DOMAIN-KEYWORD` 替代正则会改变匹配集合。构建日志和 `overlap-report.json` 会记录平台转换损失。

如果一个规则集必须在所有平台保持同等覆盖，应在源规则中维护语义明确的兼容条目，而不是由转换器自动猜测降级规则。

## IP 规则

| 规范类型 | Surge | Quantumult X | Egern | sing-box | mihomo MRS |
| --- | --- | --- | --- | --- | --- |
| `IP-CIDR` | `IP-CIDR` | `IP-CIDR` | `ip_cidr_set` | `ip_cidr` | plain CIDR |
| `IP-CIDR6` | `IP-CIDR6` | `IP6-CIDR` | `ip_cidr6_set` | `ip_cidr` | plain CIDR |

IP 规则在进入平台渲染前统一规范化、精确去重并折叠包含或相邻网段。sing-box 的 `ip_cidr` 字段允许 IPv4 和 IPv6 混合。

## 完整性原则

1. 源格式解析失败时终止构建，不静默忽略有效行中的错误。
2. 只做可证明语义等价的规范化，例如域名大小写统一、CIDR 主机位归一化、CIDR 并集折叠。
3. 每个规则集可独立订阅，因此跨规则集重叠只审计，不自动删除。
4. 平台不支持的类型只记录损失，不自动扩大或缩小匹配范围。
5. sing-box 和 mihomo 二进制产物必须存在、非空，并通过反编译往返验证。

## 并行编译

二进制编译使用仓库统一的 `RULES_COMPILE_JOBS` 配置。未设置时自动检测 CPU，但最多使用 4 个并发任务，避免在 CI 和低内存设备上产生过高峰值内存。

```bash
RULES_COMPILE_JOBS=2 make build-custom
```

该变量必须是正整数。文本转换、规则语义和产物事务不受并行度影响。
