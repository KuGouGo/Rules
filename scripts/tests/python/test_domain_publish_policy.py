import json
import tempfile
import unittest
from pathlib import Path

import _paths
from domain_publish_policy import load_publish_policy, parse_publish_policy


def policy_data():
    return {
        "schema_version": 4,
        "default_profile": "common",
        "compatibility_replacements": {},
        "common": {
            "geographic_roots": ["geolocation-!cn"],
            "geolocation_not_cn": ["google"],
            "standalone": ["tor"],
        },
        "extended": {
            "geographic_roots": [],
            "geolocation_not_cn": ["category-media"],
            "standalone": "all",
        },
    }


class DomainPublishPolicyTest(unittest.TestCase):
    def test_shared_loader_exposes_inherited_tiers(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "policy.json"
            path.write_text(json.dumps(policy_data()), encoding="utf-8")
            policy = load_publish_policy(path)
        self.assertEqual(policy.geographic_roots("common"), {"geolocation-!cn"})
        self.assertEqual(
            policy.geographic_roots("extended"),
            {"geolocation-!cn"},
        )

    def test_rejects_extended_geographic_roots(self):
        data = policy_data()
        data["extended"]["geographic_roots"] = ["geolocation-cn"]
        with self.assertRaisesRegex(ValueError, "geographic roots"):
            parse_publish_policy(data)

    def test_rejects_unsorted_lists(self):
        data = policy_data()
        data["common"]["standalone"] = ["tor", "alpha"]
        with self.assertRaisesRegex(ValueError, "must be sorted"):
            parse_publish_policy(data)


if __name__ == "__main__":
    unittest.main()
