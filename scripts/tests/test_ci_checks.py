#!/usr/bin/env python3

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/ci"))

import check_repository  # noqa: E402
import run_package_shard  # noqa: E402


class WorkflowSecurityTests(unittest.TestCase):
    DEVELOPMENT_WORKFLOWS = (
        ".github/workflows/pr-v2.yml",
        ".github/workflows/contract-drift.yml",
        ".github/workflows/pr.yml",
    )
    IMMUTABLE_ACTION = re.compile(r"^[0-9a-f]{40}$")
    VERSION_COMMENT = re.compile(r"^v[0-9]+(?:\.[0-9]+){1,2}$")

    @classmethod
    def setUpClass(cls) -> None:
        cls.sources = {
            path: (ROOT / path).read_text(encoding="utf-8")
            for path in cls.DEVELOPMENT_WORKFLOWS
        }

    @staticmethod
    def checkout_step_blocks(source: str) -> list[str]:
        lines = source.splitlines()
        blocks: list[str] = []
        for index, line in enumerate(lines):
            if "uses: actions/checkout@" not in line:
                continue
            start = index
            step_indent = None
            while start >= 0:
                match = re.match(r"^(\s*)-\s+(?:name|uses):", lines[start])
                if match:
                    step_indent = len(match.group(1))
                    break
                start -= 1
            if step_indent is None:
                raise AssertionError("checkout is not inside a recognizable workflow step")
            end = start + 1
            while end < len(lines):
                match = re.match(r"^(\s*)-\s+(?:name|uses):", lines[end])
                if match and len(match.group(1)) == step_indent:
                    break
                end += 1
            blocks.append("\n".join(lines[start:end]))
        return blocks

    def test_fork_and_same_repo_threat_models(self) -> None:
        self.assertEqual(
            set(self.sources),
            {
                ".github/workflows/pr-v2.yml",
                ".github/workflows/contract-drift.yml",
                ".github/workflows/pr.yml",
            },
        )
        combined = "\n".join(self.sources.values())
        for path, source in self.sources.items():
            with self.subTest(path=path, control="permissions"):
                self.assertRegex(source, r"(?m)^permissions:\n  contents: read$")
                self.assertNotRegex(source, r"(?m)^\s*[a-z-]+:\s+write$")
                self.assertNotIn("write-all", source)
            with self.subTest(path=path, control="token-and-runner"):
                self.assertNotIn("secrets.", source)
                self.assertNotIn("self-hosted", source)
                self.assertNotRegex(source, r"(?m)^\s*runs-on:\s*\[.*self-hosted")
            with self.subTest(path=path, control="privileged-trigger"):
                for trigger in (
                    "pull_request_target:",
                    "workflow_run:",
                    "issue_comment:",
                    "repository_dispatch:",
                ):
                    self.assertNotIn(trigger, source)
            with self.subTest(path=path, control="expression-injection"):
                self.assertNotRegex(
                    source,
                    r"\$\{\{\s*github\.event\.(?:pull_request\.)?"
                    r"(?:title|body|head\.label|head\.ref)\s*\}\}",
                )

        required = self.sources[".github/workflows/pr-v2.yml"]
        self.assertRegex(
            required,
            r"types: \[opened, synchronize, reopened, labeled, unlabeled\]",
        )
        self.assertIn("merge_group:\n    types: [checks_requested]", required)
        pull_request_section = required.split("  pull_request:\n", 1)[1].split(
            "  push:\n", 1
        )[0]
        self.assertNotIn("paths:", pull_request_section)
        self.assertIn("'CI / Required'", required)
        self.assertIn(
            "needs: [plan, contract-semantics, lint, package-tests, app-and-ui]",
            required,
        )
        self.assertIn("if: ${{ always() }}", required)
        self.assertIn("github.event_name != 'pull_request'", required)
        self.assertIn("github.event_name != 'merge_group'", required)
        self.assertIn("actions/cache/restore@", required)
        self.assertIn("actions/cache/save@", required)
        self.assertNotIn("actions/cache@", required)
        self.assertNotIn("actions/download-artifact", combined)
        self.assertEqual(combined.count("if-no-files-found: error"), 4)
        for diagnostic in (
            "ci-plan-diagnostic.txt",
            "lint-diagnostic.txt",
            "package-diagnostic-${SHARD}.txt",
            "app-ui-diagnostic.txt",
        ):
            self.assertIn(diagnostic, required)
        for release_coupling in ("release.yml", "TestFlight", "App Store", "ASC_KEY_ID"):
            self.assertNotIn(release_coupling, combined)

        legacy = self.sources[".github/workflows/pr.yml"]
        self.assertIn("on:\n  workflow_dispatch:", legacy)
        self.assertNotIn("pull_request:", legacy)

    def test_action_refs_and_credentials(self) -> None:
        external_actions = 0
        checkouts = 0
        for path, source in self.sources.items():
            for line_number, line in enumerate(source.splitlines(), start=1):
                match = re.search(r"\buses:\s*(\S+)(?:\s+#\s*(\S+))?\s*$", line)
                if not match:
                    continue
                action, comment = match.groups()
                if action.startswith("./"):
                    continue
                external_actions += 1
                self.assertIn("@", action, f"{path}:{line_number}")
                _, reference = action.rsplit("@", 1)
                self.assertRegex(reference, self.IMMUTABLE_ACTION, f"{path}:{line_number}")
                self.assertIsNotNone(comment, f"missing version comment at {path}:{line_number}")
                self.assertRegex(
                    comment or "", self.VERSION_COMMENT, f"{path}:{line_number}"
                )
            blocks = self.checkout_step_blocks(source)
            checkouts += len(blocks)
            for block in blocks:
                self.assertIn("persist-credentials: false", block, path)

        self.assertGreater(external_actions, 0)
        self.assertGreater(checkouts, 0)


