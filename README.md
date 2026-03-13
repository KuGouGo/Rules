# Rules

Convert upstream geosite and geoip data into formats suitable for:

- **Surge**: generic text/ruleset files
- **sing-box**: `.srs`
- **mihomo**: `.mrs`

## Upstream sources

- Geosite: <https://github.com/nekolsd/sing-geosite>
- GeoIP: <https://github.com/nekolsd/geoip>

## Planned outputs

### Geosite

- `geosite/surge/*.txt` — generic domain set files for Surge and general use
- `geosite/sing-box/*.srs` — sing-box rule-set files

### GeoIP

- `geoip/surge/*.txt` — Surge ruleset files
- `geoip/sing-box/*.srs` — sing-box rule-set files
- `geoip/mihomo/*.mrs` — mihomo rule providers

## Build design

This repository does not reimplement upstream parsers unless necessary.
Instead, it orchestrates the existing upstream projects and republishes the generated artifacts in a cleaner layout.

## Repo structure

- `configs/` — conversion configs
- `scripts/` — orchestration scripts
- `.github/workflows/` — CI release automation
- `upstream/` — optional vendored or cloned upstream tooling

## Notes

- `sing-geosite` already supports exporting plain domain text files and sing-box `.srs`
- `geoip` already supports exporting Surge ruleset, sing-box `.srs`, and mihomo `.mrs`
- This repo should focus on **integration, normalization, packaging, and release**
