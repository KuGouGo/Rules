# Custom Domain Rules

This directory stores custom domain rule source files.

Each `*.list` file is built into:

- `.output/domain/surge/<name>.list`
- `.output/domain/sing-box/<name>.srs`
- `.output/domain/mihomo/<name>.mrs`

These build outputs are local artifacts and are not tracked on the `main` branch.

## Format

Supported rule types:

- `DOMAIN,example.com`
- `DOMAIN-SUFFIX,example.com`

Additional rules:

- empty lines are allowed
- lines starting with `#` are treated as comments
- domains must not start with `.`
- filenames may only contain lowercase letters, digits, and hyphens
- avoid names that conflict with generated public rules, or CI will fail
