import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _paths

from check_ip_cidr_validity import check_dir

TOOL = _paths.TOOLS_DIR / "check_ip_cidr_validity.py"


class CheckIpCidrValidityTest(unittest.TestCase):
    def test_valid_public_dir_has_no_violations(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "telegram.list").write_text(
                "IP-CIDR,91.108.4.0/22,no-resolve\n"
                "IP-CIDR6,2001:b28:f23c::/48,no-resolve\n",
                encoding="utf-8",
            )
            self.assertEqual(check_dir(directory, "ip-valid"), [])

    def test_private_list_allows_non_global_cidrs(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "private.list").write_text(
                "IP-CIDR,10.0.0.0/8,no-resolve\nIP-CIDR6,fc00::/7,no-resolve\n",
                encoding="utf-8",
            )
            self.assertEqual(check_dir(directory, "ip-valid"), [])

    def test_non_global_cidr_outside_private_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "example.list").write_text(
                "IP-CIDR,10.0.0.0/8,no-resolve\n", encoding="utf-8"
            )
            violations = check_dir(directory, "ip-valid")
            self.assertEqual(len(violations), 1)
            self.assertIn("non-global CIDR outside private.list: 10.0.0.0/8", violations[0])

    def test_address_family_mismatch_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "example.list").write_text(
                "IP-CIDR6,192.0.2.0/24,no-resolve\n", encoding="utf-8"
            )
            violations = check_dir(directory, "ip-valid")
            self.assertEqual(len(violations), 2)
            self.assertIn("IP-CIDR6 requires IPv6, got 192.0.2.0/24", violations[0])
            self.assertIn("non-global CIDR outside private.list", violations[1])

    def test_invalid_and_missing_cidr_values_are_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "example.list").write_text(
                "IP-CIDR\nIP-CIDR,not-a-cidr\n", encoding="utf-8"
            )
            violations = check_dir(directory, "ip-valid")
            self.assertEqual(len(violations), 2)
            self.assertIn("missing CIDR value", violations[0])
            self.assertIn("invalid CIDR 'not-a-cidr'", violations[1])

    def test_missing_directory_is_not_a_violation(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(check_dir(Path(tmp) / "missing", "label"), [])

    def test_cli_reports_guard_header_and_exits_nonzero(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "example.list").write_text(
                "IP-CIDR,10.0.0.0/8,no-resolve\n", encoding="utf-8"
            )
            result = subprocess.run(
                [sys.executable, str(TOOL), str(directory), "ip-valid"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("IP CIDR validity guard failed:", result.stderr)
            self.assertIn("non-global CIDR outside private.list: 10.0.0.0/8", result.stderr)

    def test_cli_passes_for_valid_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "telegram.list").write_text(
                "IP-CIDR,91.108.4.0/22,no-resolve\n", encoding="utf-8"
            )
            result = subprocess.run(
                [sys.executable, str(TOOL), str(directory), "ip-valid"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
