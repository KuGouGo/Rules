import tempfile
import unittest
from pathlib import Path

import _paths  # noqa: F401
import ipaddress
from ip_rules import ParsedIpRule, parse_classical_ip_file, write_plain_cidrs


class IpRulesTest(unittest.TestCase):
    def test_parse_classical_ip_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source.list"
            source.write_text(
                "IP-CIDR,192.0.2.0/24\n"
                "IP-CIDR6,2001:db8::/32\n"
                "# comment\n",
                encoding="utf-8",
            )
            rules, errors = parse_classical_ip_file(source, require_canonical=True)
            self.assertEqual(errors, [])
            self.assertEqual([rule.value for rule in rules], ["192.0.2.0/24", "2001:db8::/32"])

    def test_write_plain_cidrs(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "out.txt"
            write_plain_cidrs(
                [
                    ParsedIpRule("IP-CIDR", ipaddress.ip_network("192.0.2.0/24"), 1),
                    ParsedIpRule("IP-CIDR6", ipaddress.ip_network("2001:db8::/32"), 3),
                ],
                output,
            )
            self.assertEqual(
                output.read_text(encoding="utf-8"),
                "192.0.2.0/24\n2001:db8::/32\n",
            )


if __name__ == "__main__":
    unittest.main()
