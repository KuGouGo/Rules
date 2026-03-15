# Custom Domain Rules

This directory stores custom domain rule source files.

Each `*.list` file is built into:

- `domain/surge/<name>.list`
- `domain/sing-box/<name>.srs`
- `domain/mihomo/<name>.mrs`

## Format

Supported rule types:

- `DOMAIN,example.com`
- `DOMAIN-SUFFIX,example.com`

Additional rules:

- empty lines are allowed
- lines starting with `#` are treated as comments
- domains must not start with `.`
- filenames may only contain lowercase letters, digits, and hyphens
- avoid names that conflict with tracked public rules, or CI will fail
