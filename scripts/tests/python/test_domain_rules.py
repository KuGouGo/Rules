import unittest

import _paths  # noqa: F401
from domain_rules import (
    ParsedDomainRule,
    compact_domain_rules,
    domain_value_errors,
    normalize_domain_value,
)


class DomainRulesTest(unittest.TestCase):
    def test_normalize_domain_value(self):
        self.assertEqual(
            normalize_domain_value("DOMAIN", "Example.COM."),
            "example.com",
        )
        self.assertEqual(
            normalize_domain_value("DOMAIN-SUFFIX", "EXAMPLE.com"),
            "example.com",
        )
        self.assertEqual(
            normalize_domain_value("DOMAIN-KEYWORD", "OpenAI"),
            "openai",
        )

    def test_domain_value_errors(self):
        self.assertEqual(
            domain_value_errors("DOMAIN", "ok.example", require_canonical=True),
            [],
        )
        self.assertTrue(
            domain_value_errors(
                "DOMAIN",
                "bad_label.example",
                require_canonical=True,
            )
        )
        self.assertTrue(
            domain_value_errors("DOMAIN", "UPPER.example", require_canonical=True)
        )
        self.assertTrue(
            domain_value_errors("DOMAIN", "example", require_canonical=True)
        )

    def test_compact_domain_rules(self):
        rules = [
            ParsedDomainRule("DOMAIN", "sub.example.com", 1),
            ParsedDomainRule("DOMAIN-SUFFIX", "example.com", 2),
        ]
        compacted, removed = compact_domain_rules(rules)
        self.assertEqual(removed, 1)
        self.assertEqual([rule.text for rule in compacted], ["DOMAIN-SUFFIX,example.com"])


if __name__ == "__main__":
    unittest.main()
