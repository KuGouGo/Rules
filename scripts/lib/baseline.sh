#!/usr/bin/env bash

# Shared publication-baseline helpers. The five publish branches are fetched
# from origin and their commit subjects carry generation/source metadata that
# every stage of the pipeline (scope selection, publishing) must agree on.

PUBLISH_BRANCH_NAMES=(surge quanx egern sing-box mihomo)

publish_git() {
  if [ -n "${PUBLISH_GIT_ROOT:-}" ]; then
    git -C "$PUBLISH_GIT_ROOT" "$@"
  else
    git "$@"
  fi
}

fetch_publish_branch_metadata() {
  local metadata_file="$1"
  local branch commit subject generation source

  : > "$metadata_file"
  # One fetch, one server-side advertisement: the five publish branches are
  # read as an atomic snapshot instead of five sequential round-trips that a
  # concurrent publication could interleave (mixed-generation baseline) and
  # that each add a transient-failure point.
  local -a refspecs=()
  for branch in "${PUBLISH_BRANCH_NAMES[@]}"; do
    refspecs+=("+refs/heads/$branch:refs/remotes/origin/$branch")
  done
  if ! publish_git fetch --quiet --no-tags --depth=1 origin "${refspecs[@]}" 2>/dev/null; then
    # Branches do not exist yet (e.g. first publication after a fresh
    # release). Record placeholders so the baseline is treated as
    # inconsistent. Pushes are atomic, so a missing branch implies all five
    # are missing.
    for branch in "${PUBLISH_BRANCH_NAMES[@]}"; do
      printf '%s\t-\t-\t-\n' "$branch" >> "$metadata_file"
    done
    return 0
  fi
  for branch in "${PUBLISH_BRANCH_NAMES[@]}"; do
    commit="$(publish_git rev-parse --verify "origin/$branch^{commit}")"
    subject="$(publish_git log -1 --format=%s "origin/$branch")"
    if [[ "$subject" =~ ^chore:\ publish\ ${branch}\ artifacts\ \[generation\ ([0-9]+-[0-9]+)\ source\ ([0-9a-f]{40})\]$ ]]; then
      generation="${BASH_REMATCH[1]}"
      source="${BASH_REMATCH[2]}"
    else
      generation="-"
      source="-"
    fi
    printf '%s\t%s\t%s\t%s\n' "$branch" "$commit" "$generation" "$source" >> "$metadata_file"
  done
}

# Validate a user-provided publication baseline JSON and write the canonical
# payload. Prints "status generation source".
validate_and_write_baseline() {
  local input_file="$1"
  local output_file="$2"

  mkdir -p "$(dirname "$output_file")"
  python3 - "$input_file" "$output_file" <<'PY'
import json
import re
import sys
from pathlib import Path

source_path, output_path = map(Path, sys.argv[1:])
branches = {"surge", "quanx", "egern", "sing-box", "mihomo"}
sha_re = re.compile(r"[0-9a-f]{40}")
generation_re = re.compile(r"[0-9]+-[0-9]+")

try:
    payload = json.loads(source_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"publication baseline unreadable: {exc}")

if not isinstance(payload, dict) or set(payload) != {"status", "generation_id", "source_commit", "branches"}:
    raise SystemExit("publication baseline has an invalid top-level schema")
if payload["status"] not in {"consistent", "inconsistent"}:
    raise SystemExit("publication baseline status must be consistent or inconsistent")
if not isinstance(payload["branches"], dict) or set(payload["branches"]) != branches:
    raise SystemExit("publication baseline must record exactly the five publish branches")
for branch, item in payload["branches"].items():
    if not isinstance(item, dict) or set(item) != {"commit", "generation_id", "source_commit"}:
        raise SystemExit(f"publication baseline branch entry is invalid: {branch}")
    if not isinstance(item["commit"], str) or not sha_re.fullmatch(item["commit"]):
        raise SystemExit(f"publication baseline branch commit is invalid: {branch}")
    if item["generation_id"] is not None and (
        not isinstance(item["generation_id"], str) or not generation_re.fullmatch(item["generation_id"])
    ):
        raise SystemExit(f"publication baseline branch generation is invalid: {branch}")
    if item["source_commit"] is not None and (
        not isinstance(item["source_commit"], str) or not sha_re.fullmatch(item["source_commit"])
    ):
        raise SystemExit(f"publication baseline branch source is invalid: {branch}")

if payload["status"] == "consistent":
    if not isinstance(payload["generation_id"], str) or not generation_re.fullmatch(payload["generation_id"]):
        raise SystemExit("consistent publication baseline generation_id is invalid")
    if not isinstance(payload["source_commit"], str) or not sha_re.fullmatch(payload["source_commit"]):
        raise SystemExit("consistent publication baseline source_commit is invalid")
    identities = {(item["generation_id"], item["source_commit"]) for item in payload["branches"].values()}
    if identities != {(payload["generation_id"], payload["source_commit"])}:
        raise SystemExit("consistent publication baseline branch identities disagree")
elif payload["generation_id"] is not None or payload["source_commit"] is not None:
    raise SystemExit("inconsistent publication baseline must use null cohort identity")

output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(payload["status"], payload["generation_id"] or "-", payload["source_commit"] or "-")
PY
}

