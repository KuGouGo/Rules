#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TEXT_ONLY_MODE="${RULES_BUILD_CUSTOM_TEXT_ONLY:-0}"

# Reject malformed or globally conflicting custom sources before creating build
# directories, inspecting staged artifacts, or downloading build tools.
"$ROOT/scripts/commands/lint-custom-rules.sh"

CUSTOM_DOMAIN_DIR="$ROOT/sources/custom/domain"
CUSTOM_IP_DIR="$ROOT/sources/custom/ip"
TMP_PARENT_DIR="$ROOT/.tmp"
mkdir -p "$TMP_PARENT_DIR"
TMP_DIR="$(mktemp -d "$TMP_PARENT_DIR/custom.XXXXXX")"
TMP_DOMAIN_DIR="$TMP_DIR/domain"
TMP_IP_DIR="$TMP_DIR/ip"
STAGE_ROOT="$TMP_DIR/output"
BIN_DIR="$ROOT/.bin"
ARTIFACT_ROOT="${RULES_ARTIFACT_ROOT:-$ROOT/.output}"
DOMAIN_SURGE_DIR="$STAGE_ROOT/domain/surge"
DOMAIN_QUANX_DIR="$STAGE_ROOT/domain/quanx"
DOMAIN_EGERN_DIR="$STAGE_ROOT/domain/egern"
DOMAIN_SINGBOX_DIR="$STAGE_ROOT/domain/sing-box"
DOMAIN_MIHOMO_DIR="$STAGE_ROOT/domain/mihomo"
IP_SURGE_DIR="$STAGE_ROOT/ip/surge"
IP_QUANX_DIR="$STAGE_ROOT/ip/quanx"
IP_EGERN_DIR="$STAGE_ROOT/ip/egern"
IP_SINGBOX_DIR="$STAGE_ROOT/ip/sing-box"
IP_MIHOMO_DIR="$STAGE_ROOT/ip/mihomo"

# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=scripts/lib/rules.sh
source "$ROOT/scripts/lib/rules.sh"
setup_tool_cache

DOMAIN_RULE_FILES="$(list_rule_files "$CUSTOM_DOMAIN_DIR")"
IP_RULE_FILES="$(list_rule_files "$CUSTOM_IP_DIR")"

mkdir -p \
  "$DOMAIN_SURGE_DIR" \
  "$DOMAIN_QUANX_DIR" \
  "$DOMAIN_EGERN_DIR" \
  "$DOMAIN_SINGBOX_DIR" \
  "$DOMAIN_MIHOMO_DIR" \
  "$IP_SURGE_DIR" \
  "$IP_QUANX_DIR" \
  "$IP_EGERN_DIR" \
  "$IP_SINGBOX_DIR" \
  "$IP_MIHOMO_DIR" \
  "$BIN_DIR"
mkdir -p "$TMP_DOMAIN_DIR" "$TMP_IP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

has_custom_domain=0
has_custom_ip=0
MIHOMO_READY=0
if [ -n "$DOMAIN_RULE_FILES" ]; then
  has_custom_domain=1
fi
if [ -n "$IP_RULE_FILES" ]; then
  has_custom_ip=1
fi

if [ "$has_custom_domain" -eq 0 ] && [ "$has_custom_ip" -eq 0 ]; then
  echo "no custom rule lists found, skip"
  exit 0
fi

ensure_mihomo_once() {
  if [ "$MIHOMO_READY" -eq 0 ]; then
    ensure_mihomo
    MIHOMO_READY=1
  fi
}

resolve_conflict_base_ref() {
  if [ -n "${RULES_CONFLICT_BASE_SHA:-}" ] \
    && git rev-parse --verify "${RULES_CONFLICT_BASE_SHA}^{commit}" >/dev/null 2>&1; then
    printf '%s' "$RULES_CONFLICT_BASE_SHA"
    return 0
  fi

  if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    printf 'HEAD^'
  fi
}

collect_base_custom_sources() {
  local base_ref="$1"

  if [ -z "$base_ref" ]; then
    return 0
  fi

  git ls-tree -r --name-only "$base_ref" -- sources/custom 2>/dev/null || true
}

custom_source_existed_in_base() {
  local rel_path="$1"
  local base_custom_sources="$2"

  printf '%s\n' "$base_custom_sources" | grep -Fxq "$rel_path"
}

