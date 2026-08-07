#!/usr/bin/env python3
"""Refresh config/tools-lock.json from the latest upstream sing-box/mihomo releases.

Queries the GitHub releases API for the latest tags, downloads the locked
linux-amd64/linux-arm64 assets, computes archive and extracted-binary SHA-256
digests, resolves the tag commit, and writes the updated lock plus the tests
that pin the locked versions.

Exits 0. Prints changed=true (and a versions= summary) only when at least one
tool was updated; otherwise prints changed=false.
"""

import argparse
import gzip
import hashlib
import io
import json
import os
import sys
import tarfile
import urllib.request
from pathlib import Path

TOOLS = {
    "sing-box": {
        "repository": "SagerNet/sing-box",
        "asset_patterns": {
            "linux-amd64": "sing-box-{version}-linux-amd64.tar.gz",
            "linux-arm64": "sing-box-{version}-linux-arm64.tar.gz",
        },
        "archive_format": "tar.gz",
    },
    "mihomo": {
        "repository": "MetaCubeX/mihomo",
        "asset_patterns": {
            "linux-amd64": "mihomo-linux-amd64-compatible-{tag}.gz",
            "linux-arm64": "mihomo-linux-arm64-{tag}.gz",
        },
        "archive_format": "gz",
    },
}


def api_get(url, headers):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def download(url, headers):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def resolve_tag_commit(repo, tag, headers):
    """Return the commit SHA a release tag resolves to (annotated tags included)."""
    ref = api_get(f"https://api.github.com/repos/{repo}/git/refs/tags/{tag}", headers)
    obj = ref["object"]
    if obj["type"] == "commit":
        return obj["sha"]
    tag_obj = api_get(f"https://api.github.com/repos/{repo}/git/tags/{obj['sha']}", headers)
    return tag_obj["object"]["sha"]


def binary_from_archive(archive_format, archive_bytes, tool, asset):
    if archive_format == "tar.gz":
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.endswith(f"/{tool}"):
                    extracted = tar.extractfile(member)
                    if extracted is not None:
                        return extracted.read()
        raise RuntimeError(f"{tool} binary not found inside {asset}")
    if archive_format == "gz":
        return gzip.decompress(archive_bytes)
    raise RuntimeError(f"unsupported archive format: {archive_format}")


def patch_tests(root, updates):
    def apply_replacements(path, text, replacements):
        for old, new in replacements:
            if old not in text:
                raise RuntimeError(
                    f"{path.name}: pinned value {old!r} not found; "
                    "refusing to write a stale test"
                )
            text = text.replace(old, new)
        return text

    tool_lock_test = root / "scripts/tests/test-tool-lock.sh"
    text = tool_lock_test.read_text(encoding="utf-8")
    for tool, update in updates.items():
        text = apply_replacements(
            tool_lock_test,
            text,
            [
                (update["old_version"], update["new"]["version"]),
                (update["old_tag_commit"], update["new"]["tag_commit"]),
            ],
        )
    tool_lock_test.write_text(text, encoding="utf-8")

    upstream_test = root / "scripts/tests/test-upstream-config.sh"
    text = upstream_test.read_text(encoding="utf-8")
    if "mihomo" in updates:
        text = apply_replacements(
            upstream_test,
            text,
            [
                (
                    updates["mihomo"]["old_arm64_asset"],
                    updates["mihomo"]["new"]["platforms"]["linux-arm64"]["asset"],
                ),
            ],
        )
    upstream_test.write_text(text, encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--lock", type=Path)
    args = parser.parse_args(argv)

    root = args.root
    lock_path = args.lock or root / "config" / "tools-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "Rules-tool-lock-updater",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    updates = {}
    for tool, meta in TOOLS.items():
        repo = meta["repository"]
        entry = lock["tools"][tool]
        release = api_get(f"https://api.github.com/repos/{repo}/releases/latest", headers)
        tag = release["tag_name"]
        version = tag[1:] if tag.startswith("v") else tag
        if version == entry["version"]:
            print(f"{tool}: already latest ({version}), skipping")
            continue

        print(f"{tool}: locked {entry['version']} -> {version}")
        assets = {asset["name"]: asset["browser_download_url"] for asset in release.get("assets", [])}
        tag_commit = resolve_tag_commit(repo, tag, headers)

        platforms = {}
        for platform, pattern in meta["asset_patterns"].items():
            asset = pattern.format(version=version, tag=tag)
            if asset not in assets:
                raise RuntimeError(f"{tool} {tag}: asset {asset} not found in release")
            archive_bytes = download(assets[asset], headers)
            binary = binary_from_archive(meta["archive_format"], archive_bytes, tool, asset)
            platforms[platform] = {
                "asset": asset,
                "sha256": sha256_bytes(archive_bytes),
                "binary_sha256": sha256_bytes(binary),
            }

        updates[tool] = {
            "old_version": entry["version"],
            "old_tag_commit": entry["tag_commit"],
            "old_arm64_asset": entry["platforms"]["linux-arm64"]["asset"],
            "new": {
                "version": version,
                "tag": tag,
                "tag_commit": tag_commit,
                "platforms": platforms,
            },
        }

    if not updates:
        print("changed=false")
        return 0

    for tool, update in updates.items():
        entry = lock["tools"][tool]
        entry["version"] = update["new"]["version"]
        entry["tag"] = update["new"]["tag"]
        entry["tag_commit"] = update["new"]["tag_commit"]
        for platform, platform_data in update["new"]["platforms"].items():
            entry["platforms"][platform] = platform_data

    lock_path.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    patch_tests(root, updates)

    versions = ", ".join(f"{tool} {update['new']['version']}" for tool, update in updates.items())
    for tool, update in updates.items():
        print(
            f"updated {tool} to {update['new']['version']} "
            f"(tag {update['new']['tag']}, commit {update['new']['tag_commit'][:12]})"
        )
    print(f"versions={versions}")
    print("changed=true")
    return 0


if __name__ == "__main__":
    sys.exit(main())
