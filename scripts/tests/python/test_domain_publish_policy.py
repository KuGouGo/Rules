import json
import tempfile
import unittest
from pathlib import Path

import _paths
from domain_publish_policy import load_publish_policy, parse_publish_policy


def policy_data():
    return {
        "schema_version": 5,
        "compatibility_replacements": {},
        "geographic_roots": ["geolocation-!cn"],
        "geolocation_not_cn": ["google"],
        "standalone": ["tor"],
    }


class DomainPublishPolicyTest(unittest.TestCase):
    def test_loader_exposes_publication_tiers(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "policy.json"
            path.write_text(json.dumps(policy_data()), encoding="utf-8")
            policy = load_publish_policy(path)
        self.assertEqual(policy.geographic_roots, {"geolocation-!cn"})
        self.assertEqual(policy.geolocation_not_cn, {"google"})
        self.assertEqual(policy.standalone, {"tor"})

    def test_rejects_extra_geographic_roots(self):
        data = policy_data()
        data["geographic_roots"] = ["geolocation-!cn", "geolocation-cn"]
        with self.assertRaisesRegex(ValueError, "geographic_roots"):
            parse_publish_policy(data)

    def test_rejects_unsorted_lists(self):
        data = policy_data()
        data["standalone"] = ["tor", "alpha"]
        with self.assertRaisesRegex(ValueError, "must be sorted"):
            parse_publish_policy(data)

    def test_rejects_chained_compatibility_replacements(self):
        data = policy_data()
        data["compatibility_replacements"] = {
            "a-list": "b-list",
            "b-list": "c-list",
        }
        with self.assertRaisesRegex(ValueError, "must not be chained"):
            parse_publish_policy(data)


if __name__ == "__main__":
    unittest.main()
