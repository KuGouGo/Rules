# Domain Sources

This directory stores hand-maintained domain rule inputs.

## Layout

- `custom/`: custom `*.list` files that are converted into:
  - `domain/surge/*.list`
  - `domain/sing-box/*.srs`
  - `domain/mihomo/*.mrs`

These generated files are local build outputs and are not tracked on `main`.

See `custom/README.md` for the list file format.
