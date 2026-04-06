# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)
[![Repo Size](https://img.shields.io/github/repo-size/KuGouGo/Rules)](https://github.com/KuGouGo/Rules)
[![Surge](https://img.shields.io/badge/client-Surge-orange)](https://github.com/KuGouGo/Rules/tree/surge)
[![sing-box](https://img.shields.io/badge/client-sing--box-blue)](https://github.com/KuGouGo/Rules/tree/sing-box)
[![mihomo](https://img.shields.io/badge/client-mihomo-green)](https://github.com/KuGouGo/Rules/tree/mihomo)

A rule repository that keeps source files on `main` and publishes ready-to-use artifacts to the `surge`, `sing-box`, and `mihomo` branches.

## What This Repo Does

- syncs domain artifacts from `v2fly/domain-list-community`
- syncs IP artifacts from curated CN, Google, Telegram, Apple, Cloudflare, CloudFront, and Fastly sources
- builds local custom domain and IP rules into all supported client formats
- publishes client-specific branches: `surge`, `sing-box`, and `mihomo`

## Branches

- `main`: source files, scripts, workflows, and documentation
- `surge`: final Surge artifacts only
- `sing-box`: final sing-box artifacts only
- `mihomo`: final mihomo artifacts only

## Quick Links

- [Surge](https://github.com/KuGouGo/Rules/tree/surge)
- [sing-box](https://github.com/KuGouGo/Rules/tree/sing-box)
- [mihomo](https://github.com/KuGouGo/Rules/tree/mihomo)
- [Intermediate Artifacts](./docs/intermediate-artifacts.md)

## Layout

```text
.
|-- .github/         # CI workflows
|-- docs/            # conversion and maintenance notes
|-- scripts/         # sync/build/publish scripts
|-- sources/         # editable rule sources only
`-- README.md
```

## Directory Roles

- `sources/`: hand-maintained rule inputs. Custom sources live under `sources/custom/`.
- `.output/`: local build output directory, ignored on `main`, and used as the publish source for client-specific branches.

## Custom Sources

- editable custom inputs live under `sources/custom/`
- generated client artifacts are written to `.output/`
- intermediate conversion formats are documented in [Intermediate Artifacts](./docs/intermediate-artifacts.md)

## Workflow

GitHub Actions will:

1. lint custom rule sources
2. choose between a full sync or a custom-only fast path
3. resolve the latest official `sing-box` and `mihomo` core versions
4. sync upstream rule artifacts when a full refresh is needed
5. build local custom artifacts
6. verify artifact integrity
7. publish to client-specific branches

The `main` branch does not keep synced upstream artifacts. Generated files are built in CI or locally under `.output/` and then published to the client branches.
Each published client branch is trimmed to `README.md`, `domain/`, and `ip/` only.
The tool bootstrap layer resolves the latest official `sing-box` and `mihomo` releases at runtime instead of pinning them in the repo.
Build scripts are intended for GitHub Actions or non-Windows shell environments.

Triggers:

- manual `workflow_dispatch` with `auto`, `custom`, or `full` scope
- scheduled sync once per day at 08:00 UTC
- pushes that modify workflows, scripts, or custom sources

Pushes that only add or edit `sources/custom/**` now reuse the currently published client branches as the artifact baseline, rebuild custom outputs, and skip the expensive upstream sync step. Scheduled runs, workflow/tooling changes, custom deletions, and manual full runs still refresh all upstream artifacts.

## Branch Usage

Surge:

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```

sing-box:

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/domain/cn.srs"
      },
      {
        "tag": "cn-ip",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/KuGouGo/Rules/sing-box/ip/cn.srs"
      }
    ]
  }
}
```

mihomo:

```yaml
rule-providers:
  cn:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/cn.mrs"
    interval: 86400

  apple:
    type: http
    behavior: domain
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/domain/apple.mrs"
    interval: 86400

  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/cn.mrs"
    interval: 86400
```

Domain rules are compiled to mihomo `mrs` after keeping `DOMAIN` and `DOMAIN-SUFFIX`.
`DOMAIN-KEYWORD` and `DOMAIN-REGEX` are kept for sing-box output.
For mihomo `mrs`, only `DOMAIN` and `DOMAIN-SUFFIX` are used.
Lists without any `DOMAIN` / `DOMAIN-SUFFIX` entries are treated as invalid for mihomo output.

## Upstream

- Domain source: <https://github.com/v2fly/domain-list-community>
- CN IP sources: <https://ispip.clang.cn/all_cn.txt> and <https://ispip.clang.cn/all_cn_ipv6.txt>
- Google IP source: <https://www.gstatic.com/ipranges/goog.json>
- Telegram IP source: <https://core.telegram.org/resources/cidr.txt>
- Apple IP source: <https://support.apple.com/en-us/101555>
- Cloudflare IP source: <https://www.cloudflare.com/ips/>
- CloudFront IP source: <https://ip-ranges.amazonaws.com/ip-ranges.json>
- Fastly IP source: <https://api.fastly.com/public-ip-list>
- mihomo converter: <https://github.com/MetaCubeX/mihomo>
