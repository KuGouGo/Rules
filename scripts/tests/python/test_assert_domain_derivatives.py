import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _paths  # noqa: F401

TOOL = _paths.TOOLS_DIR / "assert-domain-derivatives.py"


def build_manifest(
    required=True,
    geolocation_pair=True,
    aggregate_rules=600,
    extended=False,
    include_geolocation_cn=None,
):
    lists = [
        {"name": name, "kind": "attr", "attr": attr}
        for name, attr in {
            "cn": "cn",
            "geolocation-!cn": "!cn",
            "geolocation-cn": "cn",
            "geolocation-!cn@cn": "cn",
            "tld-cn": "cn",
        }.items()
    ]
    aggregate = next(
        entry for entry in lists if entry["name"] == "geolocation-!cn@cn"
    )
    aggregate["rules"] = aggregate_rules
    if include_geolocation_cn is None:
        include_geolocation_cn = extended
    if not include_geolocation_cn:
        lists = [entry for entry in lists if entry["name"] != "geolocation-cn"]
    if not required:
        lists = [entry for entry in lists if entry["name"] != "cn"]
    regions = ["cn", "!cn"] if extended else ["!cn"]
    region_pairs = {"geolocation": regions} if geolocation_pair else {}
    return {"lists": lists, "region_pairs": region_pairs}


class AssertDomainDerivativesTest(unittest.TestCase):
    def run_tool(self, manifest_path, profile="common"):
        return subprocess.run(
            [
                sys.executable,
                str(TOOL),
                str(manifest_path),
                "500",
                "--profile",
                profile,
            ],
            capture_output=True,
            text=True,
        )

    def test_passing_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            manifest.write_text(
                json.dumps(build_manifest()),
                encoding="utf-8",
            )
            result = self.run_tool(manifest)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("domain derivative rule sets", result.stdout)

    def test_aggregate_too_small(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            manifest.write_text(
                json.dumps(build_manifest(aggregate_rules=10)),
                encoding="utf-8",
            )
            result = self.run_tool(manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("geolocation-!cn@cn rules too low", result.stderr)

    def test_extended_profile_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            manifest.write_text(json.dumps(build_manifest(extended=True)), encoding="utf-8")
            result = self.run_tool(manifest, "extended")
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_extended_profile_requires_compatibility_entry_points(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            manifest.write_text(
                json.dumps(build_manifest(extended=True, include_geolocation_cn=False)),
                encoding="utf-8",
            )
            result = self.run_tool(manifest, "extended")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required derivative rule sets: geolocation-cn", result.stderr)

    def test_missing_required_rule_set(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            manifest.write_text(
                json.dumps(build_manifest(required=False)),
                encoding="utf-8",
            )
            result = self.run_tool(manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required derivative rule sets", result.stderr)

    def test_missing_geolocation_pair(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            manifest.write_text(
                json.dumps(build_manifest(geolocation_pair=False)),
                encoding="utf-8",
            )
            result = self.run_tool(manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required geolocation regional entry point", result.stderr)


if __name__ == "__main__":
    unittest.main()