# Build the baseline JSON from fetched metadata. Prints "status generation
# source" and, when an output file is given, writes the JSON payload there.
build_baseline_json() {
  local metadata_file="$1"
  local output_file="${2:-}"

  python3 - "$metadata_file" "$output_file" <<'PY'
import json
import sys
from pathlib import Path

metadata_file, output_file = sys.argv[1:]
rows = [
    line.split("\t")
    for line in Path(metadata_file).read_text(encoding="utf-8").splitlines()
    if line
]
if len(rows) != 5:
    raise SystemExit(f"publication baseline incomplete: expected 5 branches, got {len(rows)}")
valid_identities = {(row[2], row[3]) for row in rows if row[2] != "-" and row[3] != "-"}
consistent = len(valid_identities) == 1 and all(row[2] != "-" and row[3] != "-" for row in rows)
generation, source = next(iter(valid_identities)) if consistent else (None, None)
payload = {
    "status": "consistent" if consistent else "inconsistent",
    "generation_id": generation,
    "source_commit": source,
    "branches": {
        row[0]: {
            "commit": None if row[1] == "-" else row[1],
            "generation_id": None if row[2] == "-" else row[2],
            "source_commit": None if row[3] == "-" else row[3],
        }
        for row in rows
    },
}
if output_file:
    Path(output_file).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
print(payload["status"], payload["generation_id"] or "-", payload["source_commit"] or "-")
PY
}

# Rewrite a baseline file so the top-level cohort is "inconsistent" while the
# per-branch records are preserved. Used when the recorded source commit is
# unavailable or no longer an ancestor of the candidate (e.g. after a history
# rewrite), so later pipeline stages agree on the degraded cohort instead of
# reading a stale "consistent" status.
degrade_baseline_file() {
  local baseline_file="$1"
  python3 - "$baseline_file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["status"] = "inconsistent"
payload["generation_id"] = None
payload["source_commit"] = None
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

# Refuse publication when the remote cohort no longer matches the manifest
# baseline recorded by the build that produced the artifacts. A manifest
# anchored to an inconsistent baseline (e.g. after a history rewrite) has no
# cohort to compare against and is expected to establish a fresh one.
assert_remote_baseline_matches_manifest() {
  local metadata_file="$1"
  local manifest_file="$2"
  local remote_file
  remote_file="$(mktemp)"

  if ! build_baseline_json "$metadata_file" "$remote_file" >/dev/null \
    || ! python3 - "$manifest_file" "$remote_file" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
remote = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if manifest["baseline"]["status"] == "consistent" and remote != manifest["baseline"]:
    raise SystemExit(
        "publication baseline is stale: the remote cohort changed after this build started"
    )
PY
  then
    rm -f "$remote_file"
    return 1
  fi
  rm -f "$remote_file"
}
