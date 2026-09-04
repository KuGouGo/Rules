import unittest
from collections import Counter

import _paths
from artifact_verifier import normalized_semantic_entries
from domain_rules import (
    ParsedDomainRule,
    compact_domain_rules,
    domain_rule_is_covered,
    domain_value_errors,
    normalize_domain_value,
)


def semantic_entries(rules):
    return normalized_semantic_entries(
        Counter((rule.kind, rule.value) for rule in rules)
    )


class DomainRulesTest(unittest.TestCase):
    def test_domain_rule_semantic_coverage(self):
        covering = {
            ("DOMAIN-SUFFIX", "example.com"),
            ("DOMAIN", "exact.example.net"),
            ("DOMAIN-KEYWORD", "keyword"),
        }
        self.assertTrue(domain_rule_is_covered("DOMAIN", "api.example.com", covering))
        self.assertTrue(domain_rule_is_covered("DOMAIN-SUFFIX", "cdn.example.com", covering))
        self.assertTrue(domain_rule_is_covered("DOMAIN", "exact.example.net", covering))
        self.assertTrue(domain_rule_is_covered("DOMAIN-KEYWORD", "keyword", covering))
        self.assertFalse(domain_rule_is_covered("DOMAIN", "api.notexample.com", covering))
        self.assertFalse(domain_rule_is_covered("DOMAIN-REGEX", "keyword", covering))

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

    def test_compact_preserves_semantic_coverage(self):
        rules = [
            ParsedDomainRule("DOMAIN-SUFFIX", "example.com", 1),
            ParsedDomainRule("DOMAIN", "api.example.com", 2),
            ParsedDomainRule("DOMAIN-SUFFIX", "cdn.example.com", 3),
            ParsedDomainRule("DOMAIN-SUFFIX", "deep.cdn.example.com", 4),
            ParsedDomainRule("DOMAIN-KEYWORD", "example", 5),
            ParsedDomainRule("DOMAIN-REGEX", "^foo", 6),
        ]
        compacted, removed = compact_domain_rules(rules)
        self.assertEqual(removed, 3)
        self.assertEqual(
            semantic_entries(compacted),
            semantic_entries(rules),
        )


if __name__ == "__main__":
    unittest.main()
