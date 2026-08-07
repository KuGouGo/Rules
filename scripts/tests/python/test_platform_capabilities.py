import unittest

import _paths  # noqa: F401
from platform_capabilities import load_platform_capabilities


class PlatformCapabilitiesTest(unittest.TestCase):
    def test_required_platforms_present(self):
        platforms = load_platform_capabilities().platforms
        self.assertTrue({"surge", "quanx", "egern", "sing-box", "mihomo"} <= set(platforms))

    def test_domain_capabilities_shape(self):
        registry = load_platform_capabilities()
        surge = registry.platforms["surge"]
        self.assertTrue(surge.domain)
        self.assertTrue(surge.ip)


if __name__ == "__main__":
    unittest.main()
