# Rules / Surge

Generated artifacts for Surge.
This branch intentionally contains only the final Surge rule files and this README.

## Contents

- [domain/](./domain/)
- [ip/](./ip/)

Surge plain-text rule files in this branch use the `.list` extension.

## Example

```ini
[Rule]
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```
