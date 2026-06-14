# Rules / QuanX

Generated artifacts for Quantumult X.
This branch intentionally contains only the final QuanX rule files and this README.

## Contents

- [domain/](./domain/)
- [ip/](./ip/)

QuanX plain-text rule files in this branch use the `.list` extension.
Rules are emitted with QuanX types (`HOST`, `HOST-SUFFIX`, `HOST-KEYWORD`, `IP-CIDR`, `IP6-CIDR`) and an explicit policy tag in field 3.
Using `force-policy` in `filter_remote` is recommended.

## Example

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```
