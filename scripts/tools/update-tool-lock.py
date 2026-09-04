#!/usr/bin/env python3

import argparse
import gzip
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

from github_api import api_get, request_headers, resolve_tag_commit

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


def download(url, headers):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def verify_release_attestation(archive_path, repository):


    gh = shutil.which("gh")
    if gh is None:
        return "unavailable"
    proc = subprocess.run(
        [gh, "attestation", "verify", str(archive_path), "--repo", repository],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    if proc.returncode == 0:
        return "verified"
    output = (proc.stdout or "").strip()
    if "HTTP 404" in output or "no attestations found" in output.lower():
        return "unavailable"
    raise RuntimeError(
        f"artifact attestation verification failed for {archive_path.name} "
        f"in {repository}: {output[:500]}"
    )


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


def replace_pinned_version(path, text, tool, other_tool, old, new):


    tool_tokens = (tool.lower(), tool.lower().replace("-", "_"))
    other_tokens = (other_tool.lower(), other_tool.lower().replace("-", "_"))
    out_lines = []
    for line in text.splitlines(keepends=True):
        if old not in line:
            out_lines.append(line)
            continue
        lowered = line.lower()
        has_tool = any(token in lowered for token in tool_tokens)
        has_other = any(token in lowered for token in other_tokens)
        if has_tool and not has_other:
            out_lines.append(line.replace(old, new))
        else:
            raise RuntimeError(
                f"{path.name}: pinned value {old!r} appears on a line without an "
                f"unambiguous {tool} marker; refusing a blind replace"
            )
    return "".join(out_lines)


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
            [(update["old_tag_commit"], update["new"]["tag_commit"])],
        )
    all_tools = list(TOOLS)
    for tool, update in updates.items():
        other_tool = next(name for name in all_tools if name != tool)
        text = replace_pinned_version(
            tool_lock_test,
            text,
            tool,
            other_tool,
            update["old_version"],
            update["new"]["version"],
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--lock", type=Path)
    args = parser.parse_args(argv)

    root = args.root
    lock_path = args.lock or root / "config" / "tools-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))

    headers = request_headers("Rules-tool-lock-updater")

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
            with tempfile.TemporaryDirectory() as verify_dir:
                archive_file = Path(verify_dir) / asset
                archive_file.write_bytes(archive_bytes)
                attestation = verify_release_attestation(archive_file, repo)
            if attestation == "verified":
                print(f"{tool} {asset}: artifact attestation verified")
            else:
                print(
                    f"warning: {tool} {asset}: upstream does not publish artifact "
                    "attestations; the locked digest anchors the downloaded asset",
                    file=sys.stderr,
                )
            binary = binary_from_archive(meta["archive_format"], archive_bytes, tool, asset)
            platforms[platform] = {
                "asset": asset,
                "sha256": sha256_bytes(archive_bytes),
                "binary_sha256": sha256_bytes(binary),
                "attestation": attestation,
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
