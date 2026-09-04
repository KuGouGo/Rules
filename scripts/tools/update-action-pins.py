#!/usr/bin/env python3

import argparse
import json
import re
import sys
from pathlib import Path

from github_api import api_get, request_headers, resolve_tag_commit


ACTIONS = (
    "actions/cache",
    "actions/checkout",
    "actions/download-artifact",
    "actions/setup-python",
    "actions/upload-artifact",
)
USES_RE = re.compile(
    r"^(?P<prefix>\s*(?:-\s*)?uses:\s*)"
    r"(?P<repo>actions/[A-Za-z0-9_.-]+)@(?P<sha>[0-9a-f]{40})"
    r"(?P<comment>\s+#\s+)(?P<version>v?[0-9]+\.[0-9]+\.[0-9]+)\s*$"
)


def latest_actions(headers):
    latest = {}
    for repo in ACTIONS:
        release = api_get(f"https://api.github.com/repos/{repo}/releases/latest", headers)
        tag = release["tag_name"]
        if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
            raise RuntimeError(f"{repo}: latest release has unexpected tag {tag!r}")
        latest[repo] = {"version": tag, "sha": resolve_tag_commit(repo, tag, headers)}
    return latest


def workflow_paths(root):
    paths = []
    for directory in (root / ".github" / "workflows", root / ".github" / "actions"):
        paths.extend(directory.rglob("*.yml"))
        paths.extend(directory.rglob("*.yaml"))
    return sorted(paths)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--metadata", type=Path, help="read release metadata instead of GitHub")
    args = parser.parse_args(argv)

    headers = request_headers("Rules-action-pin-updater")

    if args.metadata:
        latest = json.loads(args.metadata.read_text(encoding="utf-8"))
    else:
        latest = latest_actions(headers)

    if set(latest) != set(ACTIONS):
        raise RuntimeError("release metadata must contain exactly the configured actions")
    for repo, release in latest.items():
        if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", release.get("version", "")):
            raise RuntimeError(f"{repo}: invalid release version")
        if not re.fullmatch(r"[0-9a-f]{40}", release.get("sha", "")):
            raise RuntimeError(f"{repo}: invalid release commit")

    changed = set()
    for path in workflow_paths(args.root):
        original = path.read_text(encoding="utf-8")
        output = []
        for line in original.splitlines(keepends=True):
            newline = "\n" if line.endswith("\n") else ""
            content = line[:-1] if newline else line
            match = USES_RE.match(content)
            if not match or match.group("repo") not in latest:
                output.append(line)
                continue
            repo = match.group("repo")
            release = latest[repo]
            replacement = (
                f"{match.group('prefix')}{repo}@{release['sha']}"
                f"{match.group('comment')}{release['version']}{newline}"
            )
            output.append(replacement)
            if replacement != line:
                changed.add(repo)
        rendered = "".join(output)
        if rendered != original:
            path.write_text(rendered, encoding="utf-8")

    if not changed:
        print("changed=false")
        return 0

    versions = ", ".join(f"{repo} {latest[repo]['version']}" for repo in sorted(changed))
    print(f"versions={versions}")
    print("changed=true")
    return 0


if __name__ == "__main__":
    sys.exit(main())
