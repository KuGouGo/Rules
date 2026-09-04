import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _paths

TOOL = _paths.TOOLS_DIR / "upstream_summary.py"


class UpstreamSummaryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.config = self.root / "upstreams.json"
        self.config.write_text(
            json.dumps({"domain": {"fixture": {"kind": "text", "trust": "community"}}}),
            encoding="utf-8",
        )
        self.summary = self.root / "summary.jsonl"
        self.raw = self.root / "raw.list"
        self.raw.write_text("DOMAIN,example.com\n# comment\n", encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def test_record_and_finalize(self):
        result = subprocess.run(
            [
                sys.executable,
                str(TOOL),
                "record",
                str(self.config),
                str(self.summary),
                "domain",
                "fixture",
                "ok",
                "https://example.com/raw",
                str(self.raw),
                "",
                "0",
                "",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.summary.read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(lines), 1)
        payload = json.loads(lines[0])
        self.assertEqual(payload["name"], "fixture")
        self.assertEqual(payload["kind"], "text")
        self.assertEqual(payload["raw"]["bytes"], self.raw.stat().st_size)
        self.assertEqual(payload["raw"]["entries"], 1)
        self.assertEqual(
            payload["raw"]["sha256"],
            hashlib.sha256(self.raw.read_bytes()).hexdigest(),
        )

        json_output = self.root / "summary.json"
        finalize = subprocess.run(
            [
                sys.executable,
                str(TOOL),
                "finalize",
                str(self.summary),
                str(json_output),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(finalize.returncode, 0, finalize.stderr)
        finalized = json.loads(json_output.read_text(encoding="utf-8"))
        self.assertEqual(len(finalized), 1)
        self.assertEqual(finalized[0]["name"], "fixture")


if __name__ == "__main__":
    unittest.main()