collect_generated_custom_artifacts() {
  python3 "$ROOT/scripts/tools/artifact_origins.py" list \
    "$ARTIFACT_ROOT" \
    --origin generated-custom
}

artifact_was_generated_custom() {
  local relative_path="$1"

  printf '%s\n' "$GENERATED_CUSTOM_ARTIFACTS" | grep -Fxq "$relative_path"
}

historical_fakeip_migration_collision() {
  local base_ref="$1"
  local custom_rel_path="$2"
  local tracked_path="$3"

  # This exception is available only while migrating a base commit that
  # actually tracked the old binary but did not yet track the maintained source.
  # Once the source exists in the base, the normal existing-source path applies.
  [ -n "$base_ref" ] \
    && [ "$custom_rel_path" = "sources/custom/domain/fakeip-filter.list" ] \
    && [ "$tracked_path" = ".output/domain/mihomo/fakeip-filter.mrs" ] \
    && git cat-file -e "$base_ref:$tracked_path" 2>/dev/null
}

assert_no_name_conflict() {
  local base="$1"
  local custom_rel_path="$2"
  local custom_dir="$3"
  local base_ref="$4"
  local base_custom_sources="$5"
  shift 5
  local conflicts=()
  local tracked_path

  if custom_source_existed_in_base "$custom_rel_path" "$base_custom_sources"; then
    return 0
  fi

  for tracked_path in "$@"; do
    if historical_fakeip_migration_collision "$base_ref" "$custom_rel_path" "$tracked_path"; then
      continue
    fi
    if [ -e "$ARTIFACT_ROOT/${tracked_path#.output/}" ] \
      && ! artifact_was_generated_custom "${tracked_path#.output/}"; then
      conflicts+=("$tracked_path")
    fi
  done

  if [ ${#conflicts[@]} -gt 0 ]; then
    echo "custom rule name conflict detected for base '$base'" >&2
    printf 'conflicting generated files:\n' >&2
    printf '  - %s\n' "${conflicts[@]}" >&2
    echo "rename $custom_dir/$base.list to a unique name and retry" >&2
    return 1
  fi
}

GENERATED_CUSTOM_ARTIFACTS="$(collect_generated_custom_artifacts)"

build_domain_plain_and_surge() {
  local list_file="$1"
  local base surge_out quanx_out egern_out plain_out surge_tmp quanx_tmp egern_tmp
  base="$(basename "$list_file" .list)"
  surge_out="$DOMAIN_SURGE_DIR/$base.list"
  quanx_out="$DOMAIN_QUANX_DIR/$base.list"
  egern_out="$DOMAIN_EGERN_DIR/$base.yaml"
  plain_out="$TMP_DOMAIN_DIR/$base.list"
  surge_tmp="$TMP_DOMAIN_DIR/$base.surge.tmp"
  quanx_tmp="$TMP_DOMAIN_DIR/$base.quanx.tmp"
  egern_tmp="$TMP_DOMAIN_DIR/$base.egern.tmp"

  normalize_custom_domain_source "$list_file" "$plain_out"
  render_surge_domain_ruleset_from_rules "$plain_out" "$surge_tmp"
  render_quanx_domain_ruleset_from_rules "$plain_out" "$quanx_tmp" "$base"
  render_egern_domain_ruleset_from_rules "$plain_out" "$egern_tmp"
  write_if_nonempty_or_remove "$surge_tmp" "$surge_out"
  write_if_nonempty_or_remove "$quanx_tmp" "$quanx_out"
  write_if_nonempty_or_remove "$egern_tmp" "$egern_out"
}

build_domain_binaries() {
  local plain_list="$1"
  local base json srs_tmp mihomo_text_tmp mihomo_mrs_tmp
  base="$(basename "$plain_list" .list)"
  json="$TMP_DOMAIN_DIR/$base.json"
  srs_tmp="$TMP_DOMAIN_DIR/$base.srs.tmp"
  compile_domain_rule_list_to_artifacts "$plain_list" "$json" "$srs_tmp" || {
    echo "failed to build custom domain binary rules for $base" >&2
    return 1
  }
  write_if_changed "$srs_tmp" "$DOMAIN_SINGBOX_DIR/$base.srs"

  mihomo_text_tmp="$TMP_DOMAIN_DIR/$base.mihomo.txt"
  build_mihomo_domain_text_from_rules "$plain_list" "$mihomo_text_tmp"

  if [ ! -s "$mihomo_text_tmp" ]; then
    echo "custom domain list $base has no DOMAIN/DOMAIN-SUFFIX entries; skip mihomo mrs" >&2
    rm -f "$DOMAIN_MIHOMO_DIR/$base.list" "$DOMAIN_MIHOMO_DIR/$base.mrs"
    return 0
  fi

  ensure_mihomo_once
  mihomo_mrs_tmp="$TMP_DOMAIN_DIR/$base.mrs.tmp"
  compile_mihomo_domain_plain_to_binary_artifact "$mihomo_text_tmp" "$mihomo_mrs_tmp" || {
    echo "failed to build custom mihomo domain rules for $base" >&2
    return 1
  }
  rm -f "$DOMAIN_MIHOMO_DIR/$base.list"
  write_if_changed "$mihomo_mrs_tmp" "$DOMAIN_MIHOMO_DIR/$base.mrs"
}

build_ip_plain_and_surge() {
  local list_file="$1"
  local base surge_out quanx_out egern_out plain_out surge_tmp quanx_tmp egern_tmp plain_tmp
  base="$(basename "$list_file" .list)"
  surge_out="$IP_SURGE_DIR/$base.list"
  quanx_out="$IP_QUANX_DIR/$base.list"
  egern_out="$IP_EGERN_DIR/$base.yaml"
  plain_out="$TMP_IP_DIR/$base.txt"
  surge_tmp="$TMP_IP_DIR/$base.surge.tmp"
  quanx_tmp="$TMP_IP_DIR/$base.quanx.tmp"
  egern_tmp="$TMP_IP_DIR/$base.egern.tmp"
  plain_tmp="$TMP_IP_DIR/$base.plain.tmp"

  normalize_ip_rule_source "$list_file" "$surge_tmp" "$plain_tmp"
  render_ip_plain_to_quanx_list "$plain_tmp" "$quanx_tmp" "$base"
  render_ip_plain_to_egern_yaml "$plain_tmp" "$egern_tmp"
  write_if_nonempty_or_remove "$surge_tmp" "$surge_out"
  write_if_nonempty_or_remove "$quanx_tmp" "$quanx_out"
  write_if_nonempty_or_remove "$egern_tmp" "$egern_out"
  mv "$plain_tmp" "$plain_out"
  rm -f "$surge_tmp" "$quanx_tmp" "$egern_tmp"
}

build_ip_binaries() {
  local plain_list="$1"
  local base json srs_tmp mrs_tmp
  base="$(basename "$plain_list" .txt)"
  json="$TMP_IP_DIR/$base.json"
  srs_tmp="$TMP_IP_DIR/$base.srs.tmp"
  mrs_tmp="$TMP_IP_DIR/$base.mrs.tmp"
  compile_ip_plain_to_binary_artifacts "$plain_list" "$json" "$srs_tmp" "$mrs_tmp" || {
    echo "failed to build custom IP binary rules for $base" >&2
    return 1
  }
  write_if_changed "$srs_tmp" "$IP_SINGBOX_DIR/$base.srs"
  write_if_changed "$mrs_tmp" "$IP_MIHOMO_DIR/$base.mrs"
}

CONFLICT_BASE_REF="$(resolve_conflict_base_ref)"
BASE_CUSTOM_SOURCES="$(collect_base_custom_sources "$CONFLICT_BASE_REF")"

while IFS= read -r list_file; do
  [ -n "$list_file" ] || continue
  base="$(basename "$list_file" .list)"
  assert_no_name_conflict \
    "$base" \
    "sources/custom/domain/$base.list" \
    "$CUSTOM_DOMAIN_DIR" \
    "$CONFLICT_BASE_REF" \
    "$BASE_CUSTOM_SOURCES" \
    ".output/domain/surge/$base.list" \
    ".output/domain/quanx/$base.list" \
    ".output/domain/egern/$base.yaml" \
    ".output/domain/sing-box/$base.srs" \
    ".output/domain/mihomo/$base.mrs"
  build_domain_plain_and_surge "$list_file"
done <<< "$DOMAIN_RULE_FILES"

while IFS= read -r list_file; do
  [ -n "$list_file" ] || continue
  base="$(basename "$list_file" .list)"
  assert_no_name_conflict \
    "$base" \
    "sources/custom/ip/$base.list" \
    "$CUSTOM_IP_DIR" \
    "$CONFLICT_BASE_REF" \
    "$BASE_CUSTOM_SOURCES" \
    ".output/ip/surge/$base.list" \
    ".output/ip/quanx/$base.list" \
    ".output/ip/egern/$base.yaml" \
    ".output/ip/sing-box/$base.srs" \
    ".output/ip/mihomo/$base.mrs"
  build_ip_plain_and_surge "$list_file"
done <<< "$IP_RULE_FILES"

inject_custom_build_failure() {
  local point="$1"

  if [ "${RULES_BUILD_CUSTOM_FAIL_AT:-}" = "$point" ]; then
    echo "injected custom build failure at $point" >&2
    return 1
  fi
}

# This point is deliberately after the final text render and before any binary
# setup or compile. Tests use it to prove staged text cannot leak into .output.
inject_custom_build_failure late-text

if [ "$TEXT_ONLY_MODE" -ne 1 ] && { [ "$has_custom_domain" -gt 0 ] || [ "$has_custom_ip" -gt 0 ]; }; then
  ensure_sing_box
fi

if [ "$TEXT_ONLY_MODE" -ne 1 ] && [ "$has_custom_ip" -gt 0 ]; then
  ensure_mihomo_once
fi

if [ "$TEXT_ONLY_MODE" -ne 1 ]; then
  for plain_list in "$TMP_DOMAIN_DIR"/*.list; do
    [ -f "$plain_list" ] || continue
    build_domain_binaries "$plain_list"
  done

  for plain_list in "$TMP_IP_DIR"/*.txt; do
    [ -f "$plain_list" ] || continue
    build_ip_binaries "$plain_list"
  done
fi

commit_staged_custom_artifacts() {
  local list_file base relative staged target target_dir
  local controlled=()

  while IFS= read -r list_file; do
    [ -n "$list_file" ] || continue
    base="$(basename "$list_file" .list)"
    controlled+=(
      "domain/surge/$base.list"
      "domain/quanx/$base.list"
      "domain/egern/$base.yaml"
    )
    if [ "$TEXT_ONLY_MODE" -ne 1 ]; then
      controlled+=(
        "domain/sing-box/$base.srs"
        "domain/mihomo/$base.list"
        "domain/mihomo/$base.mrs"
      )
    fi
  done <<< "$DOMAIN_RULE_FILES"

  while IFS= read -r list_file; do
    [ -n "$list_file" ] || continue
    base="$(basename "$list_file" .list)"
    controlled+=(
      "ip/surge/$base.list"
      "ip/quanx/$base.list"
      "ip/egern/$base.yaml"
    )
    if [ "$TEXT_ONLY_MODE" -ne 1 ]; then
      controlled+=(
        "ip/sing-box/$base.srs"
        "ip/mihomo/$base.mrs"
      )
    fi
  done <<< "$IP_RULE_FILES"

  # Only the paths derived from current custom sources are controlled here.
  # Restored/upstream artifacts and summaries elsewhere in .output are untouched.
  for relative in "${controlled[@]}"; do
    staged="$STAGE_ROOT/$relative"
    target="$ARTIFACT_ROOT/$relative"
    target_dir="$(dirname "$target")"
    mkdir -p "$target_dir"
    if [ -f "$staged" ]; then
      write_if_changed "$staged" "$target"
    else
      # A platform-specific skip is committed as deletion only after every
      # render and binary compile has succeeded.
      rm -f "$target"
    fi
  done
}

if [ "$TEXT_ONLY_MODE" -ne 1 ]; then
  # This point is after the last binary compile but before the controlled commit.
  inject_custom_build_failure late-binary
fi
commit_staged_custom_artifacts
origin_args=(mark-custom "$ARTIFACT_ROOT" "$CUSTOM_DOMAIN_DIR" "$CUSTOM_IP_DIR")
if [ "$TEXT_ONLY_MODE" -eq 1 ]; then
  origin_args+=(--text-only)
fi
python3 "$ROOT/scripts/tools/artifact_origins.py" "${origin_args[@]}"

if [ "$TEXT_ONLY_MODE" -eq 1 ]; then
  echo "custom build done (text only)"
else
  echo "custom build done"
fi
