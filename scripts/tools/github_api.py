#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import urllib.request


def request_headers(user_agent: str) -> dict[str, str]:

    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": user_agent,
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def api_get(url: str, headers: dict[str, str]):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def resolve_tag_commit(repo: str, tag: str, headers: dict[str, str]) -> str:

    ref = api_get(f"https://api.github.com/repos/{repo}/git/refs/tags/{tag}", headers)
    obj = ref["object"]
    if obj["type"] == "commit":
        return obj["sha"]
    tag_obj = api_get(f"https://api.github.com/repos/{repo}/git/tags/{obj['sha']}", headers)
    return tag_obj["object"]["sha"]
