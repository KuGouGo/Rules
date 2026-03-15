# Domain Sources

This directory stores hand-maintained domain rule inputs.

## Layout

- `custom/`: custom `*.list` files that are converted into:
  - `.output/domain/surge/*.list`
  - `.output/domain/sing-box/*.srs`
  - `.output/domain/mihomo/*.mrs`

These generated files are local build outputs and are not tracked on `main`.

See `custom/README.md` for the list file format.
