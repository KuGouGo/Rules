import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _paths  # noqa: F401

TOOL = _paths.TOOLS_DIR / "assert-domain-derivatives.py"


def build_manifest(required=True, geolocation_pair=True):
    lists = [
        {"name": name, "kind": "attr", "attr": attr}
        for name, attr in {
            "alibaba@!cn": "!cn",
            "apple@ads": "ads",
            "apple@cn": "cn",
            "baidu@ads": "ads",
            "category-games-!cn@cn": "cn",
            "cn": "cn",
            "geolocation-!cn": "!cn",
            "geolocation-!cn@cn": "cn",
            "geolocation-cn": "cn",
            "google@cn": "cn",
            "speedtest@ads": "ads",
            "tld-!cn": "!cn",
            "tld-cn": "cn",
        }.items()
    ]
    lists += [
        {"name": f"attr-{index}", "kind": "attr", "attr": "cn"}
        for index in range(350)
    ]
    lists += [
        {"name": f"not-cn-{index}", "kind": "attr", "attr": "!cn"}
        for index in range(40)
    ]
    lists += [
        {"name": f"ads-{index}", "kind": "attr", "attr": "ads"}
        for index in range(120)
    ]
    lists += [{"name": f"regional-{index}", "kind": "regional"} for index in range(50)]
    if not required:
        lists = [entry for entry in lists if entry["name"] != "cn"]
    region_pairs = {"geolocation": ["cn", "!cn"]} if geolocation_pair else {}
    return {"lists": lists, "region_pairs": region_pairs}


class AssertDomainDerivativesTest(unittest.TestCase):
    def run_tool(self, manifest_path):
        return subprocess.run(
            [
                sys.executable,
                str(TOOL),
                str(manifest_path),
                "300",
                "100",
                "30",
                "100",
                "40",
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
            self.assertIn("missing geolocation -cn/-!cn regional pair", result.stderr)


if __name__ == "__main__":
    unittest.main()
