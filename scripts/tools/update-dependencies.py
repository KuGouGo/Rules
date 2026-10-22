#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

COMPILERS = {
    "SING_BOX_VERSION": "SagerNet/sing-box",
    "MIHOMO_VERSION": "MetaCubeX/mihomo",
}

ACTION_FILES = sorted(
    [*ROOT.glob(".github/workflows/*.yml"), *ROOT.glob(".github/workflows/*.yaml"),
     *ROOT.glob(".github/actions/**/action.yml"), *ROOT.glob(".github/actions/**/action.yaml")]
)

TRACKED_ACTIONS = {
    "actions/checkout": 7,
    "actions/setup-python": 7,
    "actions/cache": 6,
    "actions/upload-artifact": 7,
    "actions/download-artifact": 8,
}

def _github_api_request(url: str) -> urllib.request.Request:
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    return request

def latest_release(repo: str) -> str:
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    with urllib.request.urlopen(_github_api_request(url), timeout=30) as response:
        tag = json.load(response)["tag_name"]
    return tag.removeprefix("v")

def latest_tag_in_major(repo: str, major: int) -> tuple[str, str]:
    output = subprocess.run(
        ["git", "ls-remote", "--tags", f"https://github.com/{repo}"],
        capture_output=True, text=True, check=True,
    ).stdout
    versions = []
    for line in output.splitlines():
        sha, ref = line.split("\t")
        tag = ref.removeprefix("refs/tags/")
        if re.fullmatch(rf"v{major}\.\d+\.\d+", tag):
            versions.append((tag, sha))
    if not versions:
        raise RuntimeError(f"{repo} has no v{major}.*.* tags")
    return max(versions, key=lambda item: [int(x) for x in item[0][1:].split(".")])

def update_compilers(resolved: dict[str, str] | None = None) -> list[str]:
    path = ROOT / "scripts/lib/common.sh"
    src = path.read_text(encoding="utf-8")
    # Resolve every compiler before rewriting so one failed lookup cannot
    # leave the other compiler pin already bumped.
    if resolved is None:
        resolved = {repo: latest_release(repo) for repo in COMPILERS.values()}
    changed = []
    for var, repo in COMPILERS.items():
        latest = resolved[repo]
        match = re.search(rf'^{var}="([0-9.]+)"$', src, re.M)
        if not match:
            raise RuntimeError(f"{path} 中未找到 {var}")
        current = match.group(1)
        if current != latest:
            src = src.replace(f'{var}="{current}"', f'{var}="{latest}"', 1)
            changed.append(f"compiler {repo.split('/')[1]} {current} -> {latest}")
    if changed:
        path.write_text(src, encoding="utf-8")
    return changed

def _replace_action_pin(src: str, repo: str, tag: str, sha: str) -> tuple[str, bool]:
    pattern = re.compile(rf"uses: {re.escape(repo)}@([0-9a-f]{{40}})( # v[0-9.]+)?")
    changed = False

    def replace(match: re.Match[str]) -> str:
        nonlocal changed
        current_sha, current_note = match.group(1), match.group(2) or ""
        if current_sha == sha and current_note == f" # {tag}":
            return match.group(0)
        changed = True
        return f"uses: {repo}@{sha} # {tag}"

    return pattern.sub(replace, src), changed

def update_actions(resolved: dict[str, tuple[str, str]] | None = None) -> list[str]:
    # Resolve every pin before writing. A lookup failure must not leave a
    # partial compiler or action bump on disk.
    if resolved is None:
        resolved = {
            repo: latest_tag_in_major(repo, major) for repo, major in TRACKED_ACTIONS.items()
        }
    planned: list[tuple[Path, str, list[str]]] = []
    for path in ACTION_FILES:
        src = path.read_text(encoding="utf-8")
        notes = []
        for repo, (tag, sha) in resolved.items():
            src, changed = _replace_action_pin(src, repo, tag, sha)
            if changed:
                notes.append(f"action {repo} -> {tag}")
        if notes:
            planned.append((path, src, notes))
    changed = []
    for path, src, notes in planned:
        path.write_text(src, encoding="utf-8")
        changed.extend(notes)
    return changed

def main() -> int:
    compiler_versions = {repo: latest_release(repo) for repo in COMPILERS.values()}
    action_versions = {
        repo: latest_tag_in_major(repo, major) for repo, major in TRACKED_ACTIONS.items()
    }
    changed = update_compilers(compiler_versions) + update_actions(action_versions)
    if changed:
        for line in changed:
            print(f"updated: {line}")
    else:
        print("up-to-date")
    return 0

if __name__ == "__main__":
    sys.exit(main())
