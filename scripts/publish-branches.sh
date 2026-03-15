#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

git config --global user.name "github-actions[bot]"
git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"

branch_readme() {
  local branch="$1"
  case "$branch" in
    surge)
      cat <<'EOF'
# Rules / Surge

Generated artifacts for Surge.

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
EOF
      ;;
    sing-box)
      cat <<'EOF'
# Rules / sing-box

Generated artifacts for sing-box.

## Contents

- [domain/](./domain/)
- [ip/](./ip/)

## Example

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
EOF
      ;;
    mihomo)
      cat <<'EOF'
# Rules / mihomo

Generated artifacts for mihomo.

## Contents

- [domain/](./domain/)
- [ip/](./ip/)

## Example

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
EOF
      ;;
  esac
}

publish_branch() {
  local branch="$1"
  local domain_dir="$2"
  local ip_dir="$3"
  local tmpdir

  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null

  git init -q
  git checkout --orphan "$branch" >/dev/null 2>&1

  mkdir -p domain ip
  cp -R "$ROOT/$domain_dir"/. domain/
  cp -R "$ROOT/$ip_dir"/. ip/
  branch_readme "$branch" > README.md

  git add README.md domain ip
  git commit -m "chore: publish ${branch} artifacts" >/dev/null
  local remote_url
  remote_url="$(git -C "$ROOT" remote get-url origin)"
  if [[ "$remote_url" == https://github.com/* ]] && [ -n "${GITHUB_TOKEN:-}" ]; then
    remote_url="https://x-access-token:${GITHUB_TOKEN}@${remote_url#https://}"
  fi

  git remote add origin "$remote_url"
  git push -f origin HEAD:"$branch"

  popd >/dev/null
  rm -rf "$tmpdir"
}

publish_branch surge domain/surge ip/surge
publish_branch sing-box domain/sing-box ip/sing-box
publish_branch mihomo domain/mihomo ip/mihomo
