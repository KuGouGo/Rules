import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _paths

TOOL = _paths.TOOLS_DIR / "discover-asn-groups.py"
CONFIG = _paths.TOOLS_DIR.parents[1] / "config" / "upstreams.json"


def write_tsv(path: Path, rows: list[tuple[str, str, str, str, str]]) -> None:
    path.write_text(
        "".join("\t".join(row) + "\n" for row in rows),
        encoding="utf-8",
    )


def run(config: dict, snapshots: list[list[tuple[str, str, str, str, str]]]):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config_path = root / "upstreams.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        snapshot_paths = []
        for index, rows in enumerate(snapshots):
            snapshot = root / f"snapshot-{index}.tsv"
            write_tsv(snapshot, rows)
            snapshot_paths.append(snapshot)
        output = root / "effective.json"
        result = subprocess.run(
            [sys.executable, str(TOOL), str(config_path), *map(str, snapshot_paths), str(output)],
            capture_output=True,
            text=True,
        )
        payload = json.loads(output.read_text(encoding="utf-8")) if output.exists() else None
        return result, payload


BASE_CONFIG = {
    "asn_groups": {"apple": [714], "example": [65000]},
    "asn_discovery": {
        "apple": {
            "include": ["^APPLE-AS", "^Apple Inc\\."],
            "exclude": ["HOSTMYAPPLE"],
            "max_auto_add": 2,
        },
        "example": {
            "include": ["EXAMPLE-CORP"],
            "exclude": ["EXAMPLE-RESELLER"],
            "max_auto_add": 1,
        },
    },
}


class DiscoverAsnGroupsTest(unittest.TestCase):
    def test_discovers_new_asn_matching_include(self):
        snapshots = [
            [
                ("10.0.0.0", "10.0.0.255", "714", "US", "APPLE-AS - Apple Inc."),
                ("10.1.0.0", "10.1.0.255", "64999", "US", "APPLE-AS2 - Apple Inc."),
                ("10.2.0.0", "10.2.0.255", "65000", "US", "EXAMPLE-CORP"),
            ]
        ]
        result, payload = run(BASE_CONFIG, snapshots)
        self.assertEqual(result.returncode, 0, result.stderr)
        apple = payload["groups"]["apple"]
        self.assertEqual(apple["seed"], [714])
        self.assertEqual(apple["discovered"], [64999])
        self.assertEqual(apple["effective"], [714, 64999])
        self.assertEqual(payload["groups"]["example"]["effective"], [65000])

    def test_exclude_pattern_blocks_samesame_name_impostor(self):
        snapshots = [
            [
                ("10.0.0.0", "10.0.0.255", "402302", "US", "HOSTMYAPPLE - HostMyApple Inc."),
            ]
        ]
        result, payload = run(BASE_CONFIG, snapshots)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["groups"]["apple"]["discovered"], [])

    def test_unrouted_rows_are_ignored(self):
        snapshots = [
            [
                ("10.0.0.0", "10.0.0.255", "0", "None", "Not routed"),
                ("10.1.0.0", "10.1.0.255", "64999", "US", "APPLE-AS NEW"),
            ]
        ]
        result, payload = run(BASE_CONFIG, snapshots)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["groups"]["apple"]["discovered"], [64999])

    def test_over_cap_candidates_fail_closed(self):
        snapshots = [
            [
                ("10.1.0.0", "10.1.0.255", "64998", "US", "APPLE-AS A"),
                ("10.2.0.0", "10.2.0.255", "64999", "US", "APPLE-AS B"),
                ("10.3.0.0", "10.3.0.255", "64997", "US", "APPLE-AS C"),
            ]
        ]
        result, payload = run(BASE_CONFIG, snapshots)
        self.assertEqual(result.returncode, 1)
        self.assertIn("exceed max_auto_add=2", result.stderr)
        self.assertIn("refusing to auto-apply", result.stderr)

    def test_unknown_discovery_group_fails(self):
        config = {
            "asn_groups": {"example": [65000]},
            "asn_discovery": {
                "ghost": {"include": ["X"], "exclude": [], "max_auto_add": 1},
            },
        }
        result, _ = run(config, [[("10.0.0.0", "10.0.0.255", "65000", "US", "EXAMPLE-CORP")]])
        self.assertEqual(result.returncode, 1)
        self.assertIn("unknown groups: ghost", result.stderr)

    def test_group_without_discovery_rules_keeps_seed(self):
        config = {"asn_groups": {"example": [65000]}}
        result, payload = run(config, [[("10.0.0.0", "10.0.0.255", "65000", "US", "EXAMPLE-CORP")]])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["groups"]["example"]["effective"], [65000])

    def test_real_config_discovers_nothing_on_fixture_snapshots(self):
        snapshots = [[("10.0.0.0", "10.0.0.255", "714", "US", "APPLE-ENGINEERING")]]
        with tempfile.TemporaryDirectory() as tmp:
            snapshot = Path(tmp) / "s.tsv"
            write_tsv(snapshot, snapshots[0])
            output = Path(tmp) / "effective.json"
            result = subprocess.run(
                [sys.executable, str(TOOL), str(CONFIG), str(snapshot), str(output)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(payload["groups"]["apple"]["discovered"], [])
            self.assertEqual(payload["groups"]["google"]["discovered"], [])
            self.assertEqual(payload["groups"]["telegram"]["discovered"], [])


if __name__ == "__main__":
    unittest.main()
