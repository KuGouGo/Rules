# Rules

[![Build](https://img.shields.io/github/actions/workflow/status/KuGouGo/Rules/build.yml?branch=main&label=build)](https://github.com/KuGouGo/Rules/actions/workflows/build.yml)
[![Last Commit](https://img.shields.io/github/last-commit/KuGouGo/Rules)](https://github.com/KuGouGo/Rules/commits/main)
[![Repo Size](https://img.shields.io/github/repo-size/KuGouGo/Rules)](https://github.com/KuGouGo/Rules)
[![Surge](https://img.shields.io/badge/client-Surge-orange)](https://github.com/KuGouGo/Rules/tree/surge)
[![sing-box](https://img.shields.io/badge/client-sing--box-blue)](https://github.com/KuGouGo/Rules/tree/sing-box)
[![mihomo](https://img.shields.io/badge/client-mihomo-green)](https://github.com/KuGouGo/Rules/tree/mihomo)

A rule repository that keeps source files on `main` and publishes ready-to-use artifacts to the `surge`, `sing-box`, and `mihomo` branches.

## What This Repo Does

- syncs domain artifacts from `nekolsd/sing-geosite`
- syncs IP artifacts from `nekolsd/geoip`
- builds local custom domain rules into all supported client formats
- publishes client-specific branches: `surge`, `sing-box`, and `mihomo`

## Branches

- `main`: source files, scripts, workflows, and documentation
- `surge`: generated Surge artifacts
- `sing-box`: generated sing-box artifacts
- `mihomo`: generated mihomo artifacts

## Quick Links

- [Surge](https://github.com/KuGouGo/Rules/tree/surge)
- [sing-box](https://github.com/KuGouGo/Rules/tree/sing-box)
- [mihomo](https://github.com/KuGouGo/Rules/tree/mihomo)

## Layout

```text
.
|-- .github/         # CI workflows
|-- scripts/         # sync/build/publish scripts
|-- sources/         # editable rule sources only
|-- tools/           # vendored helper code and generators
`-- README.md
```

## Directory Roles

- `sources/`: hand-maintained rule inputs. Custom domain lists live in `sources/domain/custom/`.
- `tools/`: vendored helper code or upstream tooling kept in-repo for maintenance. `tools/geoip/` contains the geoip generator source that was previously mixed into `sources/`.
- `domain/` and `ip/`: local build output directories, ignored on `main`, and published only to client-specific branches.

## Custom Sources

Custom domain lists live in `sources/domain/custom/`.

Supported entries:

- `DOMAIN,example.com`
- `DOMAIN-SUFFIX,example.com`

Generated outputs:

- `domain/surge/<name>.list`
- `domain/sing-box/<name>.srs`
- `domain/mihomo/<name>.mrs`

## Workflow

GitHub Actions will:

1. lint custom rule sources
2. sync upstream rule artifacts
3. build local custom artifacts
4. verify artifact integrity
5. publish to client-specific branches

The `main` branch does not keep synced upstream artifacts. Generated files are built in CI or locally and then published to the client branches.

Triggers:

- manual `workflow_dispatch`
- scheduled sync every 6 hours
- pushes that modify workflows, scripts, custom sources, or vendored tooling

## Branch Usage

Surge:

```ini
[Rule]
DOMAIN-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
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

  cn-ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: "https://raw.githubusercontent.com/KuGouGo/Rules/mihomo/ip/cn.mrs"
    interval: 86400
```

## Upstream

- Domain Surge / sing-box: <https://github.com/nekolsd/sing-geosite>
- IP Surge / sing-box / mihomo: <https://github.com/nekolsd/geoip>
- mihomo converter: <https://github.com/MetaCubeX/mihomo>
