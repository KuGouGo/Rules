#!/usr/bin/env python3

from __future__ import annotations

import json
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

ACTION_FILES = [
    ROOT / ".github/workflows/build.yml",
    ROOT / ".github/actions/setup-tools/action.yml",
]

TRACKED_ACTIONS = {
    "actions/checkout": 7,
    "actions/setup-python": 7,
    "actions/cache": 6,
}

def latest_release(repo: str) -> str:
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    with urllib.request.urlopen(url, timeout=30) as response:
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

def update_compilers() -> list[str]:
    path = ROOT / "scripts/lib/common.sh"
    src = path.read_text(encoding="utf-8")
    changed = []
    for var, repo in COMPILERS.items():
        latest = latest_release(repo)
        match = re.search(rf'^{var}="([0-9.]+)"$', src, re.M)
        if not match:
            raise RuntimeError(f"{path} 中未找到 {var}")
        current = match.group(1)
        if current != latest:
            src = src.replace(f'{var}="{current}"', f'{var}="{latest}"')
            changed.append(f"compiler {repo.split('/')[1]} {current} -> {latest}")
    if changed:
        path.write_text(src, encoding="utf-8")
    return changed

def update_actions() -> list[str]:
    resolved = {
        repo: latest_tag_in_major(repo, major) for repo, major in TRACKED_ACTIONS.items()
    }
    changed = []
    for path in ACTION_FILES:
        src = path.read_text(encoding="utf-8")
        for repo, (tag, sha) in resolved.items():
            pattern = re.compile(
                rf"uses: {re.escape(repo)}@([0-9a-f]{{40}})( # v[0-9.]+)?"
            )
            match = pattern.search(src)
            if not match:
                continue
            current_sha, current_note = match.group(1), match.group(2) or ""
            if current_sha == sha and current_note == f" # {tag}":
                continue
            src = pattern.sub(f"uses: {repo}@{sha} # {tag}", src)
            changed.append(f"action {repo} {current_note.strip()} -> {tag}")
        path.write_text(src, encoding="utf-8")
    return changed

def main() -> int:
    changed = update_compilers() + update_actions()
    if changed:
        for line in changed:
            print(f"updated: {line}")
    else:
        print("up-to-date")
    return 0

if __name__ == "__main__":
    sys.exit(main())