class RepositoryCheckTests(unittest.TestCase):
    def initialize_git_repository(self, root: Path) -> str:
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "ci-tests@example.invalid"],
            cwd=root,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "CI Tests"],
            cwd=root,
            check=True,
        )
        (root / "README.md").write_text("# Fixture repository\n", encoding="utf-8")
        return self.commit_all(root, "baseline")

    def commit_all(self, root: Path, message: str) -> str:
        subprocess.run(["git", "add", "-A"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", message], cwd=root, check=True)
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.strip()

    def run_real_git_checks(self, root: Path, base: str, head: str) -> None:
        diff = check_repository.ci_plan.resolve_git_diff(root, base, head)
        self.assertFalse(diff.failed)
        check_repository.run_checks(root, diff.paths, diff.merge_base, head)

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
        self.assertTrue(
            check_repository.check_markdown_fences(
                Path("bad-close.md"),
                "```swift\nlet value = 1\n```not-a-valid-close\n",
            )
        )
        self.assertTrue(
            check_repository.check_markdown_fences(
                Path("bad-tilde-close.md"),
                "~~~swift\nlet value = 1\n~~~not-a-valid-close\n",
            )
        )
        self.assertTrue(
            check_repository.check_markdown_fences(
                Path("nested-list.md"),
                "- item\n\n    ```swift\n    let value = 1\n",
            )
        )
        self.assertEqual(
            check_repository.check_markdown_fences(
                Path("long-close.md"), "```swift\nlet value = 1\n````\n"
            ),
            [],
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
            self.assertEqual(
                check_repository.check_markdown_links(
                    root,
                    "docs/source.md",
                    "[target][id]\n\n[id]: <../target.md> \"Target\"\n",
                ),
                [],
            )
            self.assertTrue(
                check_repository.check_markdown_links(
                    root,
                    "docs/source.md",
                    "[missing][id]\n\n[id]: ../missing.md\n",
                )
            )
            self.assertTrue(
                check_repository.check_markdown_links(
                    root,
                    "docs/source.md",
                    "[missing][id]\n\n[id]:\n  ../missing.md\n",
                )
            )

            (root / "docs/source.md").write_text(
                "[target][id]\n\n[id]:\n  ../target.md\n", encoding="utf-8"
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
                "artifacts/ChapterFlow.ipa",
                "artifacts/ChapterFlow.xcarchive/Info.plist",
                "artifacts/ChapterFlow.app.dSYM/Contents/Info.plist",
                "artifacts/ChapterFlow.dSYM.zip",
                "artifacts/ChapterFlow.app/Info.plist",
            ]
        )
        self.assertEqual(len(failures), 8)
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

    def test_real_git_reference_link_regressions_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = self.initialize_git_repository(root)
            (root / "docs").mkdir()
            (root / "docs/source.md").write_text(
                "[missing][id]\n\n[id]:\n  ../missing.md\n",
                encoding="utf-8",
            )
            head = self.commit_all(root, "add broken reference link")
            with self.assertRaises(check_repository.CheckFailure):
                self.run_real_git_checks(root, base, head)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.initialize_git_repository(root)
            (root / "docs").mkdir()
            (root / "target.md").write_text("target\n", encoding="utf-8")
            (root / "docs/source.md").write_text(
                "[target][id]\n\n[id]:\n  ../target.md\n",
                encoding="utf-8",
            )
            base = self.commit_all(root, "add reference target")
            (root / "target.md").unlink()
            head = self.commit_all(root, "delete reference target")
            with self.assertRaises(check_repository.CheckFailure):
                self.run_real_git_checks(root, base, head)

    def test_real_git_malformed_fence_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = self.initialize_git_repository(root)
            (root / "bad.md").write_text(
                "```swift\nlet value = 1\n```not-a-valid-close\n",
                encoding="utf-8",
            )
            head = self.commit_all(root, "add malformed fence")
            with self.assertRaises(check_repository.CheckFailure):
                self.run_real_git_checks(root, base, head)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = self.initialize_git_repository(root)
            (root / "nested-list.md").write_text(
                "- item\n\n    ```swift\n    let value = 1\n",
                encoding="utf-8",
            )
            head = self.commit_all(root, "add unclosed nested-list fence")
            with self.assertRaises(check_repository.CheckFailure):
                self.run_real_git_checks(root, base, head)

    def test_real_git_xcode_artifacts_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = self.initialize_git_repository(root)
            artifacts = root / "artifacts"
            (artifacts / "ChapterFlow.xcarchive").mkdir(parents=True)
            (artifacts / "ChapterFlow.ipa").write_bytes(b"ipa")
            (artifacts / "ChapterFlow.xcarchive/Info.plist").write_text(
                "archive\n", encoding="utf-8"
            )
            head = self.commit_all(root, "add generated Xcode artifacts")
            with self.assertRaises(check_repository.CheckFailure):
                self.run_real_git_checks(root, base, head)


if __name__ == "__main__":
    unittest.main()
