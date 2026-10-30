import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import _paths

SPEC = importlib.util.spec_from_file_location(
    "update_dependencies",
    _paths.TOOLS_DIR / "update-dependencies.py",
)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


class UpdateDependenciesTests(unittest.TestCase):
    def test_action_lookup_failure_keeps_files_unwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            common = root / "scripts/lib/common.sh"
            common.parent.mkdir(parents=True)
            original_common = 'SING_BOX_VERSION="1.0.0"\nMIHOMO_VERSION="2.0.0"\n'
            common.write_text(original_common, encoding="utf-8")
            workflow = root / "build.yml"
            original_workflow = (
                "uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7.0.0\n"
            )
            workflow.write_text(original_workflow, encoding="utf-8")

            with mock.patch.object(updater, "ROOT", root), \
                mock.patch.object(updater, "ACTION_FILES", [workflow]), \
                mock.patch.object(updater, "latest_release", return_value="9.9.9"), \
                mock.patch.object(
                    updater,
                    "latest_tag_in_major",
                    side_effect=RuntimeError("lookup failed"),
                ):
                with self.assertRaisesRegex(RuntimeError, "lookup failed"):
                    updater.main()

            self.assertEqual(original_common, common.read_text(encoding="utf-8"))
            self.assertEqual(original_workflow, workflow.read_text(encoding="utf-8"))

    def test_action_pins_update_only_after_every_lookup(self):
        with tempfile.TemporaryDirectory() as temp:
            workflow = Path(temp) / "build.yml"
            workflow.write_text(
                "uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7.0.0\n"
                "uses: actions/cache@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb # v6.0.0\n",
                encoding="utf-8",
            )
            resolved = {
                "actions/checkout": ("v7.0.1", "c" * 40),
                "actions/cache": ("v6.1.0", "d" * 40),
            }

            with mock.patch.object(updater, "ACTION_FILES", [workflow]), \
                mock.patch.object(updater, "TRACKED_ACTIONS", {"actions/checkout": 7, "actions/cache": 6}), \
                mock.patch.object(
                    updater,
                    "latest_tag_in_major",
                    side_effect=lambda repo, major: resolved[repo],
                ):
                changed = updater.update_actions()

            text = workflow.read_text(encoding="utf-8")
            self.assertIn(f"uses: actions/checkout@{'c' * 40} # v7.0.1", text)
            self.assertIn(f"uses: actions/cache@{'d' * 40} # v6.1.0", text)
            self.assertEqual(
                ["action actions/checkout -> v7.0.1", "action actions/cache -> v6.1.0"],
                changed,
            )

    def test_workflow_pin_is_refused_and_nothing_is_written(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workflow = root / ".github/workflows/build.yml"
            action = root / ".github/actions/setup/action.yml"
            workflow.parent.mkdir(parents=True)
            action.parent.mkdir(parents=True)
            original_workflow = (
                "uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7.0.0\n"
            )
            original_action = (
                "uses: actions/cache@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb # v6.0.0\n"
            )
            workflow.write_text(original_workflow, encoding="utf-8")
            action.write_text(original_action, encoding="utf-8")

            with mock.patch.object(updater, "ACTION_FILES", [workflow, action]), \
                mock.patch.object(
                    updater,
                    "TRACKED_ACTIONS",
                    {"actions/checkout": 7, "actions/cache": 6},
                ), \
                mock.patch.object(
                    updater,
                    "latest_tag_in_major",
                    side_effect=lambda repo, major: {
                        "actions/checkout": ("v7.0.1", "c" * 40),
                        "actions/cache": ("v6.1.0", "d" * 40),
                    }[repo],
                ):
                with self.assertRaisesRegex(RuntimeError, "workflow file"):
                    updater.update_actions()

            # One blocked file must not leave the other action half-updated.
            self.assertEqual(original_workflow, workflow.read_text(encoding="utf-8"))
            self.assertEqual(original_action, action.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
