#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN="${PUBLISH_DRY_RUN:-0}"
ALLOW_REMOTE_FALLBACK="${PUBLISH_ALLOW_REMOTE_FALLBACK:-0}"
ARTIFACT_ROOT="$ROOT/.output"

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
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/domain/cn.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/KuGouGo/Rules/surge/ip/cn.list,DIRECT
```
EOF
      ;;
    quanx)
      cat <<'EOF'
# Rules / QuanX

Generated artifacts for Quantumult X.
This branch intentionally contains only the final QuanX rule files and this README.

## Contents

- [domain/](./domain/)
- [ip/](./ip/)

QuanX plain-text rule files in this branch use the `.list` extension.
Rules are emitted with QuanX types (`HOST`, `HOST-SUFFIX`, `HOST-KEYWORD`, `IP-CIDR`, `IP6-CIDR`) and an explicit policy tag in field 3.
Using `force-policy` in `filter_remote` is recommended.

## Example

```ini
[filter_remote]
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/domain/cn.list, tag=CN-DOMAIN, force-policy=direct, enabled=true
https://raw.githubusercontent.com/KuGouGo/Rules/quanx/ip/cn.list, tag=CN-IP, force-policy=direct, enabled=true
```
EOF
      ;;
    egern)
      cat <<'EOF'
# Rules / Egern

Generated artifacts for Egern.
This branch intentionally contains only the final Egern rule files and this README.

## Contents

- [domain/](./domain/)
- [ip/](./ip/)

Egern rule files in this branch use the `.yaml` extension.
Domain files may contain `domain_set`, `domain_suffix_set`, `domain_keyword_set`, `domain_regex_set`.
IP files use `ip_cidr_set`.

## URLs

- Domain example: `https://raw.githubusercontent.com/KuGouGo/Rules/egern/domain/cn.yaml`
- IP example: `https://raw.githubusercontent.com/KuGouGo/Rules/egern/ip/cn.yaml`
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

Domain rules use binary `.mrs` files.
IP rules use binary `.mrs` files.

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

has_publish_source_artifacts() {
  local src_dir="$1"
  local extensions_csv="$2"
  local -a extensions=()
  local extension

  IFS=',' read -r -a extensions <<< "$extensions_csv"
  for extension in "${extensions[@]}"; do
    if find "$ARTIFACT_ROOT/$src_dir" -maxdepth 1 -type f -name "*.${extension}" -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done

  return 1
}

