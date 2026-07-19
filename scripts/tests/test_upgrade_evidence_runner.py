#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
RUNNER_PATH = ROOT / "scripts/validation/run_evidence.py"
SPEC = importlib.util.spec_from_file_location("run_evidence", RUNNER_PATH)
assert SPEC is not None and SPEC.loader is not None
run_evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(run_evidence)


class UpgradeEvidenceRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.evidence = self.root / "evidence"
        self.locks = self.root / "locks"
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True)
        subprocess.run(
            ["git", "config", "user.email", "evidence-tests@example.invalid"],
            cwd=self.repo,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Evidence Tests"],
            cwd=self.repo,
            check=True,
        )
        (self.repo / "README.md").write_text("fixture\n", encoding="utf-8")
        self.initial_head = self.commit_all("baseline")
        self.attempt_repo_heads: dict[tuple[str, str], list[str]] = {}

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def commit_all(self, message: str) -> str:
        subprocess.run(["git", "add", "-A"], cwd=self.repo, check=True)
        subprocess.run(["git", "commit", "-qm", message], cwd=self.repo, check=True)
        return self.git("rev-parse", "HEAD")

    def git(self, *arguments: str) -> str:
        return subprocess.run(
            ["git", *arguments],
            cwd=self.repo,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.strip()

    def make_backend_repository(self, name: str = "backend") -> tuple[Path, str]:
        backend = self.root / name
        backend.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=backend, check=True)
        subprocess.run(
            ["git", "config", "user.email", "backend-tests@example.invalid"],
            cwd=backend,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Backend Tests"],
            cwd=backend,
            check=True,
        )
        subprocess.run(
            [
                "git",
                "remote",
                "add",
                "origin",
                "https://github.com/WillSoltani/ChapterFlow.git",
            ],
            cwd=backend,
            check=True,
        )
        (backend / "README.md").write_text("backend\n", encoding="utf-8")
        subprocess.run(["git", "add", "README.md"], cwd=backend, check=True)
        subprocess.run(
            ["git", "commit", "-qm", "backend baseline"],
            cwd=backend,
            check=True,
        )
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=backend,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.strip()
        return backend, head

    def attempt_root(
        self,
        attempt: str,
        *,
        head: str | None = None,
        package: str = "WP-TEST-01",
        repo_heads: list[str] | None = None,
    ) -> Path:
        declared = repo_heads or self.attempt_repo_heads.get((package, attempt))
        repositories, digest = run_evidence.canonicalize_repo_heads(
            declared or [f"ios={head or self.git('rev-parse', 'HEAD')}"]
        )
        self.assertIn("ios", {item["repository"] for item in repositories})
        return self.evidence / package / digest / "attempts" / attempt

    def run_cli(
        self,
        attempt: str,
        artifact: str,
        *,
        options: list[str] | None = None,
        command: list[str] | None = None,
        head: str | None = None,
        package: str = "WP-TEST-01",
        assertion: str = "TEST-ASSERTION",
        root: Path | None = None,
        lock_root: Path | None = None,
        environment: dict[str, str] | None = None,
        repo_heads: list[str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        candidate = head or self.git("rev-parse", "HEAD")
        declared_heads = [f"ios={candidate}", *(repo_heads or [])]
        recorded_heads = list(declared_heads)
        recovery_mode = bool(
            options
            and any(
                item in options
                for item in (
                    "--build-recovery-inventory",
                    "--classify-recovery-inventory",
                )
            )
        )
        environment_backend_head = (environment or {}).get(
            "CHAPTERFLOW_BACKEND_HEAD"
        )
        if (
            recovery_mode
            and environment_backend_head
            and not any(item.startswith("backend=") for item in recorded_heads)
        ):
            recorded_heads.append(f"backend={environment_backend_head}")
        self.attempt_repo_heads[(package, attempt)] = recorded_heads
        invocation = [
            sys.executable,
            "-B",
            str(RUNNER_PATH),
            "--root",
            str(root or self.evidence),
            "--package",
            package,
            "--assertion",
            assertion,
            "--attempt",
            attempt,
            *sum((["--repo-head", value] for value in declared_heads), []),
            "--cwd",
            str(self.repo),
            "--artifact",
            artifact,
            "--owner",
            "owner-1",
            "--lock-root",
            str(lock_root or self.locks),
            *(options or []),
        ]
        if command is not None:
            invocation.extend(["--", *command])
        env = os.environ.copy()
        env.update(environment or {})
        return subprocess.run(
            invocation,
            cwd=self.repo,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )

    def manifest(self, attempt: str, **kwargs: object) -> dict[str, object]:
        return json.loads(
            (self.attempt_root(attempt, **kwargs) / "manifest.json").read_text(
                encoding="utf-8"
            )
        )

    def test_head_set_is_sorted_and_rejects_ambiguous_values(self) -> None:
        first = "a" * 40
        second = "b" * 40
        ordered, digest = run_evidence.canonicalize_repo_heads(
            [f"ios={second}", f"backend={first}"]
        )
        self.assertEqual(
            ordered,
            [
                {"repository": "backend", "head": first},
                {"repository": "ios", "head": second},
            ],
        )
        reverse, reverse_digest = run_evidence.canonicalize_repo_heads(
            [f"backend={first}", f"ios={second}"]
        )
        self.assertEqual(reverse, ordered)
        self.assertEqual(reverse_digest, digest)
        with self.assertRaises(run_evidence.EvidenceError):
            run_evidence.canonicalize_repo_heads([f"ios={first}", f"ios={second}"])
        with self.assertRaises(run_evidence.EvidenceError):
            run_evidence.canonicalize_repo_heads(["ios=abc123"])

    def test_rewrites_plain_and_key_value_results_paths_externally(self) -> None:
        script = (
            "from pathlib import Path; import sys; "
            "value=sys.argv[1].split('=',1)[-1]; Path(value).write_text('ok')"
        )
        result = self.run_cli(
            "attempt-rewrite",
            "results/out.txt",
            command=[sys.executable, "-c", script, "--output=results/out.txt"],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        attempt = self.attempt_root("attempt-rewrite")
        self.assertEqual((attempt / "results/out.txt").read_text(), "ok")
        self.assertFalse((self.repo / "results").exists())
        manifest = self.manifest("attempt-rewrite")
        rewrites = manifest["result"]["command"]["rewrites"]
        self.assertEqual(rewrites[0]["kind"], "output")

    def test_rejects_bare_inputs_output_refs_and_shell_embedded_paths(self) -> None:
        bare_input = self.run_cli(
            "bare-input",
            "results/out.txt",
            command=[
                sys.executable,
                "-c",
                "print('must not run')",
                "--input",
                "results/source.json",
            ],
        )
        self.assertNotEqual(bare_input.returncode, 0)

        source = self.run_cli(
            "immutable-source",
            "results/source.txt",
            command=[sys.executable, "-c", "print('source')"],
        )
        self.assertEqual(source.returncode, 0, source.stderr)
        output_ref = self.run_cli(
            "output-ref",
            "results/out.txt",
            command=[
                sys.executable,
                "-c",
                "print('must not run')",
                "--output",
                "attempt://immutable-source/results/source.txt",
            ],
        )
        self.assertNotEqual(output_ref.returncode, 0)

        shell_path = self.run_cli(
            "shell-path",
            "results/out.txt",
            options=["--shell"],
            command=["printf unsafe > results/local.txt"],
        )
        self.assertNotEqual(shell_path.returncode, 0)
        self.assertFalse((self.repo / "results").exists())

    def test_generates_structured_json_for_plain_test_output(self) -> None:
        script = "import sys; print('Ran 3 tests in 0.01s', file=sys.stderr); print('OK', file=sys.stderr)"
        result = self.run_cli(
            "attempt-unittest",
            "results/test-result.json",
            command=[sys.executable, "-c", script, "--filter", "fixture"],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        artifact = json.loads(
            (self.attempt_root("attempt-unittest") / "results/test-result.json").read_text()
        )
        self.assertEqual(artifact["kind"], "command-result")
        self.assertEqual(artifact["counts"]["matched"], 3)
        manifest = self.manifest("attempt-unittest")
        self.assertEqual(manifest["result"]["command"]["counts"]["matched"], 3)
        self.assertEqual(manifest["result"]["command"]["counts"]["failed"], 0)

    def test_counts_are_tool_scoped_structured_and_skip_strict(self) -> None:
        github = self.root / "github.json"
        github.write_text('[[{"body":"166 passed"}]]\n', encoding="utf-8")
        gh_counts = run_evidence.parse_test_counts(
            github.read_bytes(), github, 0, ["gh", "api", "--paginate", "--slurp"]
        )
        self.assertEqual(gh_counts["matched"], 1)

        structured = self.root / "structured.json"
        structured.write_text(
            json.dumps({"counts": {"matched": 4, "failed": 0, "skipped": 1}}),
            encoding="utf-8",
        )
        structured_result = run_evidence.parse_test_counts(
            b"", structured, 0, ["tool", "--test", "fixture"]
        )
        self.assertEqual(structured_result["matched"], 4)
        self.assertEqual(structured_result["skipped"], 1)

        xctest = run_evidence.parse_test_counts(
            (
                b"Test Case '-[Suite testOne]' skipped (0.001 seconds).\n"
                b"Executed 1 test, with 0 failures (0 unexpected) in 0.001 seconds\n"
            ),
            None,
            0,
            ["xcodebuild", "test"],
        )
        self.assertEqual(xctest["matched"], 1)
        self.assertEqual(xctest["skipped"], 1)

        swift = run_evidence.parse_test_counts(
            (
                b"\xe2\x86\xb7 Test skippedFixture() skipped after 0.001 seconds.\n"
                b"Test run with 2 tests skipped after 0.001 seconds.\n"
            ),
            None,
            0,
            ["swift", "test", "--filter", "Fixture"],
        )
        self.assertEqual(swift["skipped"], 2)

        swift_repository_pass = run_evidence.parse_test_counts(
            b"Test run with 140 tests in 23 suites passed after 4.231 seconds.\n",
            None,
            0,
            ["swift", "test", "--filter", "Fixture"],
        )
        self.assertEqual(swift_repository_pass["matched"], 140)
        self.assertEqual(swift_repository_pass["failed"], 0)

        swift_repository_failure = run_evidence.parse_test_counts(
            b"Test run with 2 tests in 1 suite failed after 0.100 seconds.\n",
            None,
            1,
            ["swift", "test", "--filter", "Fixture"],
        )
        self.assertEqual(swift_repository_failure["matched"], 2)
        self.assertEqual(swift_repository_failure["failed"], 1)

        expected = run_evidence.parse_test_counts(
            (
                b"XCTExpectFailure: known issue\n"
                b"Executed 1 test, with 0 failures (0 unexpected) in 0.001 seconds\n"
            ),
            None,
            0,
            ["xcodebuild", "test"],
        )
        self.assertEqual(expected["failed"], 1)

        tap = run_evidence.parse_test_counts(
            b"TAP version 13\n# tests 3\n# pass 3\n# fail 0\n# skipped 0\n",
            None,
            0,
            ["npx", "tsx", "--test", "fixture.ts"],
        )
        self.assertEqual(tap["matched"], 3)

        silent = self.run_cli(
            "silent-selector",
            "results/silent.json",
            command=[
                sys.executable,
                "-c",
                "print('no matching summary')",
                "--filter",
                "Missing",
            ],
        )
        self.assertNotEqual(silent.returncode, 0)

    def test_shell_mode_enables_pipefail(self) -> None:
        result = self.run_cli(
            "shell-pipefail",
            "results/pipeline.txt",
            options=["--shell"],
            command=["false | printf 'downstream\\n'"],
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            (self.attempt_root("shell-pipefail") / "results/pipeline.txt").read_text(),
            "downstream\n",
        )
        command = self.manifest("shell-pipefail")["result"]["command"]
        self.assertNotEqual(command["exitCode"], 0)
        self.assertEqual(command["declared"], ["false | printf 'downstream\\n'"])

    def test_zero_match_skip_missing_artifact_and_local_write_fail_closed(self) -> None:
        zero = self.run_cli(
            "attempt-zero",
            "results/zero.json",
            command=[
                sys.executable,
                "-c",
                "print('Ran 0 tests')",
                "--filter",
                "missing",
            ],
        )
        self.assertNotEqual(zero.returncode, 0)
        self.assertIn("zero", str(self.manifest("attempt-zero")["failure"]))

        skipped = self.run_cli(
            "attempt-skipped",
            "results/skipped.json",
            command=[
                sys.executable,
                "-c",
                "print('Ran 1 test'); print('OK (skipped=1)')",
                "--filter",
                "fixture",
            ],
        )
        self.assertNotEqual(skipped.returncode, 0)
        self.assertIn("skipped", str(self.manifest("attempt-skipped")["failure"]))

        missing = self.run_cli(
            "attempt-missing",
            "results/missing.txt",
            command=[sys.executable, "-c", "pass"],
        )
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("missing", str(self.manifest("attempt-missing")["failure"]))

        local_write = self.run_cli(
            "attempt-local-write",
            "results/external.txt",
            command=[
                sys.executable,
                "-c",
                (
                    "from pathlib import Path; "
                    "Path('results').mkdir(); Path('results/local.txt').write_text('bad'); "
                    "print('captured')"
                ),
            ],
        )
        self.assertNotEqual(local_write.returncode, 0)
        manifest = self.manifest("attempt-local-write")
        self.assertTrue(manifest["repositoryLocalResults"]["changed"])
        self.assertIn("repository-local", str(manifest["failure"]))

    def test_empty_or_symlinked_repository_results_root_fails_closed(self) -> None:
        empty = self.run_cli(
            "empty-local-results",
            "results/external.txt",
            command=[
                sys.executable,
                "-c",
                "from pathlib import Path; Path('results').mkdir(); print('created')",
            ],
        )
        self.assertNotEqual(empty.returncode, 0)
        (self.repo / "results").rmdir()

        target = self.root / "empty-target"
        target.mkdir()
        symlink = self.run_cli(
            "symlink-local-results",
            "results/external.txt",
            command=[
                sys.executable,
                "-c",
                (
                    "from pathlib import Path; "
                    f"Path('results').symlink_to({str(target)!r}, target_is_directory=True); "
                    "print('created')"
                ),
            ],
        )
        self.assertNotEqual(symlink.returncode, 0)
        (self.repo / "results").unlink()

    def test_source_head_and_worktree_drift_invalidates_attempt(self) -> None:
        dirty = self.run_cli(
            "source-dirty",
            "results/source.txt",
            command=[
                sys.executable,
                "-c",
                "from pathlib import Path; Path('README.md').write_text('changed\\n'); print('done')",
            ],
        )
        self.assertNotEqual(dirty.returncode, 0)
        self.assertIn("working-tree state", str(self.manifest("source-dirty")["failure"]))
        subprocess.run(
            ["git", "checkout", "--", "README.md"], cwd=self.repo, check=True
        )

        (self.repo / "next.txt").write_text("next\n", encoding="utf-8")
        next_head = self.commit_all("next head")
        subprocess.run(
            ["git", "checkout", "--detach", self.initial_head],
            cwd=self.repo,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        drift = self.run_cli(
            "source-head-drift",
            "results/source.txt",
            head=self.initial_head,
            command=["git", "checkout", "--detach", next_head],
        )
        self.assertNotEqual(drift.returncode, 0)
        self.assertIn(
            "HEAD drifted",
            str(self.manifest("source-head-drift", head=self.initial_head)["failure"]),
        )

    def test_attempt_collision_preserves_original_bytes(self) -> None:
        first = self.run_cli(
            "attempt-collision",
            "results/value.txt",
            command=[sys.executable, "-c", "print('first')"],
        )
        self.assertEqual(first.returncode, 0, first.stderr)
        attempt = self.attempt_root("attempt-collision")
        before = {
            path.relative_to(attempt).as_posix(): path.read_bytes()
            for path in attempt.rglob("*")
            if path.is_file()
        }
        second = self.run_cli(
            "attempt-collision",
            "results/value.txt",
            command=[sys.executable, "-c", "print('second')"],
        )
        self.assertNotEqual(second.returncode, 0)
        after = {
            path.relative_to(attempt).as_posix(): path.read_bytes()
            for path in attempt.rglob("*")
            if path.is_file()
        }
        self.assertEqual(after, before)

    def test_retry_is_exact_linked_retained_and_single(self) -> None:
        marker = self.root / "transient-ready"
        script = (
            "from pathlib import Path; import sys; "
            f"ready=Path({str(marker)!r}).exists(); print('Ran 1 test'); "
            "print('OK' if ready else 'FAILED (failures=1)'); sys.exit(0 if ready else 1)"
        )
        command = [sys.executable, "-c", script]
        first = self.run_cli(
            "attempt-transient",
            "results/transient.txt",
            assertion="TRANSIENT",
            command=command,
        )
        self.assertNotEqual(first.returncode, 0)
        marker.write_text("ready", encoding="utf-8")
        retry = self.run_cli(
            "retry-transient",
            "results/transient.txt",
            assertion="TRANSIENT",
            options=[
                "--retry-of",
                "attempt-transient",
                "--reason",
                "diagnosed fixture readiness race",
            ],
            command=command,
        )
        self.assertEqual(retry.returncode, 0, retry.stderr)
        self.assertTrue(self.attempt_root("attempt-transient").is_dir())
        retry_manifest = self.manifest("retry-transient")
        self.assertEqual(retry_manifest["retryOf"], "attempt-transient")
        self.assertEqual(retry_manifest["retry"]["reason"], "diagnosed fixture readiness race")
        retry_claim = Path(retry_manifest["retry"]["claim"])
        self.assertTrue(retry_claim.is_file())
        self.assertEqual(retry_claim.stat().st_mode & 0o777, 0o600)
        self.assertEqual(retry_claim.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(retry_claim.parent.parent.stat().st_mode & 0o777, 0o700)
        second_retry = self.run_cli(
            "retry-transient-two",
            "results/transient.txt",
            assertion="TRANSIENT",
            options=[
                "--retry-of",
                "attempt-transient",
                "--reason",
                "same diagnosed transient",
            ],
            command=command,
        )
        self.assertNotEqual(second_retry.returncode, 0)

    def test_builtin_retry_rejects_changed_invocation(self) -> None:
        for name in ("one.txt", "two.txt"):
            (self.repo / name).write_text(name, encoding="utf-8")
        head = self.commit_all("two paths")
        first = self.run_cli(
            "builtin-failed",
            "results/scope.json",
            head=head,
            assertion="BUILTIN-RETRY",
            options=[
                "--check-exact-paths",
                "--base",
                self.initial_head,
                "--head",
                head,
                "--allow",
                "one.txt",
            ],
        )
        self.assertNotEqual(first.returncode, 0)
        changed = self.run_cli(
            "builtin-retry-changed",
            "results/scope.json",
            head=head,
            assertion="BUILTIN-RETRY",
            options=[
                "--retry-of",
                "builtin-failed",
                "--reason",
                "transient",
                "--check-exact-paths",
                "--base",
                self.initial_head,
                "--head",
                head,
                "--allow",
                "one.txt",
                "--allow",
                "two.txt",
            ],
        )
        self.assertNotEqual(changed.returncode, 0)
        self.assertIn(
            "invocation differs", str(self.manifest("builtin-retry-changed")["failure"])
        )

    def test_attempt_references_compare_and_record_lineage(self) -> None:
        for attempt in ("attempt-left", "attempt-right"):
            result = self.run_cli(
                attempt,
                "results/value.txt",
                command=[sys.executable, "-c", "print('same')"],
            )
            self.assertEqual(result.returncode, 0, result.stderr)
        comparison = self.run_cli(
            "attempt-compare",
            "results/comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://attempt-left/results/value.txt",
                "attempt://attempt-right/results/value.txt",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertEqual(comparison.returncode, 0, comparison.stderr)
        artifact = json.loads(
            (self.attempt_root("attempt-compare") / "results/comparison.json").read_text()
        )
        self.assertTrue(artifact["equal"])
        manifest = self.manifest("attempt-compare")
        self.assertEqual(len(manifest["inputs"]), 2)
        self.assertTrue(all(item["manifestSha256"] for item in manifest["inputs"]))

    def test_sha_and_pr_comparison_schemas(self) -> None:
        digest = "a" * 64
        for attempt in ("sha-left", "sha-right"):
            result = self.run_cli(
                attempt,
                "results/digest.json",
                command=[sys.executable, "-c", f"print('{digest}  -')"],
            )
            self.assertEqual(result.returncode, 0, result.stderr)
        sha_compare = self.run_cli(
            "sha-compare",
            "results/sha-comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://sha-left/results/digest.json",
                "attempt://sha-right/results/digest.json",
                "--comparison",
                "sha256-value",
            ],
        )
        self.assertEqual(sha_compare.returncode, 0, sha_compare.stderr)

        pr = {
            "number": 117,
            "state": "open",
            "draft": True,
            "head": {"ref": "codex/wp-rel-01", "sha": "b" * 40},
            "base": {"ref": "main", "sha": "c" * 40},
        }
        payload = json.dumps(pr, separators=(",", ":"))
        for attempt in ("pr-before", "pr-after"):
            result = self.run_cli(
                attempt,
                "results/pr.json",
                command=[sys.executable, "-c", f"print({payload!r})"],
            )
            self.assertEqual(result.returncode, 0, result.stderr)
        pr_compare = self.run_cli(
            "pr-compare",
            "results/pr-comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://pr-before/results/pr.json",
                "attempt://pr-after/results/pr.json",
                "--comparison",
                "pr-number-head-base-state",
            ],
        )
        self.assertEqual(pr_compare.returncode, 0, pr_compare.stderr)

    def test_owner_fingerprint_detects_same_size_untracked_content_change(self) -> None:
        owner = self.root / "owner-repository"
        owner.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=owner, check=True)
        subprocess.run(
            ["git", "config", "user.email", "owner-tests@example.invalid"],
            cwd=owner,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Owner Tests"],
            cwd=owner,
            check=True,
        )
        (owner / "README.md").write_text("owner\n", encoding="utf-8")
        subprocess.run(["git", "add", "README.md"], cwd=owner, check=True)
        subprocess.run(["git", "commit", "-qm", "owner baseline"], cwd=owner, check=True)
        private = owner / "private.txt"
        private.write_text("alpha", encoding="utf-8")
        target = self.root / "symlink-target"
        target.write_text("target\n", encoding="utf-8")
        (owner / "private-link").symlink_to(target)

        before = self.run_cli(
            "owner-fingerprint-before",
            "results/owner.json",
            options=["--fingerprint-git-owner-state", str(owner)],
        )
        self.assertEqual(before.returncode, 0, before.stderr)
        before_path = self.attempt_root("owner-fingerprint-before") / "results/owner.json"
        before_value = json.loads(before_path.read_text())
        self.assertEqual(before_value["untrackedCount"], 2)
        kinds = {
            item["pathSha256"]: item["kind"]
            for item in before_value["untrackedEntries"]
        }
        self.assertEqual(
            kinds,
            {
                run_evidence.private_path_digest("private-link"): "symlink",
                run_evidence.private_path_digest("private.txt"): "file",
            },
        )
        serialized = before_path.read_text()
        self.assertNotIn('"path"', serialized)
        self.assertNotIn("private-link", serialized)
        self.assertNotIn("private.txt", serialized)
        self.assertNotIn("alpha", serialized)
        self.assertNotIn(str(target), serialized)
        self.assertEqual(before_value["schemaVersion"], 2)

        private.write_text("omega", encoding="utf-8")
        after = self.run_cli(
            "owner-fingerprint-after",
            "results/owner.json",
            options=["--fingerprint-git-owner-state", str(owner)],
        )
        self.assertEqual(after.returncode, 0, after.stderr)
        after_value = json.loads(
            (self.attempt_root("owner-fingerprint-after") / "results/owner.json").read_text()
        )
        self.assertNotEqual(before_value["stateSha256"], after_value["stateSha256"])
        comparison = self.run_cli(
            "owner-fingerprint-compare",
            "results/comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://owner-fingerprint-before/results/owner.json",
                "attempt://owner-fingerprint-after/results/owner.json",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertNotEqual(comparison.returncode, 0)

    def test_owner_fingerprint_rejects_head_or_status_races(self) -> None:
        head_a = "a" * 40
        head_b = "b" * 40
        status_a = (
            f"# branch.oid {head_a}\0# branch.head main\0".encode("ascii")
        )

        def stable_git_bytes(
            _: Path, arguments: list[str], __: str
        ) -> bytes:
            return status_a if arguments[0] == "status" else b""

        with mock.patch.object(
            run_evidence, "repository_root", return_value=self.repo
        ), mock.patch.object(
            run_evidence, "git_bytes", side_effect=stable_git_bytes
        ), mock.patch.object(
            run_evidence, "git_output", side_effect=[head_a, head_b]
        ):
            with self.assertRaisesRegex(
                run_evidence.EvidenceError, "HEAD changed"
            ):
                run_evidence.git_owner_state_fingerprint(self.repo)

        malformed = b"# branch.oid (initial)\0# branch.head main\0"
        with self.assertRaisesRegex(
            run_evidence.EvidenceError, "branch.oid"
        ):
            run_evidence.status_branch_oid(malformed)

    def test_attempt_reference_rejects_tamper_alias_escape_and_cross_head(self) -> None:
        source = self.run_cli(
            "source-attempt",
            "results/value.txt",
            command=[sys.executable, "-c", "print('original')"],
        )
        self.assertEqual(source.returncode, 0, source.stderr)
        source_path = self.attempt_root("source-attempt") / "results/value.txt"
        source_path.write_text("tampered\n", encoding="utf-8")
        tampered = self.run_cli(
            "consume-tampered",
            "results/comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://source-attempt/results/value.txt",
                "attempt://source-attempt/results/value.txt",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertNotEqual(tampered.returncode, 0)

        alias = self.run_cli(
            "consume-alias",
            "results/comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://latest/results/value.txt",
                "attempt://other/results/value.txt",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertNotEqual(alias.returncode, 0)
        escape = self.run_cli(
            "consume-escape",
            "results/comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://source-attempt/results/%2e%2e/manifest.json",
                "attempt://other/results/value.txt",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertNotEqual(escape.returncode, 0)

        (self.repo / "next.txt").write_text("next\n", encoding="utf-8")
        new_head = self.commit_all("new candidate")
        cross_head = self.run_cli(
            "consume-cross-head",
            "results/comparison.json",
            head=new_head,
            options=[
                "--compare-artifacts",
                "attempt://source-attempt/results/value.txt",
                "attempt://other/results/value.txt",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertNotEqual(cross_head.returncode, 0)

    def test_directory_input_digest_includes_empty_directory_structure(self) -> None:
        direct_root = self.root / "direct-directory"
        direct_root.mkdir(mode=0o700)
        before = run_evidence.directory_artifact_record(direct_root, self.root)
        (direct_root / "empty").mkdir(mode=0o700)
        after = run_evidence.directory_artifact_record(direct_root, self.root)
        self.assertNotEqual(before["sha256"], after["sha256"])
        self.assertEqual(after["fileCount"], 0)
        self.assertEqual(after["directoryCount"], 1)

        script = (
            "from pathlib import Path; import sys; "
            "root=Path(sys.argv[1]); root.mkdir(); (root/'original-empty').mkdir()"
        )
        source = self.run_cli(
            "directory-source",
            "results/tree",
            command=[sys.executable, "-c", script, "results/tree"],
        )
        self.assertEqual(source.returncode, 0, source.stderr)
        tree = self.attempt_root("directory-source") / "results/tree"
        (tree / "original-empty").rmdir()
        (tree / "replacement-empty").mkdir(mode=0o700)
        consumer = self.run_cli(
            "directory-consumer",
            "results/value.txt",
            command=[
                sys.executable,
                "-c",
                "print('must not run')",
                "attempt://directory-source/results/tree",
            ],
        )
        self.assertNotEqual(consumer.returncode, 0)
        self.assertIn(
            "digest mismatch", str(self.manifest("directory-consumer")["failure"])
        )

    def test_attempt_reference_rejects_internal_same_content_symlink(self) -> None:
        source = self.run_cli(
            "symlink-source",
            "results/value.txt",
            command=[sys.executable, "-c", "print('same')"],
        )
        self.assertEqual(source.returncode, 0, source.stderr)
        artifact = self.attempt_root("symlink-source") / "results/value.txt"
        artifact.unlink()
        artifact.symlink_to(Path("..") / "stdout.txt")
        consumed = self.run_cli(
            "symlink-consumer",
            "results/comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://symlink-source/results/value.txt",
                "attempt://symlink-source/results/value.txt",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertNotEqual(consumed.returncode, 0)
        self.assertIn("symlink", str(self.manifest("symlink-consumer")["failure"]))

    def test_rejects_symlinked_package_and_referenced_attempt_roots(self) -> None:
        self.evidence.mkdir(mode=0o700)
        self.evidence.chmod(0o700)
        outside = self.root / "outside-package"
        outside.mkdir(mode=0o700)
        (self.evidence / "WP-TEST-01").symlink_to(
            outside, target_is_directory=True
        )
        package_symlink = self.run_cli(
            "package-symlink",
            "results/value.txt",
            command=[sys.executable, "-c", "print('must not run')"],
        )
        self.assertNotEqual(package_symlink.returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])

        (self.evidence / "WP-TEST-01").unlink()
        source = self.run_cli(
            "attempt-alias",
            "results/value.txt",
            command=[sys.executable, "-c", "print('original')"],
        )
        self.assertEqual(source.returncode, 0, source.stderr)
        declared = self.attempt_root("attempt-alias")
        retained = declared.with_name("attempt-alias-retained")
        declared.rename(retained)
        declared.symlink_to(retained.name, target_is_directory=True)
        consumer = self.run_cli(
            "attempt-alias-consumer",
            "results/comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://attempt-alias/results/value.txt",
                "attempt://attempt-alias/results/value.txt",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertNotEqual(consumer.returncode, 0)
        self.assertIn(
            "symlink", str(self.manifest("attempt-alias-consumer")["failure"])
        )

    def test_command_consumes_private_staged_input_during_source_swap_restore(self) -> None:
        source = self.run_cli(
            "swap-source",
            "results/value.txt",
            command=[sys.executable, "-c", "print('original')"],
        )
        self.assertEqual(source.returncode, 0, source.stderr)
        source_path = self.attempt_root("swap-source") / "results/value.txt"
        script = (
            "from pathlib import Path; import sys; "
            "staged=Path(sys.argv[1]); source=Path(sys.argv[2]); output=Path(sys.argv[3]); "
            "original=source.read_bytes(); source.write_bytes(b'transient\\n'); "
            "output.write_bytes(staged.read_bytes()); source.write_bytes(original)"
        )
        consumer = self.run_cli(
            "swap-consumer",
            "results/consumed.txt",
            command=[
                sys.executable,
                "-c",
                script,
                "attempt://swap-source/results/value.txt",
                str(source_path),
                "results/consumed.txt",
            ],
        )
        self.assertEqual(consumer.returncode, 0, consumer.stderr)
        self.assertEqual(
            (self.attempt_root("swap-consumer") / "results/consumed.txt").read_text(),
            "original\n",
        )
        self.assertEqual(source_path.read_text(), "original\n")
        input_record = self.manifest("swap-consumer")["inputs"][0]
        self.assertNotEqual(input_record["sourcePath"], input_record["stagedPath"])
        self.assertEqual(
            input_record["artifactSha256"], input_record["stagedSha256"]
        )

    def test_current_attempt_root_replacement_fails_before_finalization(self) -> None:
        symlink_package = "WP-TEST-SYMLINK"
        symlink_attempt = self.attempt_root(
            "replace-root", package=symlink_package
        )
        outside = self.root / "outside-attempt"
        outside.mkdir(mode=0o700)
        symlink_script = (
            "from pathlib import Path; import shutil, sys; "
            "attempt=Path(sys.argv[1]); outside=Path(sys.argv[2]); output=Path(sys.argv[3]); "
            "shutil.rmtree(attempt); (outside/'results').mkdir(mode=0o700); "
            "attempt.symlink_to(outside, target_is_directory=True); output.write_text('escaped')"
        )
        symlink_result = self.run_cli(
            "replace-root",
            "results/value.txt",
            package=symlink_package,
            command=[
                sys.executable,
                "-c",
                symlink_script,
                str(symlink_attempt),
                str(outside),
                "results/value.txt",
            ],
        )
        self.assertNotEqual(symlink_result.returncode, 0)
        self.assertFalse((outside / "manifest.json").exists())
        self.assertFalse((outside / "stdout.txt").exists())

        inode_package = "WP-TEST-INODE"
        inode_attempt = self.attempt_root("replace-root", package=inode_package)
        inode_script = (
            "from pathlib import Path; import shutil, sys; "
            "attempt=Path(sys.argv[1]); output=Path(sys.argv[2]); shutil.rmtree(attempt); "
            "attempt.mkdir(mode=0o700); (attempt/'results').mkdir(mode=0o700); "
            "output.write_text('replacement')"
        )
        inode_result = self.run_cli(
            "replace-root",
            "results/value.txt",
            package=inode_package,
            command=[
                sys.executable,
                "-c",
                inode_script,
                str(inode_attempt),
                "results/value.txt",
            ],
        )
        self.assertNotEqual(inode_result.returncode, 0)
        self.assertFalse((inode_attempt / "manifest.json").exists())

    def test_permissive_referenced_artifact_fails_closed(self) -> None:
        source = self.run_cli(
            "permissive-source",
            "results/value.txt",
            command=[sys.executable, "-c", "print('private')"],
        )
        self.assertEqual(source.returncode, 0, source.stderr)
        source_path = self.attempt_root("permissive-source") / "results/value.txt"
        source_path.chmod(0o644)
        consumer = self.run_cli(
            "permissive-consumer",
            "results/comparison.json",
            options=[
                "--compare-artifacts",
                "attempt://permissive-source/results/value.txt",
                "attempt://permissive-source/results/value.txt",
                "--comparison",
                "exact-bytes",
            ],
        )
        self.assertNotEqual(consumer.returncode, 0)
        self.assertIn("0600", str(self.manifest("permissive-consumer")["failure"]))

    def test_evidence_permissions_are_private_and_permissive_root_fails_closed(self) -> None:
        result = self.run_cli(
            "private-modes",
            "results/value.txt",
            command=[sys.executable, "-c", "print('private')"],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        attempt = self.attempt_root("private-modes")
        directories = [
            self.evidence,
            attempt.parents[2],
            attempt.parents[1],
            attempt.parent,
            attempt,
            attempt / "results",
        ]
        for directory in directories:
            self.assertEqual(
                directory.stat().st_mode & 0o777,
                0o700,
                str(directory),
            )
        for file_path in (
            attempt / "results/value.txt",
            attempt / "stdout.txt",
            attempt / "stderr.txt",
            attempt / "manifest.json",
        ):
            self.assertEqual(file_path.stat().st_mode & 0o777, 0o600, str(file_path))

        permissive = self.root / "permissive-evidence"
        permissive.mkdir(mode=0o755)
        permissive.chmod(0o755)
        rejected = self.run_cli(
            "permissive-root",
            "results/value.txt",
            root=permissive,
            command=[sys.executable, "-c", "print('must not run')"],
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("0700", rejected.stderr)

    def test_symlinked_lease_root_fails_before_resource_claim(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        target = self.root / "lease-target"
        target.mkdir(mode=0o700)
        alias = self.root / "lease-alias"
        alias.symlink_to(target, target_is_directory=True)
        result = self.run_cli(
            "symlink-lease-root",
            "results/value.txt",
            lock_root=alias,
            command=["xcodebuild", "test"],
            environment={"PATH": f"{fake_bin}:{os.environ['PATH']}"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must not be a symlink", result.stderr)
        self.assertEqual(list(target.iterdir()), [])

    def make_fake_gh(self) -> tuple[Path, dict[str, object]]:
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "if '--version' in sys.argv:\n"
            "    print('gh version test')\n"
            "elif sys.argv[1:3] == ['auth', 'status']:\n"
            "    print(json.dumps({'hosts': {'github.com': [{'active': True, 'state': 'success'}]}}))\n"
            "else:\n"
            "    print(json.dumps(json.loads(os.environ['FAKE_GH_PAYLOADS'])[sys.argv[-1]], separators=(',', ':')))\n",
            encoding="utf-8",
        )
        gh.chmod(0o755)
        payloads: dict[str, object] = {
            "repos/WillSoltani/Chapterflow-IOS/pulls?state=open&per_page=100": [[
                {
                    "number": 117,
                    "state": "open",
                    "draft": True,
                    "head": {"ref": "codex/wp-rel-01", "sha": "a" * 40},
                    "base": {"ref": "main", "sha": "b" * 40},
                    "html_url": "https://example.invalid/117",
                }
            ]],
            "repos/WillSoltani/ChapterFlow/pulls?state=open&per_page=100": [[
                {
                    "number": 401,
                    "state": "open",
                    "draft": False,
                    "head": {"ref": "backend-active", "sha": "c" * 40},
                    "base": {"ref": "main", "sha": "d" * 40},
                    "html_url": "https://example.invalid/401",
                }
            ]],
            "repos/WillSoltani/Chapterflow-IOS/branches?per_page=100": [[
                {"name": "main", "commit": {"sha": self.initial_head}, "protected": True}
            ]],
            "repos/WillSoltani/ChapterFlow/branches?per_page=100": [[
                {"name": "main", "commit": {"sha": "e" * 40}, "protected": True}
            ]],
        }
        return binary, payloads

    def test_builds_normalized_inventory_from_exact_captures(self) -> None:
        planned_branch = "codex/shared-repository-name"
        package_path = (
            self.repo
            / "upgrade/workstreams/01-current-work-recovery/WP-PLANNED/package.json"
        )
        package_path.parent.mkdir(parents=True)
        package_path.write_text(
            json.dumps(
                {
                    "id": "WP-PLANNED",
                    "git": {
                        "repository": "WillSoltani/Chapterflow-IOS",
                        "branch": planned_branch,
                    },
                }
            ),
            encoding="utf-8",
        )
        self.commit_all("planned package fixture")
        secondary_worktree = self.root / "ios-secondary"
        subprocess.run(
            [
                "git",
                "worktree",
                "add",
                "-q",
                "-b",
                "recovery-secondary",
                str(secondary_worktree),
                self.git("rev-parse", "HEAD"),
            ],
            cwd=self.repo,
            check=True,
        )

        backend = self.root / "backend"
        backend.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=backend, check=True)
        subprocess.run(
            ["git", "config", "user.email", "backend-tests@example.invalid"],
            cwd=backend,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Backend Tests"],
            cwd=backend,
            check=True,
        )
        subprocess.run(
            [
                "git",
                "remote",
                "add",
                "origin",
                "https://github.com/WillSoltani/ChapterFlow.git",
            ],
            cwd=backend,
            check=True,
        )
        (backend / "README.md").write_text("backend\n", encoding="utf-8")
        subprocess.run(["git", "add", "README.md"], cwd=backend, check=True)
        subprocess.run(["git", "commit", "-qm", "backend baseline"], cwd=backend, check=True)
        backend_head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=backend,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.strip()
        recovery_heads = [f"backend={backend_head}"]

        fake_bin, payloads = self.make_fake_gh()
        payloads["repos/WillSoltani/Chapterflow-IOS/branches?per_page=100"][0].append(
            {"name": planned_branch, "commit": {"sha": "f" * 40}}
        )
        payloads["repos/WillSoltani/ChapterFlow/branches?per_page=100"][0].append(
            {"name": planned_branch, "commit": {"sha": "9" * 40}}
        )
        environment = {
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "FAKE_GH_PAYLOADS": json.dumps(payloads),
            "CHAPTERFLOW_BACKEND_HEAD": backend_head,
            "CHAPTERFLOW_BACKEND_REPOSITORY": str(backend),
            "CHAPTERFLOW_BACKEND_WORKTREES_REF": (
                "attempt://capture-backend-worktrees/"
                "results/recovery/backend-worktrees.txt"
            ),
        }
        worktrees = self.run_cli(
            "capture-worktrees",
            "results/recovery/worktrees.txt",
            command=["git", "worktree", "list", "--porcelain"],
            environment=environment,
            repo_heads=recovery_heads,
        )
        self.assertEqual(worktrees.returncode, 0, worktrees.stderr)
        backend_worktrees = self.run_cli(
            "capture-backend-worktrees",
            "results/recovery/backend-worktrees.txt",
            command=["git", "-C", str(backend), "worktree", "list", "--porcelain"],
            environment=environment,
            repo_heads=recovery_heads,
        )
        self.assertEqual(
            backend_worktrees.returncode, 0, backend_worktrees.stderr
        )
        captures = [
            (
                "capture-ios-prs",
                "results/recovery/ios-open-prs.json",
                "repos/WillSoltani/Chapterflow-IOS/pulls?state=open&per_page=100",
            ),
            (
                "capture-backend-prs",
                "results/recovery/backend-open-prs.json",
                "repos/WillSoltani/ChapterFlow/pulls?state=open&per_page=100",
            ),
            (
                "capture-ios-branches",
                "results/recovery/ios-branches.json",
                "repos/WillSoltani/Chapterflow-IOS/branches?per_page=100",
            ),
            (
                "capture-backend-branches",
                "results/recovery/backend-branches.json",
                "repos/WillSoltani/ChapterFlow/branches?per_page=100",
            ),
        ]
        for attempt, artifact, endpoint in captures:
            result = self.run_cli(
                attempt,
                artifact,
                command=["gh", "api", "--paginate", "--slurp", endpoint],
                environment=environment,
                repo_heads=recovery_heads,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
        build = self.run_cli(
            "build-inventory",
            "results/recovery/inventory.json",
            options=[
                "--build-recovery-inventory",
                "--worktrees",
                "attempt://capture-worktrees/results/recovery/worktrees.txt",
                "--ios-prs",
                "attempt://capture-ios-prs/results/recovery/ios-open-prs.json",
                "--backend-prs",
                "attempt://capture-backend-prs/results/recovery/backend-open-prs.json",
                "--ios-branches",
                "attempt://capture-ios-branches/results/recovery/ios-branches.json",
                "--backend-branches",
                "attempt://capture-backend-branches/results/recovery/backend-branches.json",
            ],
            environment=environment,
        )
        self.assertEqual(build.returncode, 0, build.stderr)
        inventory = json.loads(
            (self.attempt_root("build-inventory") / "results/recovery/inventory.json").read_text()
        )
        self.assertEqual(inventory["counts"]["worktrees"], 3)
        self.assertEqual(inventory["counts"]["iosWorktrees"], 2)
        self.assertEqual(inventory["counts"]["backendWorktrees"], 1)
        self.assertEqual(inventory["counts"]["iosOpenPRs"], 1)
        self.assertEqual(inventory["counts"]["backendOpenPRs"], 1)
        self.assertEqual(inventory["counts"]["candidates"], 9)
        self.assertEqual(len(inventory["sources"]), 6)
        self.assertEqual(
            inventory["repositoryBindings"]["backend"]["root"],
            str(backend.resolve()),
        )
        self.assertEqual(inventory["schemaVersion"], 2)
        candidates = {
            item["candidateId"]: item for item in inventory["candidates"]
        }
        self.assertEqual(
            candidates[f"ios:branch:{planned_branch}"]["successorPackage"]["packageId"],
            "WP-PLANNED",
        )
        self.assertNotIn(
            "successorPackage", candidates[f"backend:branch:{planned_branch}"]
        )
        (secondary_worktree / "advanced.txt").write_text("advanced\n", encoding="utf-8")
        subprocess.run(
            ["git", "add", "advanced.txt"], cwd=secondary_worktree, check=True
        )
        subprocess.run(
            ["git", "commit", "-qm", "advance secondary worktree"],
            cwd=secondary_worktree,
            check=True,
        )
        classified = self.run_cli(
            "classify-inventory",
            "results/recovery/classified.json",
            options=[
                "--classify-recovery-inventory",
                "attempt://build-inventory/results/recovery/inventory.json",
                "--target",
                f"ios={self.git('rev-parse', 'HEAD')}",
            ],
            environment=environment,
        )
        self.assertEqual(classified.returncode, 0, classified.stderr)
        classification = json.loads(
            (
                self.attempt_root("classify-inventory")
                / "results/recovery/classified.json"
            ).read_text()
        )
        self.assertEqual(
            len(classification["classifications"]), inventory["counts"]["candidates"]
        )
        self.assertEqual(classification["counts"]["frozen"], 1)
        secondary_row = next(
            item
            for item in classification["classifications"]
            if item["kind"] == "worktree"
            and item["candidateId"].startswith("ios:worktree:")
            and Path(
                item["candidateId"].removeprefix("ios:worktree:")
            ).resolve()
            == secondary_worktree.resolve()
        )
        self.assertEqual(secondary_row["disposition"], "unsafe-to-touch")
        self.assertEqual(secondary_row["reason"], "worktree-registry-drift")

        other_backend, _ = self.make_backend_repository("other-backend")
        wrong_capture = self.run_cli(
            "capture-wrong-backend-worktrees",
            "results/recovery/backend-worktrees.txt",
            command=[
                "git",
                "-C",
                str(other_backend),
                "worktree",
                "list",
                "--porcelain",
            ],
            environment=environment,
            repo_heads=recovery_heads,
        )
        self.assertEqual(wrong_capture.returncode, 0, wrong_capture.stderr)
        wrong_build = self.run_cli(
            "build-inventory-wrong-backend",
            "results/recovery/inventory.json",
            options=[
                "--build-recovery-inventory",
                "--worktrees",
                "attempt://capture-worktrees/results/recovery/worktrees.txt",
                "--backend-worktrees",
                "attempt://capture-wrong-backend-worktrees/results/recovery/backend-worktrees.txt",
                "--ios-prs",
                "attempt://capture-ios-prs/results/recovery/ios-open-prs.json",
                "--backend-prs",
                "attempt://capture-backend-prs/results/recovery/backend-open-prs.json",
                "--ios-branches",
                "attempt://capture-ios-branches/results/recovery/ios-branches.json",
                "--backend-branches",
                "attempt://capture-backend-branches/results/recovery/backend-branches.json",
            ],
            environment=environment,
        )
        self.assertNotEqual(wrong_build.returncode, 0)
        self.assertIn(
            "different repository root",
            str(self.manifest("build-inventory-wrong-backend")["failure"]),
        )

    def test_inventory_parsers_reject_duplicates_and_truncated_pages(self) -> None:
        with self.assertRaises(run_evidence.EvidenceError):
            run_evidence.flatten_gh_pages([], "empty")
        with self.assertRaises(run_evidence.EvidenceError):
            run_evidence.flatten_gh_pages([{"not": "pages"}], "truncated")
        branch = {"name": "main", "commit": {"sha": "a" * 40}}
        with self.assertRaises(run_evidence.EvidenceError):
            run_evidence.parse_branches([[branch, branch]], "ios")
        malformed_worktree = f"worktree /tmp/a\nHEAD {'a' * 40}\n"
        with self.assertRaises(run_evidence.EvidenceError):
            run_evidence.parse_worktrees(malformed_worktree.encode())

    def test_lsof_warning_fails_closed_without_persisting_diagnostic(self) -> None:
        private_warning = "cannot read owner-private-directory"
        with mock.patch.object(
            run_evidence.shutil, "which", return_value="/usr/sbin/lsof"
        ), mock.patch.object(
            run_evidence.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                ["lsof"], 1, "p123\n", private_warning
            ),
        ):
            observed = run_evidence.worktree_open_files(self.repo)
        self.assertFalse(observed["available"])
        self.assertIsNone(observed["count"])
        self.assertEqual(observed["pids"], [])
        self.assertNotIn(private_warning, json.dumps(observed))
        self.assertEqual(
            observed["stderrSha256"],
            run_evidence.sha256_bytes(private_warning.encode("utf-8")),
        )

    def test_backend_repository_binding_rejects_remote_suffix_spoofs(self) -> None:
        backend, _ = self.make_backend_repository("backend-origin-validation")
        self.assertEqual(
            run_evidence.validate_backend_repository(str(backend)), backend.resolve()
        )
        invalid_remotes = (
            "https://evil.invalid/ChapterFlow.git",
            "https://github.com/Other/ChapterFlow.git",
            str(self.root / "attacker" / "ChapterFlow"),
        )
        for remote in invalid_remotes:
            with self.subTest(remote=remote):
                subprocess.run(
                    ["git", "remote", "set-url", "origin", remote],
                    cwd=backend,
                    check=True,
                )
                with self.assertRaisesRegex(
                    run_evidence.EvidenceError, "origin must be"
                ):
                    run_evidence.validate_backend_repository(str(backend))
        subprocess.run(
            [
                "git",
                "remote",
                "set-url",
                "origin",
                "https://github.com/WillSoltani/ChapterFlow.git",
            ],
            cwd=backend,
            check=True,
        )

    def test_exact_path_mode_requires_equality_and_ancestry(self) -> None:
        base = self.initial_head
        allowed = [
            "docs/ios/DEVELOPMENT_EXECUTION_STATUS.md",
            "scripts/validation/run_evidence.py",
            "scripts/tests/test_upgrade_evidence_runner.py",
        ]
        for path in allowed:
            target = self.repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(f"{path}\n", encoding="utf-8")
        head = self.commit_all("three exact paths")
        result = self.run_cli(
            "exact-paths",
            "results/scope.json",
            head=head,
            options=[
                "--check-exact-paths",
                "--base",
                base,
                "--head",
                head,
                *sum((["--allow", path] for path in allowed), []),
            ],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        subprocess.run(
            ["git", "commit", "--allow-empty", "-qm", "descendant"],
            cwd=self.repo,
            check=True,
        )
        descendant = self.git("rev-parse", "HEAD")
        mismatched = self.run_cli(
            "mismatched-head",
            "results/scope.json",
            head=descendant,
            options=[
                "--check-exact-paths",
                "--base",
                base,
                "--head",
                head,
                *sum((["--allow", path] for path in allowed), []),
            ],
        )
        self.assertNotEqual(mismatched.returncode, 0)
        self.assertIn("candidate HEAD", str(self.manifest("mismatched-head")["failure"]))
        (self.repo / "extra.txt").write_text("extra\n", encoding="utf-8")
        extra_head = self.commit_all("extra path")
        extra = self.run_cli(
            "extra-path",
            "results/scope.json",
            head=extra_head,
            options=[
                "--check-exact-paths",
                "--base",
                base,
                "--head",
                extra_head,
                *sum((["--allow", path] for path in allowed), []),
            ],
        )
        self.assertNotEqual(extra.returncode, 0)

    def test_classification_rejects_command_authored_inventory(self) -> None:
        backend, backend_head = self.make_backend_repository("classification-backend")
        payload = json.dumps({"schemaVersion": 2, "candidates": []})
        source = self.run_cli(
            "inventory-source",
            "results/inventory.json",
            command=[sys.executable, "-c", f"print({payload!r})"],
            repo_heads=[f"backend={backend_head}"],
        )
        self.assertEqual(source.returncode, 0, source.stderr)
        classified = self.run_cli(
            "classified",
            "results/classified.json",
            options=[
                "--classify-recovery-inventory",
                "attempt://inventory-source/results/inventory.json",
                "--target",
                f"ios={self.initial_head}",
                "--target",
                f"backend={backend_head}",
                "--backend-repository",
                str(backend),
            ],
            repo_heads=[f"backend={backend_head}"],
        )
        self.assertNotEqual(classified.returncode, 0)
        self.assertIn(
            "provenance-bound built-in mode",
            str(self.manifest("classified")["failure"]),
        )

    def test_backend_classification_uses_backend_object_database(self) -> None:
        backend, backend_target = self.make_backend_repository(
            "backend-graph-classification"
        )
        (backend / "ahead.txt").write_text("ahead\n", encoding="utf-8")
        subprocess.run(["git", "add", "ahead.txt"], cwd=backend, check=True)
        subprocess.run(
            ["git", "commit", "-qm", "backend ahead"],
            cwd=backend,
            check=True,
        )
        backend_ahead = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=backend,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.strip()
        bindings = run_evidence.recovery_repository_bindings(
            self.repo, backend, backend_target
        )
        self.assertEqual(
            bindings["backend"]["declaredSourceHead"], backend_target
        )
        self.assertEqual(bindings["backend"]["localCheckoutHead"], backend_ahead)
        self.assertEqual(
            run_evidence.git_relationship(backend, backend_target, backend_ahead)[
                "disposition"
            ],
            "merged",
        )
        self.assertEqual(
            run_evidence.git_relationship(backend, backend_ahead, backend_target)[
                "disposition"
            ],
            "novel",
        )

    def test_git_relationship_treats_fatal_git_status_as_unsafe(self) -> None:
        def fake_run(arguments: list[str], **_: object) -> subprocess.CompletedProcess:
            operation = arguments[1]
            if operation == "cat-file":
                return subprocess.CompletedProcess(arguments, 0, stdout=b"", stderr=b"")
            if operation == "diff":
                return subprocess.CompletedProcess(arguments, 0, stdout=b"diff", stderr=b"")
            if operation == "merge-base":
                return subprocess.CompletedProcess(arguments, 1, stdout=b"", stderr=b"")
            if operation == "log":
                return subprocess.CompletedProcess(arguments, 128, stdout="", stderr="fatal")
            raise AssertionError(arguments)

        with mock.patch.object(
            run_evidence, "git_output", side_effect=["1" * 40, "2" * 40]
        ), mock.patch.object(run_evidence.subprocess, "run", side_effect=fake_run):
            relationship = run_evidence.git_relationship(
                self.repo, "a" * 40, "b" * 40
            )
        self.assertEqual(relationship["disposition"], "unsafe-to-touch")
        self.assertEqual(relationship["reason"], "git-log-failed")

    def test_git_relationship_treats_merge_only_divergence_as_unsafe(self) -> None:
        base = self.initial_head
        subprocess.run(
            ["git", "checkout", "-qb", "side-a", base], cwd=self.repo, check=True
        )
        (self.repo / "a.txt").write_text("a\n", encoding="utf-8")
        side_a = self.commit_all("side a")

        subprocess.run(
            ["git", "checkout", "-qb", "side-c", base], cwd=self.repo, check=True
        )
        (self.repo / "c.txt").write_text("c\n", encoding="utf-8")
        side_c = self.commit_all("side c")

        subprocess.run(
            ["git", "checkout", "-qb", "merge-candidate", side_a],
            cwd=self.repo,
            check=True,
        )
        subprocess.run(
            ["git", "merge", "--no-ff", "--no-commit", side_c],
            cwd=self.repo,
            check=True,
            stdout=subprocess.PIPE,
        )
        (self.repo / "merge-only.txt").write_text("resolution\n", encoding="utf-8")
        candidate = self.commit_all("merge-only resolution")

        subprocess.run(
            ["git", "checkout", "-qb", "merge-target", base],
            cwd=self.repo,
            check=True,
        )
        subprocess.run(
            ["git", "cherry-pick", side_a, side_c],
            cwd=self.repo,
            check=True,
            stdout=subprocess.PIPE,
        )
        target = self.git("rev-parse", "HEAD")
        unique_non_merges = self.git(
            "log",
            "--cherry-pick",
            "--right-only",
            "--no-merges",
            "--format=%H",
            f"{target}...{candidate}",
        )
        self.assertEqual(unique_non_merges, "")
        relationship = run_evidence.git_relationship(self.repo, candidate, target)
        self.assertEqual(relationship["disposition"], "unsafe-to-touch")
        self.assertEqual(
            relationship["reason"], "diverged-without-proven-equivalence"
        )

    def make_fake_xcodebuild(self) -> Path:
        binary = self.root / "xcode-bin"
        binary.mkdir(exist_ok=True)
        executable = binary / "xcodebuild"
        executable.write_text(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "print('Test run with 1 test passed')\n"
            "sys.exit(1 if os.environ.get('FAKE_XCODE_FAIL') == '1' else 0)\n",
            encoding="utf-8",
        )
        executable.chmod(0o755)
        return binary

    def test_direct_pytest_all_skipped_fails_closed(self) -> None:
        binary = self.root / "pytest-bin"
        binary.mkdir()
        pytest = binary / "pytest"
        pytest.write_text(
            "#!/bin/sh\nprintf '1 skipped in 0.01s\\n'\n",
            encoding="utf-8",
        )
        pytest.chmod(0o755)
        result = self.run_cli(
            "pytest-all-skipped",
            "results/pytest.json",
            command=["pytest", "fixture.py"],
            environment={"PATH": f"{binary}:{os.environ['PATH']}"},
        )
        self.assertNotEqual(result.returncode, 0)
        counts = self.manifest("pytest-all-skipped")["result"]["command"]["counts"]
        self.assertTrue(counts["selectorRequired"])
        self.assertTrue(counts["selectorDetected"])
        self.assertEqual(counts["matched"], 1)
        self.assertEqual(counts["skipped"], 1)
        self.assertIn("skipped", str(self.manifest("pytest-all-skipped")["failure"]))

    def test_lease_acquisition_failure_cleans_only_its_exclusive_slot(self) -> None:
        original_writer = run_evidence.write_json_exclusive
        cases = (
            ("before-claim", OSError("claim write failed"), False),
            ("after-claim", KeyboardInterrupt(), True),
        )
        for suffix, injected, write_first in cases:
            with self.subTest(suffix=suffix):
                lock_root = self.root / f"locks-{suffix}"

                def failing_writer(path: Path, value: object) -> None:
                    if write_first:
                        original_writer(path, value)
                    raise injected

                with mock.patch.object(
                    run_evidence,
                    "write_json_exclusive",
                    side_effect=failing_writer,
                ):
                    with self.assertRaises(type(injected)):
                        run_evidence.acquire_command_lease(
                            lock_root=lock_root,
                            package="WP-TEST-01",
                            assertion="LEASE-ACQUIRE",
                            attempt=f"acquire-{suffix}",
                            owner="owner-1",
                            command_digest="a" * 64,
                            trigger="xcodebuild test",
                        )
                self.assertFalse(
                    (lock_root / "resource-simulator-device-slot-1").exists()
                )

    def test_exclusive_writer_cleans_identity_capture_interrupt(self) -> None:
        target = self.root / "interrupted-exclusive-write.json"
        original_fstat = run_evidence.os.fstat
        calls = 0

        def interrupt_first_fstat(descriptor: int) -> os.stat_result:
            nonlocal calls
            calls += 1
            if calls == 1:
                raise KeyboardInterrupt()
            return original_fstat(descriptor)

        with mock.patch.object(
            run_evidence.os, "fstat", side_effect=interrupt_first_fstat
        ):
            with self.assertRaises(KeyboardInterrupt):
                run_evidence.write_bytes_exclusive(target, b"value")
        self.assertFalse(target.exists())

    def test_signal_restore_interrupt_outranks_creation_error(self) -> None:
        slot = self.root / "signal-priority-slot"
        with mock.patch.object(
            run_evidence.os,
            "mkdir",
            side_effect=FileExistsError(),
        ), mock.patch.object(
            run_evidence.signal,
            "pthread_sigmask",
            side_effect=[set(), KeyboardInterrupt()],
        ):
            with self.assertRaises(KeyboardInterrupt):
                run_evidence.create_exclusive_owned_lease_slot(slot)
        self.assertFalse(slot.exists())

    def test_interrupt_after_finalizer_arm_rolls_back_without_stranding_slot(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        original_arm = run_evidence.AttemptLeaseFinalizer.arm

        def interrupt_after_arm(
            finalizer: run_evidence.AttemptLeaseFinalizer, **kwargs: object
        ) -> None:
            original_arm(finalizer, **kwargs)
            raise KeyboardInterrupt("private-interrupt-detail")

        argv = [
            "--root",
            str(self.evidence),
            "--package",
            "WP-TEST-01",
            "--assertion",
            "LEASE-ARM-INTERRUPT",
            "--attempt",
            "lease-arm-interrupt",
            "--repo-head",
            f"ios={self.git('rev-parse', 'HEAD')}",
            "--cwd",
            str(self.repo),
            "--artifact",
            "results/lease.txt",
            "--owner",
            "owner-1",
            "--lock-root",
            str(self.locks),
            "--",
            "xcodebuild",
            "test",
        ]
        with mock.patch.object(
            run_evidence.AttemptLeaseFinalizer,
            "arm",
            autospec=True,
            side_effect=interrupt_after_arm,
        ), mock.patch.dict(
            os.environ, {"PATH": f"{fake_bin}:{os.environ['PATH']}"}
        ):
            with self.assertRaises(KeyboardInterrupt):
                run_evidence.run(argv)
        self.assertFalse(
            (self.locks / "resource-simulator-device-slot-1").exists()
        )
        attempt = self.attempt_root("lease-arm-interrupt")
        manifest = json.loads((attempt / "manifest.json").read_text())
        self.assertEqual(manifest["status"], "failed")
        self.assertEqual(manifest["lease"]["mode"], "not-required")
        self.assertNotIn("private-interrupt-detail", json.dumps(manifest))
        self.assertFalse((attempt / "lease-release.json").exists())

    def test_release_refuses_byte_identical_replacement_claim(self) -> None:
        lock_root = self.root / "claim-identity-locks"
        captured: dict[str, object] = {}
        command_digest = "a" * 64
        trigger = "xcodebuild test"

        def capture_identity(
            lease: dict[str, object],
            slot: Path,
            slot_identity: tuple[int, int],
            claim_identity: tuple[int, int],
        ) -> None:
            captured.update(
                lease=lease,
                slot=slot,
                slot_identity=slot_identity,
                claim_identity=claim_identity,
            )

        lease, slot = run_evidence.acquire_command_lease(
            lock_root=lock_root,
            package="WP-TEST-01",
            assertion="CLAIM-IDENTITY",
            attempt="claim-identity",
            owner="owner-1",
            command_digest=command_digest,
            trigger=trigger,
            on_acquired=capture_identity,
        )
        assert slot is not None
        claim_path = slot / "claim.json"
        original = claim_path.read_bytes()
        original_inode = claim_path.stat().st_ino
        claim_path.unlink()
        claim_path.write_bytes(original)
        claim_path.chmod(0o600)
        self.assertNotEqual(claim_path.stat().st_ino, original_inode)
        with self.assertRaisesRegex(
            run_evidence.EvidenceError, "replaced simulator-device lease claim"
        ):
            run_evidence.release_command_lease(
                lease,
                slot,
                captured["slot_identity"],
                captured["claim_identity"],
                package="WP-TEST-01",
                assertion="CLAIM-IDENTITY",
                attempt="claim-identity",
                owner="owner-1",
                command_digest=command_digest,
                trigger=trigger,
            )
        self.assertTrue(slot.is_dir())
        self.assertEqual(claim_path.read_bytes(), original)

    def test_command_scoped_lease_releases_and_collision_prevents_execution(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        environment = {"PATH": f"{fake_bin}:{os.environ['PATH']}"}
        passed = self.run_cli(
            "lease-pass",
            "results/lease.txt",
            command=["xcodebuild", "test"],
            environment=environment,
        )
        self.assertEqual(passed.returncode, 0, passed.stderr)
        slot = self.locks / "resource-simulator-device-slot-1"
        self.assertFalse(slot.exists())
        manifest = self.manifest("lease-pass")
        self.assertFalse(manifest["lease"]["released"])
        self.assertTrue(manifest["lease"]["releaseAfterManifest"])
        self.assertEqual(manifest["lease"]["releaseRecord"], "lease-release.json")
        release = json.loads(
            (self.attempt_root("lease-pass") / "lease-release.json").read_text()
        )
        self.assertTrue(release["released"])
        self.assertEqual(
            release["manifestSha256"],
            run_evidence.sha256_file(self.attempt_root("lease-pass") / "manifest.json"),
        )
        self.assertEqual(self.locks.stat().st_mode & 0o777, 0o700)
        self.assertEqual(
            (self.attempt_root("lease-pass") / "lease-release.json").stat().st_mode
            & 0o777,
            0o600,
        )

        wrapper_failure = self.run_cli(
            "lease-wrapper-failure",
            "results/lease.txt",
            command=["xcodebuild", "test", "--input", "results/input.json"],
            environment=environment,
        )
        self.assertNotEqual(wrapper_failure.returncode, 0)
        self.assertFalse(slot.exists())
        failed_release = json.loads(
            (
                self.attempt_root("lease-wrapper-failure") / "lease-release.json"
            ).read_text()
        )
        self.assertTrue(failed_release["released"])

        slot.mkdir(mode=0o700)
        slot.chmod(0o700)
        collision_claim = slot / "claim.json"
        collision_claim.write_text(
            json.dumps(
                {
                    "scope": "command",
                    "packageId": "OTHER",
                    "ownerTaskId": "other-owner",
                    "pid": 999,
                }
            ),
            encoding="utf-8",
        )
        collision_claim.chmod(0o600)
        collision = self.run_cli(
            "lease-collision",
            "results/lease.txt",
            command=["xcodebuild", "test"],
            environment=environment,
        )
        self.assertNotEqual(collision.returncode, 0)
        self.assertEqual(self.manifest("lease-collision")["status"], "locked")
        self.assertTrue(slot.exists())

    def test_post_command_snapshot_failure_cannot_strand_owned_lease(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        original_snapshot = run_evidence.snapshot_repository_results
        calls = 0

        def flaky_snapshot(path: Path) -> list[dict[str, object]]:
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("post-command snapshot failed")
            return original_snapshot(path)

        original_release = run_evidence.release_command_lease

        def release_after_manifest(
            lease: dict[str, object],
            slot: Path | None,
            expected_identity: tuple[int, int],
            expected_claim_identity: tuple[int, int],
            *,
            package: str,
            assertion: str,
            attempt: str,
            owner: str,
            command_digest: str,
            trigger: str,
        ) -> None:
            self.assertTrue(
                (self.attempt_root("lease-snapshot-failure") / "manifest.json").is_file()
            )
            self.assertIsNotNone(slot)
            assert slot is not None
            self.assertTrue((slot / "claim.json").is_file())
            original_release(
                lease,
                slot,
                expected_identity,
                expected_claim_identity,
                package=package,
                assertion=assertion,
                attempt=attempt,
                owner=owner,
                command_digest=command_digest,
                trigger=trigger,
            )

        argv = [
            "--root",
            str(self.evidence),
            "--package",
            "WP-TEST-01",
            "--assertion",
            "LEASE-FINALLY",
            "--attempt",
            "lease-snapshot-failure",
            "--repo-head",
            f"ios={self.git('rev-parse', 'HEAD')}",
            "--cwd",
            str(self.repo),
            "--artifact",
            "results/lease.txt",
            "--owner",
            "owner-1",
            "--lock-root",
            str(self.locks),
            "--",
            "xcodebuild",
            "test",
        ]
        with mock.patch.object(
            run_evidence, "snapshot_repository_results", side_effect=flaky_snapshot
        ), mock.patch.object(
            run_evidence, "release_command_lease", side_effect=release_after_manifest
        ), mock.patch.dict(
            os.environ, {"PATH": f"{fake_bin}:{os.environ['PATH']}"}
        ):
            result = run_evidence.run(argv)
        self.assertEqual(result, 1)
        slot = self.locks / "resource-simulator-device-slot-1"
        self.assertFalse(slot.exists())
        release = json.loads(
            (
                self.attempt_root("lease-snapshot-failure")
                / "lease-release.json"
            ).read_text()
        )
        self.assertTrue(release["released"])
        manifest = self.manifest("lease-snapshot-failure")
        self.assertEqual(manifest["status"], "failed")
        self.assertIsNone(manifest["repositoryLocalResults"]["afterSha256"])
        self.assertFalse(manifest["lease"]["released"])
        self.assertTrue(manifest["lease"]["releaseAfterManifest"])

    def test_body_base_exception_still_releases_owned_lease(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        original_snapshot = run_evidence.snapshot_repository_results
        calls = 0

        def interrupted_snapshot(path: Path) -> list[dict[str, object]]:
            nonlocal calls
            calls += 1
            if calls == 2:
                raise KeyboardInterrupt()
            return original_snapshot(path)

        argv = [
            "--root",
            str(self.evidence),
            "--package",
            "WP-TEST-01",
            "--assertion",
            "LEASE-BASE-EXCEPTION",
            "--attempt",
            "lease-base-exception",
            "--repo-head",
            f"ios={self.git('rev-parse', 'HEAD')}",
            "--cwd",
            str(self.repo),
            "--artifact",
            "results/lease.txt",
            "--owner",
            "owner-1",
            "--lock-root",
            str(self.locks),
            "--",
            "xcodebuild",
            "test",
        ]
        with mock.patch.object(
            run_evidence,
            "snapshot_repository_results",
            side_effect=interrupted_snapshot,
        ), mock.patch.dict(
            os.environ, {"PATH": f"{fake_bin}:{os.environ['PATH']}"}
        ):
            with self.assertRaises(KeyboardInterrupt):
                run_evidence.run(argv)
        slot = self.locks / "resource-simulator-device-slot-1"
        self.assertFalse(slot.exists())
        attempt = self.attempt_root("lease-base-exception")
        release = json.loads((attempt / "lease-release.json").read_text())
        self.assertTrue(release["released"])
        manifest = json.loads((attempt / "manifest.json").read_text())
        self.assertEqual(manifest["status"], "failed")
        self.assertIn("repository-results verification", manifest["failure"])
        self.assertIn("KeyboardInterrupt", manifest["failure"])
        self.assertFalse(manifest["lease"]["released"])
        self.assertTrue(manifest["lease"]["releaseAfterManifest"])
        self.assertEqual(
            release["manifestSha256"],
            run_evidence.sha256_file(attempt / "manifest.json"),
        )

    def test_manifest_base_exception_still_releases_owned_lease(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        original_writer = run_evidence.write_json_exclusive

        def interrupted_manifest(path: Path, value: object) -> None:
            if path.name == "manifest.json":
                raise KeyboardInterrupt()
            original_writer(path, value)

        argv = [
            "--root",
            str(self.evidence),
            "--package",
            "WP-TEST-01",
            "--assertion",
            "LEASE-MANIFEST-EXCEPTION",
            "--attempt",
            "lease-manifest-exception",
            "--repo-head",
            f"ios={self.git('rev-parse', 'HEAD')}",
            "--cwd",
            str(self.repo),
            "--artifact",
            "results/lease.txt",
            "--owner",
            "owner-1",
            "--lock-root",
            str(self.locks),
            "--",
            "xcodebuild",
            "test",
        ]
        with mock.patch.object(
            run_evidence,
            "write_json_exclusive",
            side_effect=interrupted_manifest,
        ), mock.patch.dict(
            os.environ, {"PATH": f"{fake_bin}:{os.environ['PATH']}"}
        ):
            with self.assertRaises(KeyboardInterrupt):
                run_evidence.run(argv)
        slot = self.locks / "resource-simulator-device-slot-1"
        self.assertFalse(slot.exists())
        attempt = self.attempt_root("lease-manifest-exception")
        release = json.loads((attempt / "lease-release.json").read_text())
        self.assertTrue(release["released"])
        self.assertIsNone(release["manifestSha256"])
        self.assertIn("failure", release)
        self.assertFalse((attempt / "manifest.json").exists())

    def test_replaced_attempt_layout_never_receives_release_receipt(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        attempt = self.attempt_root("lease-layout-replacement")
        backup = attempt.with_name(f"{attempt.name}-original")
        slot = self.locks / "resource-simulator-device-slot-1"
        original_verify = run_evidence.AttemptContext.verify_private_layout
        replaced = False

        def replace_after_release(context: run_evidence.AttemptContext) -> None:
            nonlocal replaced
            manifest = context.attempt_root / "manifest.json"
            if manifest.is_file() and not slot.exists() and not replaced:
                context.attempt_root.rename(backup)
                context.attempt_root.mkdir(mode=0o700)
                context.attempt_root.chmod(0o700)
                replaced = True
            original_verify(context)

        argv = [
            "--root",
            str(self.evidence),
            "--package",
            "WP-TEST-01",
            "--assertion",
            "LEASE-LAYOUT-REPLACEMENT",
            "--attempt",
            "lease-layout-replacement",
            "--repo-head",
            f"ios={self.git('rev-parse', 'HEAD')}",
            "--cwd",
            str(self.repo),
            "--artifact",
            "results/lease.txt",
            "--owner",
            "owner-1",
            "--lock-root",
            str(self.locks),
            "--",
            "xcodebuild",
            "test",
        ]
        with mock.patch.object(
            run_evidence.AttemptContext,
            "verify_private_layout",
            autospec=True,
            side_effect=replace_after_release,
        ), mock.patch.dict(
            os.environ, {"PATH": f"{fake_bin}:{os.environ['PATH']}"}
        ):
            result = run_evidence.run(argv)
        self.assertEqual(result, 1)
        self.assertTrue(replaced)
        self.assertFalse(slot.exists())
        self.assertFalse((attempt / "lease-release.json").exists())
        self.assertFalse((backup / "lease-release.json").exists())
        self.assertTrue((backup / "manifest.json").is_file())

    def test_release_base_exception_uses_identity_checked_cleanup(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        argv = [
            "--root",
            str(self.evidence),
            "--package",
            "WP-TEST-01",
            "--assertion",
            "LEASE-RELEASE-EXCEPTION",
            "--attempt",
            "lease-release-exception",
            "--repo-head",
            f"ios={self.git('rev-parse', 'HEAD')}",
            "--cwd",
            str(self.repo),
            "--artifact",
            "results/lease.txt",
            "--owner",
            "owner-1",
            "--lock-root",
            str(self.locks),
            "--",
            "xcodebuild",
            "test",
        ]
        with mock.patch.object(
            run_evidence,
            "release_command_lease",
            side_effect=KeyboardInterrupt(),
        ), mock.patch.dict(
            os.environ, {"PATH": f"{fake_bin}:{os.environ['PATH']}"}
        ):
            with self.assertRaises(KeyboardInterrupt):
                run_evidence.run(argv)
        slot = self.locks / "resource-simulator-device-slot-1"
        self.assertFalse(slot.exists())
        attempt = self.attempt_root("lease-release-exception")
        manifest = json.loads((attempt / "manifest.json").read_text())
        release = json.loads((attempt / "lease-release.json").read_text())
        self.assertFalse(manifest["lease"]["released"])
        self.assertTrue(manifest["lease"]["releaseAfterManifest"])
        self.assertTrue(release["released"])
        self.assertEqual(
            release["manifestSha256"],
            run_evidence.sha256_file(attempt / "manifest.json"),
        )

    def test_every_declared_simulator_device_trigger_is_recognized(self) -> None:
        run_evidence.validate_lease_policy(ROOT)
        commands = (
            ["xcodebuild", "test", "-project", "Fixture.xcodeproj"],
            ["python3", "scripts/visual/run_native_matrix.py"],
            ["python3", "scripts/qa/device/run_matrix.py"],
            ["python3", "scripts/performance/run_paired_performance.py"],
        )
        for command, trigger in zip(commands, run_evidence.LEASE_TRIGGERS, strict=True):
            with self.subTest(trigger=trigger):
                self.assertEqual(run_evidence.command_triggers_lease(command), trigger)
        self.assertIsNone(
            run_evidence.command_triggers_lease(["xcodebuild", "build"])
        )

    def test_parent_lease_is_reentrant_and_attempt_failure_releases_own_slot(self) -> None:
        fake_bin = self.make_fake_xcodebuild()
        environment = {"PATH": f"{fake_bin}:{os.environ['PATH']}"}
        slot = self.locks / "resource-simulator-device-slot-1"
        self.locks.mkdir(mode=0o700)
        self.locks.chmod(0o700)
        slot.mkdir(mode=0o700)
        slot.chmod(0o700)
        parent_claim = slot / "claim.json"
        parent_claim.write_text(
            json.dumps(
                {
                    "scope": "package",
                    "packageId": "WP-TEST-01",
                    "ownerTaskId": "owner-1",
                }
            ),
            encoding="utf-8",
        )
        parent_claim.chmod(0o600)
        reentrant = self.run_cli(
            "lease-parent",
            "results/lease.txt",
            command=["xcodebuild", "test"],
            environment=environment,
        )
        self.assertEqual(reentrant.returncode, 0, reentrant.stderr)
        self.assertTrue(slot.exists())
        self.assertEqual(
            self.manifest("lease-parent")["lease"]["mode"],
            "parent-claim-reentrant",
        )

        (slot / "claim.json").unlink()
        slot.rmdir()
        failed = self.run_cli(
            "lease-failure",
            "results/lease.txt",
            command=["xcodebuild", "test"],
            environment={**environment, "FAKE_XCODE_FAIL": "1"},
        )
        self.assertNotEqual(failed.returncode, 0)
        self.assertFalse(slot.exists())

    def test_rejects_repository_local_root_traversal_and_symlink_artifact(self) -> None:
        inside = self.run_cli(
            "inside-root",
            "results/value.txt",
            root=self.repo / "evidence",
            command=[sys.executable, "-c", "print('no')"],
        )
        self.assertNotEqual(inside.returncode, 0)
        traversal = self.run_cli(
            "traversal",
            "results/../escape.txt",
            command=[sys.executable, "-c", "print('no')"],
        )
        self.assertNotEqual(traversal.returncode, 0)

        target = self.root / "outside.txt"
        target.write_text("outside\n", encoding="utf-8")
        script = "from pathlib import Path; import sys; Path(sys.argv[1]).symlink_to(sys.argv[2])"
        symlink = self.run_cli(
            "symlink-artifact",
            "results/link.txt",
            command=[sys.executable, "-c", script, "results/link.txt", str(target)],
        )
        self.assertNotEqual(symlink.returncode, 0)
        self.assertEqual(self.manifest("symlink-artifact")["status"], "failed")

        outside_directory = self.root / "outside-directory"
        outside_directory.mkdir()
        parent_script = (
            "from pathlib import Path; import sys; "
            "parent=Path(sys.argv[1]).parent; parent.rmdir(); "
            "parent.symlink_to(sys.argv[2], target_is_directory=True); print('{}')"
        )
        parent_symlink = self.run_cli(
            "symlink-artifact-parent",
            "results/nested/value.json",
            command=[
                sys.executable,
                "-c",
                parent_script,
                "results/nested/value.json",
                str(outside_directory),
            ],
        )
        self.assertNotEqual(parent_symlink.returncode, 0)
        self.assertFalse((outside_directory / "value.json").exists())

    def test_rejects_evidence_and_lease_roots_inside_foreign_git_repository(self) -> None:
        foreign = self.root / "foreign-repository"
        foreign.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=foreign, check=True)

        evidence_root = foreign / "evidence"
        evidence = self.run_cli(
            "foreign-evidence-root",
            "results/value.txt",
            root=evidence_root,
            command=[sys.executable, "-c", "print('must not run')"],
        )
        self.assertNotEqual(evidence.returncode, 0)
        self.assertIn("outside every Git repository", evidence.stderr)
        self.assertFalse(evidence_root.exists())

        fake_bin = self.make_fake_xcodebuild()
        lease_root = foreign / "locks"
        lease = self.run_cli(
            "foreign-lease-root",
            "results/value.txt",
            lock_root=lease_root,
            command=["xcodebuild", "test"],
            environment={"PATH": f"{fake_bin}:{os.environ['PATH']}"},
        )
        self.assertNotEqual(lease.returncode, 0)
        self.assertIn("outside every Git repository", lease.stderr)
        self.assertFalse(lease_root.exists())
        self.assertEqual(
            subprocess.run(
                ["git", "status", "--porcelain", "--untracked-files=all"],
                cwd=foreign,
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            ).stdout,
            "",
        )

        bare = self.root / "foreign-bare.git"
        subprocess.run(["git", "init", "--bare", "-q", str(bare)], check=True)
        bare_root = bare / "evidence"
        poisoned = {
            "GIT_DIR": str(self.repo / ".git"),
            "GIT_WORK_TREE": str(self.repo),
            "GIT_COMMON_DIR": str(self.repo / ".git"),
            "GIT_CEILING_DIRECTORIES": str(bare),
            "GIT_OPTIONAL_LOCKS": "1",
        }
        before_environment = os.environ.copy()
        with mock.patch.dict(os.environ, poisoned, clear=False):
            sanitized = run_evidence.git_discovery_environment()
            self.assertEqual(sanitized["GIT_OPTIONAL_LOCKS"], "0")
            self.assertNotIn("GIT_DIR", sanitized)
            self.assertNotIn("GIT_WORK_TREE", sanitized)
            self.assertNotIn("GIT_COMMON_DIR", sanitized)
            self.assertNotIn("GIT_CEILING_DIRECTORIES", sanitized)
            self.assertEqual(
                run_evidence.containing_git_repository(bare_root), bare.resolve()
            )
            external = self.root / "not-a-repository"
            external.mkdir()
            self.assertIsNone(
                run_evidence.containing_git_repository(external / "evidence")
            )
        self.assertEqual(os.environ, before_environment)
        bare_result = self.run_cli(
            "foreign-bare-root",
            "results/value.txt",
            root=bare_root,
            command=[sys.executable, "-c", "print('must not run')"],
        )
        self.assertNotEqual(bare_result.returncode, 0)
        self.assertIn("outside every Git repository", bare_result.stderr)
        self.assertFalse(bare_root.exists())

    def test_direct_and_shell_commands_receive_sanitized_git_environment(self) -> None:
        poisoned = {
            "GIT_DIR": str(self.repo / ".git"),
            "GIT_WORK_TREE": str(self.repo),
            "GIT_COMMON_DIR": str(self.repo / ".git"),
            "GIT_OPTIONAL_LOCKS": "1",
        }
        probe = (
            "printf '%s|%s|%s' \"${GIT_DIR-unset}\" "
            "\"${GIT_WORK_TREE-unset}\" \"${GIT_OPTIONAL_LOCKS-unset}\""
        )
        cases = (
            ("direct-git-environment", [], ["/bin/sh", "-c", probe]),
            ("shell-git-environment", ["--shell"], [probe]),
        )
        for attempt, options, command in cases:
            with self.subTest(attempt=attempt):
                result = self.run_cli(
                    attempt,
                    "results/environment.txt",
                    options=options,
                    command=command,
                    environment=poisoned,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                artifact = (
                    self.attempt_root(attempt) / "results/environment.txt"
                ).read_text()
                self.assertEqual(artifact, "unset|unset|0")

    def test_fingerprint_git_failure_redacts_stderr_from_attempt_evidence(self) -> None:
        private_name = "owner-private-filename-do-not-persist.txt"
        original_run = subprocess.run

        def fail_fingerprint_status(
            command: list[str], *args: object, **kwargs: object
        ) -> subprocess.CompletedProcess[bytes] | subprocess.CompletedProcess[str]:
            if (
                command[:2] == ["git", "status"]
                and "-z" in command
                and Path(str(kwargs.get("cwd"))).resolve() == self.repo.resolve()
            ):
                return subprocess.CompletedProcess(
                    command, 128, b"", private_name.encode("utf-8")
                )
            return original_run(command, *args, **kwargs)

        argv = [
            "--root",
            str(self.evidence),
            "--package",
            "WP-TEST-01",
            "--assertion",
            "FINGERPRINT-STDERR-REDACTION",
            "--attempt",
            "fingerprint-stderr-redaction",
            "--repo-head",
            f"ios={self.git('rev-parse', 'HEAD')}",
            "--cwd",
            str(self.repo),
            "--artifact",
            "results/fingerprint.json",
            "--owner",
            "owner-1",
            "--lock-root",
            str(self.locks),
            "--fingerprint-git-owner-state",
            str(self.repo),
        ]
        with mock.patch.object(
            run_evidence.subprocess,
            "run",
            side_effect=fail_fingerprint_status,
        ):
            result = run_evidence.run(argv)
        self.assertEqual(result, 1)
        attempt = self.attempt_root("fingerprint-stderr-redaction")
        persisted = b"".join(
            path.read_bytes() for path in attempt.rglob("*") if path.is_file()
        )
        self.assertNotIn(private_name.encode("utf-8"), persisted)
        self.assertIn(b"stderrSha256", persisted)


if __name__ == "__main__":
    unittest.main()
