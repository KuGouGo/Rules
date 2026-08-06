import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _paths  # noqa: F401

TOOL = _paths.TOOLS_DIR / "normalize-ip-rules.py"


class NormalizeManifestTest(unittest.TestCase):
    def test_generate_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL),
                    "generate-manifest",
                    str(manifest),
                    "text",
                    "a.raw",
                    "a.cidr",
                    "html",
                    "b.raw",
                    "b.cidr",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            tasks = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(
                tasks,
                [
                    {"source_type": "text", "input_file": "a.raw", "output_file": "a.cidr"},
                    {
                        "source_type": "html",
                        "input_file": "b.raw",
                        "output_file": "b.cidr",
                    },
                ],
            )

    def test_invalid_triplets_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL),
                    "generate-manifest",
                    str(manifest),
                    "text",
                    "a.raw",
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("triplets", result.stderr)


if __name__ == "__main__":
    unittest.main()