copy_artifacts() {
  local src_dir="$1"
  local dest_dir="$2"
  local extensions_csv="$3"
  local -a extensions=()
  local extension file copied=0

  IFS=',' read -r -a extensions <<< "$extensions_csv"

  mkdir -p "$dest_dir"
  shopt -s nullglob
  for extension in "${extensions[@]}"; do
    for file in "$ARTIFACT_ROOT/$src_dir"/*."$extension"; do
      cp "$file" "$dest_dir/"
      copied=1
    done
  done
  shopt -u nullglob

  if [ "$copied" -eq 0 ]; then
    echo "no supported artifacts found in $src_dir ($extensions_csv)" >&2
    exit 1
  fi
}

restore_remote_publish_side() {
  local branch="$1"
  local side="$2"
  local extensions_csv="$3"
  local dest_dir="$4"
  local tree_path="$side"
  local -a extensions=()
  local extension restored=0
  local file_path rel_name

  IFS=',' read -r -a extensions <<< "$extensions_csv"
  mkdir -p "$dest_dir"

  if ! git -C "$ROOT" rev-parse --verify "origin/$branch^{commit}" >/dev/null 2>&1; then
    return 1
  fi

  while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    rel_name="${file_path#"${tree_path}"/}"
    mkdir -p "$dest_dir/$(dirname "$rel_name")"
    git -C "$ROOT" show "origin/$branch:$file_path" > "$dest_dir/$rel_name"
    restored=1
  done < <(
    for extension in "${extensions[@]}"; do
      git -C "$ROOT" ls-tree -r --name-only "origin/$branch" -- "$tree_path" 2>/dev/null | grep -E "\\.${extension}$" || true
    done
  )

  [ "$restored" -eq 1 ]
}

prepare_publish_side() {
  local branch="$1"
  local src_dir="$2"
  local side="$3"
  local extensions_csv="$4"
  local dest_dir="$5"

  if has_publish_source_artifacts "$src_dir" "$extensions_csv"; then
    copy_artifacts "$src_dir" "$dest_dir" "$extensions_csv"
    return 0
  fi

  echo "publish source missing local artifacts for $src_dir; attempting fallback from origin/$branch:$side" >&2
  if restore_remote_publish_side "$branch" "$side" "$extensions_csv" "$dest_dir"; then
    echo "restored $side artifacts from origin/$branch baseline" >&2
    return 0
  fi

  echo "publish source missing artifacts: $ARTIFACT_ROOT/$src_dir (expected: $extensions_csv)" >&2
  echo "hint: run the build pipeline first to populate .output before publishing" >&2
  echo "hint: or ensure origin/$branch contains baseline $side artifacts for fallback restore" >&2
  exit 1
}

has_allowed_extension() {
  local file="$1"
  local extensions_csv="$2"
  local -a extensions=()
  local extension

  IFS=',' read -r -a extensions <<< "$extensions_csv"
  for extension in "${extensions[@]}"; do
    [[ "$file" == *."$extension" ]] && return 0
  done

  return 1
}

assert_branch_layout() {
  local domain_extensions="$1"
  local ip_extensions="$2"
  local file rel

  [ -f "README.md" ] || {
    echo "missing publish file: README.md" >&2
    exit 1
  }

  while IFS= read -r -d '' file; do
    rel="${file#./}"
    if [[ "$rel" == domain/* ]]; then
      has_allowed_extension "$rel" "$domain_extensions" || {
        echo "unexpected file in publish tree: $rel" >&2
        exit 1
      }
      continue
    fi
    if [[ "$rel" == ip/* ]]; then
      has_allowed_extension "$rel" "$ip_extensions" || {
        echo "unexpected file in publish tree: $rel" >&2
        exit 1
      }
      continue
    fi
    echo "unexpected file in publish tree: $rel" >&2
    exit 1
  done < <(find domain ip -type f -print0)
}

cleanup_tempdir() {
  local tempdir="$1"
  popd >/dev/null || true
  rm -rf "$tempdir"
}

publish_branch() {
  local branch="$1"
  local domain_dir="$2"
  local ip_dir="$3"
  local domain_extensions="$4"
  local ip_extensions="$5"
  local tmpdir local_tree remote_tree

  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  trap 'cleanup_tempdir "$tmpdir"' RETURN

  git init -q
  git checkout --orphan "$branch" >/dev/null 2>&1
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

  prepare_publish_side "$branch" "$domain_dir" domain "$domain_extensions" domain
  prepare_publish_side "$branch" "$ip_dir" ip "$ip_extensions" ip
  branch_readme "$branch" > README.md
  assert_branch_layout "$domain_extensions" "$ip_extensions"

  git add README.md domain ip
  local_tree="$(git write-tree)"
  remote_tree="$(git -C "$ROOT" rev-parse "origin/$branch^{tree}" 2>/dev/null || true)"

  if [ -n "$remote_tree" ] && [ "$local_tree" = "$remote_tree" ]; then
    echo "$branch artifacts unchanged, skip publish"
    return 0
  fi

  git commit -m "chore: publish ${branch} artifacts" >/dev/null

  local remote_url
  if [ "$DRY_RUN" = "1" ]; then
    echo "=== ${branch} publish dry-run ==="
    echo "domain files: $(find domain -maxdepth 1 -type f | wc -l | tr -d ' ')"
    echo "ip files: $(find ip -maxdepth 1 -type f | wc -l | tr -d ' ')"
    return 0
  fi

  remote_url="$(git -C "$ROOT" remote get-url origin)"
  if [[ "$remote_url" == https://github.com/* ]] && [ -n "${GITHUB_TOKEN:-}" ]; then
    remote_url="https://x-access-token:${GITHUB_TOKEN}@${remote_url#https://}"
  fi
  git remote add origin "$remote_url"

  local_tree="$(git rev-parse 'HEAD^{tree}')"
  if git fetch --depth=1 origin "$branch" >/dev/null 2>&1; then
    remote_tree="$(git rev-parse 'FETCH_HEAD^{tree}')"
    if [ "$local_tree" = "$remote_tree" ]; then
      echo "${branch} artifacts unchanged, skip push"
      return 0
    fi
  fi

  git push -f origin HEAD:"$branch"
}

publish_branch surge domain/surge ip/surge list list
publish_branch quanx domain/quanx ip/quanx list list
publish_branch egern domain/egern ip/egern yaml yaml
publish_branch sing-box domain/sing-box ip/sing-box srs srs
publish_branch mihomo domain/mihomo ip/mihomo mrs mrs
