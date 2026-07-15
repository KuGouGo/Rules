#!/usr/bin/env python3
"""Generate and strictly verify the canonical publication artifact manifest."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any

from artifact_origins import ALLOWED_ORIGINS, load_origin_file
from artifact_verifier import verify_one
from platform_capabilities import load_platform_capabilities

SCHEMA_VERSION = 4
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
GENERATION_RE = re.compile(r"^[0-9]+-[0-9]+$")
TOP_KEYS = {"schema_version", "generation_id", "build_id", "build_scope", "source", "baseline", "inputs", "tools", "summaries", "artifacts", "restoration"}
SOURCE_KEYS = {"commit", "tree"}
INPUT_KEYS = {"capabilities", "tool_lock", "artifact_origins"}
INPUT_VALUE_KEYS = {"path", "sha256"}
TOOLS_KEYS = {"lock", "installed"}
SUMMARY_KEYS = {"path", "sha256", "content"}
ARTIFACT_KEYS = {"path", "platform", "type", "extension", "bytes", "sha256", "origin", "verification"}
RESTORATION_KEYS = {"status", "generation_id", "source_commit", "branches"}
BRANCH_KEYS = {"commit", "generation_id", "source_commit"}
PUBLISH_BRANCHES = {"surge", "quanx", "egern", "sing-box", "mihomo"}
INTERNAL_ARTIFACT_FILES = {"domain/rule-manifest.json"}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def git_value(root: Path, *args: str) -> str | None:
    try:
        return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL, text=True).strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def artifact_output(root: Path) -> Path:
    override = os.environ.get("RULES_ARTIFACT_ROOT")
    return Path(override).resolve() if override else root / ".output"


def capability_matrix(root: Path) -> dict[tuple[str, str], dict[str, str]]:
    registry = load_platform_capabilities(root / "config" / "domain-platform-capabilities.json")
    return {(section, platform): {"extension": capability.extension, "format": capability.format}
            for platform, _details, section, capability in registry.iter_capabilities()}


def require_exact(value: Any, keys: set[str], location: str, errors: list[str]) -> bool:
    if not isinstance(value, dict):
        errors.append(f"{location} must be an object")
        return False
    if set(value) != keys:
        errors.append(f"{location} must contain exactly {sorted(keys)}")
        return False
    return True


def collect_artifacts(root: Path, origins: dict[str, str]) -> list[dict[str, Any]]:
    output, matrix = artifact_output(root), capability_matrix(root)
    artifacts: list[dict[str, Any]] = []
    for (artifact_type, platform), details in sorted(matrix.items()):
        directory = output / artifact_type / platform
        if not directory.is_dir():
            continue
        for path in sorted(directory.iterdir(), key=lambda item: item.name):
            if not path.is_file() or path.suffix != "." + details["extension"]:
                continue
            rel = path.relative_to(output).as_posix()
            if rel not in origins:
                raise SystemExit(f"artifact origin provenance missing for {rel}")
            try:
                verification = verify_one(root, path, artifact_type, platform)
            except Exception as exc:
                raise SystemExit(f"refusing to manifest unverified artifact {rel}: {exc}") from exc
            artifacts.append({"path": rel, "platform": platform, "type": artifact_type,
                              "extension": details["extension"], "bytes": path.stat().st_size,
                              "sha256": digest(path), "origin": origins[rel], "verification": verification})
    extra = set(origins) - {item["path"] for item in artifacts}
    if extra:
        raise SystemExit(f"artifact origin provenance lists non-publishable paths: {', '.join(sorted(extra))}")
    if not artifacts:
        raise SystemExit("refusing to generate manifest with an empty artifact set")
    return artifacts


def provenance_metadata(root: Path, lock: dict[str, Any]) -> dict[str, Any]:
    installed: dict[str, Any] = {}
    for tool in sorted(lock["tools"]):
        candidate = root / ".bin" / f"{tool}.provenance.json"
        if not candidate.is_file():
            raise SystemExit(f"trusted tool provenance missing: {candidate}")
        installed[tool] = load_json(candidate)
    return {"lock": lock, "installed": installed}


def validate_verification(value: Any, location: str, errors: list[str]) -> None:
    keys = {"status", "method", "decoded_counts", "decoded_count", "decoded_semantic_sha256", "canonical_linkage"}
    if not require_exact(value, keys, location, errors):
        return
    if value["status"] != "verified" or not isinstance(value["method"], str) or not value["method"]:
        errors.append(f"{location} has invalid status or method")
    counts = value["decoded_counts"]
    if not isinstance(counts, dict) or any(not isinstance(key, str) or not key or type(count) is not int or count < 0 for key, count in counts.items()):
        errors.append(f"{location}.decoded_counts must map strings to non-negative integers")
    elif type(value["decoded_count"]) is not int or value["decoded_count"] != sum(counts.values()) or value["decoded_count"] <= 0:
        errors.append(f"{location}.decoded_count is invalid")
    if not isinstance(value["decoded_semantic_sha256"], str) or not SHA256_RE.fullmatch(value["decoded_semantic_sha256"]):
        errors.append(f"{location}.decoded_semantic_sha256 is invalid")
    linkage = value["canonical_linkage"]
    if not isinstance(linkage, dict) or linkage.get("status") not in {"matched", "unavailable"}:
        errors.append(f"{location}.canonical_linkage is invalid")
    elif linkage["status"] == "matched":
        if set(linkage) != {"status", "source", "counts", "semantic_sha256"} or not isinstance(linkage.get("source"), str) or not isinstance(linkage.get("counts"), dict) or not isinstance(linkage.get("semantic_sha256"), str) or not SHA256_RE.fullmatch(linkage["semantic_sha256"]):
            errors.append(f"{location}.canonical_linkage matched schema is invalid")
    elif set(linkage) != {"status", "reason"} or not isinstance(linkage.get("reason"), str) or not linkage["reason"]:
        errors.append(f"{location}.canonical_linkage unavailable schema is invalid")


def validate_tool_provenance(root: Path, tools: Any, lock: dict[str, Any], errors: list[str]) -> None:
    if not require_exact(tools, TOOLS_KEYS, "manifest tools", errors):
        return
    if tools["lock"] != lock:
        errors.append("manifest tools.lock does not match current tool lock")
    installed = tools["installed"]
    if not isinstance(installed, dict) or set(installed) != set(lock["tools"]):
        errors.append("manifest tools.installed must contain exactly the locked tools")
        return
    for name, sidecar in installed.items():
        path = root / ".bin" / f"{name}.provenance.json"
        try:
            current = load_json(path)
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"current trusted provenance unreadable for {name}: {exc}")
            continue
        if sidecar != current:
            errors.append(f"manifest tool provenance mismatch: {name}")
        locked = lock["tools"][name]
        expected_keys = {"schema_version", "tool", "version", "tag_commit", "platform", "asset", "archive_sha256", "binary_sha256", "version_probe"}
        if not isinstance(sidecar, dict) or set(sidecar) != expected_keys:
            errors.append(f"tool provenance has invalid schema: {name}")
            continue
        platform = sidecar.get("platform")
        platform_lock = locked.get("platforms", {}).get(platform) if isinstance(platform, str) else None
        expected = {"schema_version": 1, "tool": name, "version": locked.get("version"), "tag_commit": locked.get("tag_commit")}
        if any(sidecar.get(key) != value for key, value in expected.items()) or not isinstance(platform_lock, dict):
            errors.append(f"tool provenance disagrees with lock: {name}")
            continue
        if sidecar.get("asset") != platform_lock.get("asset") or sidecar.get("archive_sha256") != platform_lock.get("sha256") or sidecar.get("binary_sha256") != platform_lock.get("binary_sha256"):
            errors.append(f"tool provenance digest disagrees with lock: {name}")
        binary = root / ".bin" / name
        if not binary.is_file() or digest(binary) != sidecar.get("binary_sha256"):
            errors.append(f"installed tool binary is not authenticated: {name}")


def validate_publication_cohort(value: Any, location: str, errors: list[str]) -> bool:
    if not require_exact(value, RESTORATION_KEYS, location, errors):
        return False
    status = value["status"]
    if status not in {"consistent", "inconsistent"}:
        errors.append(f"{location} status must be consistent or inconsistent")
    branches = value["branches"]
    if not isinstance(branches, dict) or set(branches) != PUBLISH_BRANCHES:
        errors.append(f"{location} must record all publish branches")
    else:
        for branch, item in branches.items():
            if (
                not require_exact(item, BRANCH_KEYS, f"{location}.branches.{branch}", errors)
                or not isinstance(item.get("commit"), str)
                or not GIT_SHA_RE.fullmatch(item.get("commit", ""))
            ):
                errors.append(f"{location} branch commit invalid: {branch}")
                continue
            branch_generation = item["generation_id"]
            branch_source = item["source_commit"]
            if branch_generation is not None and (
                not isinstance(branch_generation, str) or not GENERATION_RE.fullmatch(branch_generation)
            ):
                errors.append(f"{location} branch generation invalid: {branch}")
            if branch_source is not None and (
                not isinstance(branch_source, str) or not GIT_SHA_RE.fullmatch(branch_source)
            ):
                errors.append(f"{location} branch source invalid: {branch}")
    if status == "consistent":
        generation = value["generation_id"]
        source = value["source_commit"]
        if not isinstance(generation, str) or not GENERATION_RE.fullmatch(generation):
            errors.append(f"{location} generation_id must use <run-id>-<attempt>")
        if not isinstance(source, str) or not GIT_SHA_RE.fullmatch(source):
            errors.append(f"{location} source_commit must be a Git commit")
        if isinstance(branches, dict):
            identities = {
                (item.get("generation_id"), item.get("source_commit"))
                for item in branches.values()
                if isinstance(item, dict)
            }
            if identities != {(generation, source)}:
                errors.append(f"{location} consistent branch identities disagree")
    elif value["generation_id"] is not None or value["source_commit"] is not None:
        errors.append(f"{location} inconsistent identity must be null")
    return True


def git_is_ancestor(root: Path, ancestor: str, descendant: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", ancestor, descendant],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def generate(args: argparse.Namespace) -> None:
    root, output = args.root.resolve(), artifact_output(args.root.resolve())
    output.mkdir(parents=True, exist_ok=True)
    capabilities_path, lock_path = root / "config/domain-platform-capabilities.json", root / "config/tools-lock.json"
    origins_path = output / "artifact-origins.json"
    lock, origins = load_json(lock_path), load_origin_file(origins_path, require_nonempty=True)
    source_commit = args.source_sha or git_value(root, "rev-parse", "HEAD")
    source_tree = git_value(root, "rev-parse", f"{source_commit}^{{tree}}") if source_commit else None
    if args.source_sha and (not GIT_SHA_RE.fullmatch(args.source_sha) or source_tree is None):
        raise SystemExit(f"source SHA is not a locally resolvable Git commit: {args.source_sha}")
    summaries: dict[str, Any] = {}
    for name in ("upstream-summary.json", "build-summary.json"):
        path = output / name
        if path.is_file():
            summaries[name.removesuffix(".json").replace("-", "_")] = {"path": name, "sha256": digest(path), "content": load_json(path)}
    baseline_path = Path(os.environ.get("ARTIFACT_BASELINE_FILE", root / ".tmp" / "publication-baseline.json"))
    try:
        baseline = load_json(baseline_path)
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"publication baseline unreadable: {exc}") from exc
    baseline_errors: list[str] = []
    validate_publication_cohort(baseline, "publication baseline", baseline_errors)
    if baseline_errors:
        raise SystemExit("invalid publication baseline: " + "; ".join(baseline_errors))
    if baseline["status"] == "consistent" and source_commit and not git_is_ancestor(root, baseline["source_commit"], source_commit):
        raise SystemExit(
            f"stale source refused: publication baseline {baseline['source_commit']} "
            f"is not an ancestor of candidate {source_commit}"
        )
    restoration = load_json(output / "restoration-metadata.json") if (output / "restoration-metadata.json").is_file() else None
    if args.build_scope == "custom":
        if baseline["status"] != "consistent":
            raise SystemExit("custom build requires a consistent publication baseline")
        if restoration != baseline:
            raise SystemExit("custom restoration metadata does not match the selected publication baseline")
    if args.build_scope == "full" and restoration is not None:
        raise SystemExit("full build must not contain restoration metadata")
    manifest = {"schema_version": SCHEMA_VERSION, "generation_id": args.generation_id,
                "build_id": args.build_id or args.generation_id, "build_scope": args.build_scope,
                "source": {"commit": source_commit, "tree": source_tree},
                "baseline": baseline,
                "inputs": {"capabilities": {"path": "config/domain-platform-capabilities.json", "sha256": digest(capabilities_path)},
                           "tool_lock": {"path": "config/tools-lock.json", "sha256": digest(lock_path)},
                           "artifact_origins": {"path": "artifact-origins.json", "sha256": digest(origins_path)}},
                "tools": provenance_metadata(root, lock), "summaries": summaries,
                "artifacts": collect_artifacts(root, origins), "restoration": restoration}
    target = output / "artifact-manifest.json"
    target.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {target} with {len(manifest['artifacts'])} artifacts")


def safe_artifact_path(value: str) -> bool:
    path = PurePosixPath(value)
    return value == path.as_posix() and not path.is_absolute() and len(path.parts) == 3 and path.parts[0] in {"domain", "ip"} and all(part not in {"", ".", ".."} for part in path.parts) and "\\" not in value


def verify(args: argparse.Namespace) -> None:
    root, output, errors = args.root.resolve(), artifact_output(args.root.resolve()), []
    try:
        manifest = load_json(output / "artifact-manifest.json")
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"artifact manifest unreadable: {exc}")
    if not require_exact(manifest, TOP_KEYS, "manifest", errors):
        manifest = manifest if isinstance(manifest, dict) else {}
    if type(manifest.get("schema_version")) is not int or manifest.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"unsupported artifact manifest schema_version: {manifest.get('schema_version')}")
    for key in ("generation_id", "build_id"):
        if not isinstance(manifest.get(key), str) or not manifest[key]: errors.append(f"manifest {key} must be a non-empty string")
    if manifest.get("build_scope") not in {"custom", "full"}: errors.append("manifest build_scope must be custom or full")
    source = manifest.get("source")
    if require_exact(source, SOURCE_KEYS, "manifest source", errors):
        for key in SOURCE_KEYS:
            if source[key] is not None and (not isinstance(source[key], str) or not GIT_SHA_RE.fullmatch(source[key])): errors.append(f"manifest source.{key} must be a Git object id or null")
        if args.source_sha:
            actual_tree = git_value(root, "rev-parse", f"{args.source_sha}^{{tree}}")
            if actual_tree is None: errors.append(f"source SHA is not a locally resolvable Git commit: {args.source_sha}")
            if source["commit"] != args.source_sha: errors.append(f"source commit mismatch: expected {args.source_sha}, got {source['commit']}")
            if actual_tree and source["tree"] != actual_tree: errors.append(f"source tree mismatch: expected {actual_tree}, got {source['tree']}")
    baseline = manifest.get("baseline")
    if validate_publication_cohort(baseline, "manifest baseline", errors):
        source_commit = source.get("commit") if isinstance(source, dict) else None
        baseline_source = baseline.get("source_commit")
        if (
            baseline.get("status") == "consistent"
            and
            isinstance(source_commit, str)
            and GIT_SHA_RE.fullmatch(source_commit)
            and isinstance(baseline_source, str)
            and GIT_SHA_RE.fullmatch(baseline_source)
            and not git_is_ancestor(root, baseline_source, source_commit)
        ):
            errors.append(
                f"stale source refused: manifest baseline {baseline_source} "
                f"is not an ancestor of candidate {source_commit}"
            )
    capabilities_path, lock_path, origins_path = root / "config/domain-platform-capabilities.json", root / "config/tools-lock.json", output / "artifact-origins.json"
    try:
        matrix, lock, origins = capability_matrix(root), load_json(lock_path), load_origin_file(origins_path, require_nonempty=True)
    except (OSError, ValueError, json.JSONDecodeError, SystemExit) as exc:
        errors.append(f"manifest verification input invalid: {exc}"); matrix, lock, origins = {}, {}, {}
    inputs = manifest.get("inputs")
    if require_exact(inputs, INPUT_KEYS, "manifest inputs", errors):
        for name, path, recorded_path in (("capabilities", capabilities_path, "config/domain-platform-capabilities.json"), ("tool_lock", lock_path, "config/tools-lock.json"), ("artifact_origins", origins_path, "artifact-origins.json")):
            item = inputs[name]
            if require_exact(item, INPUT_VALUE_KEYS, f"manifest inputs.{name}", errors):
                if item["path"] != recorded_path: errors.append(f"{name} input path mismatch")
                if not path.is_file() or item["sha256"] != digest(path): errors.append(f"{name} hash mismatch")
    validate_tool_provenance(root, manifest.get("tools"), lock, errors)
    summaries = manifest.get("summaries")
    if not isinstance(summaries, dict) or set(summaries) - {"upstream_summary", "build_summary"}: errors.append("manifest summaries has unsupported keys")
    elif "build_summary" not in summaries: errors.append("manifest summaries must include build_summary")
    else:
        for key, item in summaries.items():
            if not require_exact(item, SUMMARY_KEYS, f"manifest summaries.{key}", errors): continue
            expected_path = key.replace("_", "-") + ".json"
            if item["path"] != expected_path: errors.append(f"summary path mismatch: {key}"); continue
            path = output / expected_path
            try: content = load_json(path)
            except (OSError, json.JSONDecodeError) as exc: errors.append(f"summary unreadable: {expected_path}: {exc}"); continue
            if item["sha256"] != digest(path): errors.append(f"summary hash mismatch: {expected_path}")
            if item["content"] != content: errors.append(f"summary embedded content mismatch: {expected_path}")
    restoration = manifest.get("restoration")
    if manifest.get("build_scope") == "custom":
        if validate_publication_cohort(restoration, "manifest restoration", errors):
            if isinstance(baseline, dict) and baseline.get("status") != "consistent":
                errors.append("custom manifest baseline must be consistent")
            if restoration != baseline:
                errors.append("manifest restoration must match the publication baseline")
    elif restoration is not None: errors.append("full manifest restoration must be null")
    entries = manifest.get("artifacts")
    if not isinstance(entries, list) or not entries: errors.append("manifest artifacts must be a non-empty array"); entries = []
    recorded: set[str] = set()
    for index, entry in enumerate(entries):
        if not require_exact(entry, ARTIFACT_KEYS, f"artifact entry {index}", errors): continue
        rel = entry["path"]
        if not isinstance(rel, str) or not safe_artifact_path(rel): errors.append(f"unsafe or nested artifact path: {rel!r}"); continue
        if rel in recorded: errors.append(f"duplicate artifact path: {rel}")
        recorded.add(rel); artifact_type, platform, filename = PurePosixPath(rel).parts; expected = matrix.get((artifact_type, platform)); extension = filename.rsplit(".", 1)[-1] if "." in filename else ""
        if not expected: errors.append(f"artifact capability missing for {rel}")
        elif entry["type"] != artifact_type or entry["platform"] != platform or entry["extension"] != extension or extension != expected["extension"]: errors.append(f"artifact metadata disagrees with capabilities: {rel}")
        if entry["origin"] not in ALLOWED_ORIGINS or origins.get(rel) != entry["origin"]: errors.append(f"artifact origin provenance mismatch for {rel}")
        path = output / Path(*PurePosixPath(rel).parts)
        if not path.is_file(): errors.append(f"manifest artifact missing: {rel}"); continue
        size = path.stat().st_size
        if size <= 0: errors.append(f"zero-byte artifact: {rel}")
        if type(entry["bytes"]) is not int or entry["bytes"] != size: errors.append(f"artifact byte count mismatch: {rel}")
        if not isinstance(entry["sha256"], str) or not SHA256_RE.fullmatch(entry["sha256"]) or entry["sha256"] != digest(path): errors.append(f"artifact hash mismatch: {rel}")
        validate_verification(entry["verification"], f"artifact verification for {rel}", errors)
        try: actual_verification = verify_one(root, path, artifact_type, platform)
        except Exception as exc: errors.append(f"artifact binary/readability verification failed for {rel}: {exc}")
        else:
            if entry["verification"] != actual_verification: errors.append(f"artifact verification metadata mismatch: {rel}")
    actual: set[str] = set()
    for artifact_type in ("domain", "ip"):
        base = output / artifact_type
        if not base.exists(): continue
        for path in base.rglob("*"):
            if not path.is_file(): continue
            rel, parts = path.relative_to(output).as_posix(), PurePosixPath(path.relative_to(output).as_posix()).parts
            if rel in INTERNAL_ARTIFACT_FILES: continue
            if len(parts) != 3: errors.append(f"unexpected nested publishable file: {rel}"); continue
            expected = matrix.get((parts[0], parts[1]))
            if not expected or path.suffix != "." + expected["extension"]: errors.append(f"unexpected publishable file: {rel}"); continue
            actual.add(rel)
    for rel in sorted(actual - recorded): errors.append(f"unmanifested artifact: {rel}")
    for rel in sorted(recorded - actual): errors.append(f"manifest lists non-publishable artifact: {rel}")
    if errors:
        print("artifact manifest verification failed:", file=sys.stderr)
        for error in errors: print(f"- {error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"artifact manifest verified: {len(recorded)} artifacts, generation {manifest['generation_id']}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(); result.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    sub = result.add_subparsers(dest="command", required=True)
    create = sub.add_parser("generate"); create.add_argument("--generation-id", required=True); create.add_argument("--build-id"); create.add_argument("--build-scope", choices=("custom", "full"), required=True); create.add_argument("--source-sha"); create.set_defaults(func=generate)
    check = sub.add_parser("verify"); check.add_argument("--source-sha"); check.set_defaults(func=verify)
    return result


def main() -> None:
    args = parser().parse_args(); args.func(args)

if __name__ == "__main__": main()
