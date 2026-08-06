import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _paths  # noqa: F401

TOOL = _paths.TOOLS_DIR / "merge-domain-suffixes.py"


class MergeDomainSuffixesTest(unittest.TestCase):
    def test_merge_skips_covered_suffixes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            plain = root / "plain.list"
            plain.write_text(
                "example.com\nsub.example.com\nunrelated.org\nbad_domain.example\n",
                encoding="utf-8",
            )
            target = root / "target.list"
            target.write_text("DOMAIN-SUFFIX,example.com\n", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL),
                    str(plain),
                    str(target),
                    "--normalized-output",
                    str(root / "normalized.list"),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("candidate=3 invalid=1", result.stdout)
            self.assertIn("added=1 covered_or_duplicate=2", result.stdout)
            self.assertEqual(
                target.read_text(encoding="utf-8"),
                "DOMAIN-SUFFIX,example.com\nDOMAIN-SUFFIX,unrelated.org\n",
            )


if __name__ == "__main__":
    unittest.main()
