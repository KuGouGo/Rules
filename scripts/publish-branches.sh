#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN="${PUBLISH_DRY_RUN:-0}"

branch_readme() {
  local branch="$1"
  case "$branch" in
    surge)
      cat <<'EOF'
# Rules / Surge

Generated artifacts for Surge.
This branch intentionally contains only the final Surge rule files and this README.

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
This branch intentionally contains only the final sing-box rule files and this README.

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
This branch intentionally contains only the final mihomo rule files and this README.

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

copy_artifacts() {
  local src_dir="$1"
  local dest_dir="$2"
  local extension="$3"
  local file copied=0

  mkdir -p "$dest_dir"
  shopt -s nullglob
  for file in "$ROOT/$src_dir"/*."$extension"; do
    cp "$file" "$dest_dir/"
    copied=1
  done
  shopt -u nullglob

  if [ "$copied" -eq 0 ]; then
    echo "no .$extension artifacts found in $src_dir" >&2
    exit 1
  fi
}

assert_branch_layout() {
  local expected_ext="$1"
  local file rel

  for rel in README.md; do
    [ -f "$rel" ] || {
      echo "missing publish file: $rel" >&2
      exit 1
    }
  done

  while IFS= read -r -d '' file; do
    rel="${file#./}"
    case "$rel" in
      domain/*."$expected_ext"|ip/*."$expected_ext") ;;
      *)
        echo "unexpected file in publish tree: $rel" >&2
        exit 1
        ;;
    esac
  done < <(find domain ip -type f -print0)
}

publish_branch() {
  local branch="$1"
  local domain_dir="$2"
  local ip_dir="$3"
  local extension="$4"
  local tmpdir

  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null

  git init -q
  git checkout --orphan "$branch" >/dev/null 2>&1
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

  copy_artifacts "$domain_dir" domain "$extension"
  copy_artifacts "$ip_dir" ip "$extension"
  branch_readme "$branch" > README.md
  assert_branch_layout "$extension"

  git add README.md domain ip
  git commit -m "chore: publish ${branch} artifacts" >/dev/null

  if [ "$DRY_RUN" = "1" ]; then
    echo "=== ${branch} publish dry-run ==="
    echo "domain files: $(find domain -maxdepth 1 -type f | wc -l | tr -d ' ')"
    echo "ip files: $(find ip -maxdepth 1 -type f | wc -l | tr -d ' ')"
    popd >/dev/null
    rm -rf "$tmpdir"
    return 0
  fi

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

publish_branch surge domain/surge ip/surge list
publish_branch sing-box domain/sing-box ip/sing-box srs
publish_branch mihomo domain/mihomo ip/mihomo mrs
