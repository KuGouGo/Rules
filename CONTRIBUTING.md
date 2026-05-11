# Contributing

## Add or change custom rules

Domain rule files live in `sources/custom/domain/*.list`.

Supported domain rule types:

```text
DOMAIN,api.example.com
DOMAIN-SUFFIX,example.com
DOMAIN-KEYWORD,example
DOMAIN-REGEX,^(.+\.)?example\.com$
```

IP rule files live in `sources/custom/ip/*.list`.

Supported IP rule types:

```text
IP-CIDR,1.2.3.0/24
IP-CIDR6,2001:db8::/32
```

File names must use lowercase letters, digits, and hyphens only, for example `emby-cn.list`.

## Rule quality checks

`make lint` rejects custom rules that would otherwise be silently normalized or dropped during the build:

- duplicate rules in the same file
- `DOMAIN` entries already covered by a `DOMAIN-SUFFIX` in the same file
- narrower `DOMAIN-SUFFIX` entries already covered by a broader suffix in the same file
- invalid `DOMAIN`/`DOMAIN-SUFFIX` labels, uppercase values, leading or trailing dots
- invalid `DOMAIN-REGEX` patterns
- non-canonical CIDRs such as `192.168.1.1/24`
- duplicate or redundant CIDRs in the same file

## Config quality checks

`make lint` also validates repository config files:

- upstream sources must declare supported `kind` and `trust` values
- URL fields must be absolute `https://` URLs
- configured parsers must be supported by local tooling
- minimum count and byte thresholds must be positive integers
- required upstream sources, first-batch baselines, ASN groups, and platform capability entries must exist
- platform capability rule types must be supported domain rule types

## Validate locally

Run the full local validation suite:

```bash
make validate
```

Before pushing changes, run the local preflight check:

```bash
make preflight
```

For a faster custom-rule output check that does not download `sing-box` or `mihomo`, run:

```bash
make build-custom-text
```

## Change generation logic

When changing scripts or parsers:

- Add or update fixtures in `tests/fixtures/` when output behavior changes intentionally.
- Add a `scripts/tests/test-*.sh` test for new shell or Python behavior.
- Run `make validate` before publishing.

The test runner automatically discovers `scripts/tests/test-*.sh`, so new test scripts do not need to be added to the `Makefile`.
