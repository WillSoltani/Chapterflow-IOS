#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/ci"))

import check_repository  # noqa: E402
import run_package_shard  # noqa: E402


class RepositoryCheckTests(unittest.TestCase):
    def test_markdown_fences(self) -> None:
        self.assertEqual(
            check_repository.check_markdown_fences(
                Path("ok.md"), "```swift\nlet value = 1\n```\n"
            ),
            [],
        )
        self.assertTrue(
            check_repository.check_markdown_fences(
                Path("bad.md"), "```swift\nlet value = 1\n"
            )
        )

    def test_local_markdown_links(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docs").mkdir()
            (root / "docs/source.md").write_text("source", encoding="utf-8")
            (root / "target.md").write_text("target", encoding="utf-8")
            self.assertEqual(
                check_repository.check_markdown_links(
                    root, "docs/source.md", "[target](../target.md)"
                ),
                [],
            )
            self.assertTrue(
                check_repository.check_markdown_links(
                    root, "docs/source.md", "[missing](../missing.md)"
                )
            )

            (root / "docs/source.md").write_text(
                "[target](../target.md)", encoding="utf-8"
            )
            incoming = check_repository.check_incoming_links_to_deleted(
                root,
                ["target.md"],
                ["docs/source.md"],
            )
            self.assertTrue(incoming)

    def test_added_secret_patterns(self) -> None:
        self.assertEqual(
            check_repository.check_added_secrets(
                "+API_KEY = YOUR_PLACEHOLDER_KEY\n"
            ),
            [],
        )
        fake_key = "AKIA" + "A" * 16
        failures = check_repository.check_added_secrets(f"+token={fake_key}\n")
        self.assertTrue(failures)
        disguised = check_repository.check_added_secrets(
            f"+token={fake_key}  # example placeholder\n"
        )
        self.assertTrue(disguised)
        temporary_key = "ASIA" + "A" * 16
        fine_grained = "github_" + "pat_" + "A" * 30
        self.assertTrue(
            check_repository.check_added_secrets(f"+token={temporary_key}\n")
        )
        self.assertTrue(
            check_repository.check_added_secrets(f"+token={fine_grained}\n")
        )

    def test_conflict_markers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bad.txt").write_text(
                "<<<<<<< HEAD\nleft\n=======\nright\n>>>>>>> branch\n",
                encoding="utf-8",
            )
            self.assertEqual(
                len(check_repository.check_conflict_markers(root, ["bad.txt"])),
                3,
            )

            (root / "plain.txt").write_text(
                "<<<<<<<\nleft\n=======\nright\n>>>>>>>\n",
                encoding="utf-8",
            )
            self.assertEqual(
                len(check_repository.check_conflict_markers(root, ["plain.txt"])),
                3,
            )

    def test_package_test_count_parser(self) -> None:
        self.assertEqual(
            run_package_shard.parse_test_count(
                "Executed 12 tests, with 0 failures\nTest run with 14 tests passed"
            ),
            14,
        )
        self.assertIsNone(run_package_shard.parse_test_count("no test summary"))

    def test_generated_artifacts_are_rejected(self) -> None:
        failures = check_repository.check_generated_artifacts(
            [
                "scripts/ci/__pycache__/plan.cpython-313.pyc",
                "DerivedData/build.log",
                "results/Test.xcresult/Info.plist",
            ]
        )
        self.assertEqual(len(failures), 3)
        self.assertEqual(
            check_repository.check_generated_artifacts(["scripts/ci/plan.py"]),
            [],
        )

    def test_deleted_generated_artifacts_are_not_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            deleted = "scripts/ci/__pycache__/deleted.pyc"
            present = "scripts/ci/__pycache__/present.pyc"
            broken_symlink = "scripts/ci/__pycache__/broken.pyc"
            (root / present).parent.mkdir(parents=True)
            (root / present).write_bytes(b"generated")
            (root / broken_symlink).symlink_to("missing-target")

            self.assertEqual(
                check_repository.check_present_generated_artifacts(root, [deleted]),
                [],
            )
            self.assertEqual(
                len(
                    check_repository.check_present_generated_artifacts(
                        root, [deleted, present, broken_symlink]
                    )
                ),
                2,
            )


if __name__ == "__main__":
    unittest.main()
