# Rules / mihomo

此分支提供 mihomo 的滚动构建产物，仅保留 `README.md`、`domain/` 和 `ip/`。分支内容会随构建覆盖更新，不是固定版本快照；需要可复现内容时请固定提交 SHA。

## 项目与许可

- [主 README](https://github.com/KuGouGo/Rules/blob/main/README.md)
- [NOTICE](https://github.com/KuGouGo/Rules/blob/main/NOTICE)
- [LICENSE](https://github.com/KuGouGo/Rules/blob/main/LICENSE)
- [THIRD_PARTY_NOTICES](https://github.com/KuGouGo/Rules/blob/main/THIRD_PARTY_NOTICES.md)

## 产物格式与能力降级

- `domain/` 与 `ip/` 均使用二进制 `.mrs` 扩展名。
- 域名产物仅保留精确域名和域名后缀；域名关键词与正则会降级丢弃，仅含这些类型的列表不会发布。
- IP CIDR 保留；`.mrs` 仅供 mihomo 使用，不能假定与其他客户端的二进制规则格式兼容。
- `domain/fakeip-filter.mrs` 由 KuGouGo 在主分支维护的 `sources/custom/domain/fakeip-filter.list` 编译生成；它不是第三方预编译下载。过去采用 `wwqgtxx/clash-rules` 二进制仅属历史。

## 最小示例

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/cn.mrs
```

## v2fly/domain-list-community MIT 通知

本分支的域名产物包含或派生自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)：

> MIT License
>
> Copyright (c) 2018-2019 V2Ray
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.
