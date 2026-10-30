import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _paths

TOOL = _paths.TOOLS_DIR / "verify-upstream-health.py"


def run_check(family: str, text: str) -> tuple[int, dict]:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        config = root / "upstreams.json"
        config.write_text(
            json.dumps(
                {
                    "ip": {
                        "sample": {
                            "health": {
                                "family": family,
                                "min_entries": 1,
                                "min_raw_bytes": 1,
                                "requirement": "required",
                            }
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        raw = root / "raw.txt"
        raw.write_text(text, encoding="utf-8")
        normalized = root / "normalized.txt"
        normalized.write_text(text, encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(TOOL), str(config), "ip", "sample", str(raw), str(normalized)],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode, json.loads(result.stdout)


class UpstreamHealthTests(unittest.TestCase):
    def test_ipv4_source_rejects_invalid_and_other_family(self):
        code, report = run_check("ipv4", "1.2.3.0/24\n2001:db8::/32\nnot-a-network\n")
        self.assertEqual(1, code)
        self.assertTrue(any("not IP networks" in error for error in report["errors"]))
        self.assertTrue(any("address family" in error for error in report["errors"]))

    def test_ipv4_source_accepts_only_ipv4(self):
        code, report = run_check("ipv4", "1.2.3.0/24\n203.0.113.0/24\n")
        self.assertEqual(0, code)
        self.assertEqual([], report["errors"])


if __name__ == "__main__":
    unittest.main()
