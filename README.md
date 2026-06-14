# Rules / mihomo

Generated artifacts for mihomo.
This branch intentionally contains only the final mihomo rule files and this README.

## Contents

- [domain/](./domain/)
- [ip/](./ip/)

Domain rules use binary `.mrs` files.
IP rules use binary `.mrs` files.

## Example

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
