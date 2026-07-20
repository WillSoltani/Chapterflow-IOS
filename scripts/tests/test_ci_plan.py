#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import statistics
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/ci"))

import plan  # noqa: E402
import generate_package_graph  # noqa: E402
import required_gate  # noqa: E402


class CIPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.graph = plan.load_graph(ROOT)
        plan.verify_graph(ROOT, cls.graph)
        cls.all_packages = plan.testable_packages(ROOT, cls.graph)

    def make_plan(
        self,
        paths: list[str],
        *,
        event: str = "pull_request",
        mode: str = "affected",
        labels: list[str] | None = None,
        packages: list[str] | None = None,
        ui: str = "auto",
        diff_failed: bool = False,
    ) -> dict[str, object]:
        return plan.create_plan(
            root=ROOT,
            graph=self.graph,
            changed_files=paths,
            base_sha="a" * 40,
            head_sha="b" * 40,
            merge_base="a" * 40,
            event=event,
            mode=mode,
            labels=labels or [],
            package_override=packages or [],
            ui_override=ui,
            max_shards=2,
            diff_failed=diff_failed,
        )

    def assert_full(self, result: dict[str, object]) -> None:
        self.assertTrue(result["run_full_packages"])
        self.assertTrue(result["run_contract_semantics"])
        self.assertTrue(result["run_app_build"])
        self.assertTrue(result["run_ui_tests"])
        self.assertTrue(result["run_lint"])
        self.assertEqual(set(result["affected_packages"]), set(self.all_packages))

    def test_supported_event_path_matrix(self) -> None:
        full = {
            "docs_only": False,
            "run_contract_semantics": True,
            "run_lint": True,
            "run_app_build": True,
            "run_ui_tests": True,
            "run_full_packages": True,
            "high_risk": True,
        }
        rows = (
            {
                "name": "pull-request-docs-safe-skip",
                "paths": ["docs/README.md"],
                "expected": {
                    "docs_only": True,
                    "run_contract_semantics": False,
                    "run_lint": False,
                    "run_app_build": False,
                    "run_ui_tests": False,
                    "run_full_packages": False,
                    "high_risk": False,
                },
                "affected": set(),
                "reasons": {"docs_only"},
            },
            {
                "name": "feature-logic",
                "paths": ["Packages/AIFeature/Sources/AIFeature/Audio/AudioPlayer.swift"],
                "expected": {
                    "docs_only": False,
                    "run_contract_semantics": True,
                    "run_lint": True,
                    "run_app_build": True,
                    "run_ui_tests": False,
                    "run_full_packages": False,
                    "high_risk": False,
                },
                "affected": {"AIFeature", "AppFeature", "LibraryFeature"},
                "reasons": {"package_impact", "contract_semantics"},
            },
            {
                "name": "ui-route",
                "paths": [
                    "Packages/LibraryFeature/Sources/LibraryFeature/Routes/LibraryRoute.swift"
                ],
                "expected": {
                    "docs_only": False,
                    "run_contract_semantics": True,
                    "run_lint": True,
                    "run_app_build": True,
                    "run_ui_tests": True,
                    "run_full_packages": False,
                    "high_risk": False,
                },
                "affected": {"AppFeature", "LibraryFeature"},
                "reasons": {"package_impact", "ui_risk", "contract_semantics"},
            },
            {
                "name": "shared-foundation",
                "paths": ["Packages/CoreKit/Sources/CoreKit/Clock.swift"],
                "expected": full,
                "affected": "all",
                "reasons": {"foundation_or_shared_package", "contract_semantics"},
            },
            {
                "name": "contract-policy",
                "paths": ["contracts/native-ios/v1/incremental-drift-policy.json"],
                "expected": full,
                "affected": "all",
                "reasons": {
                    "contract_semantics_policy_or_verifier",
                    "contract_semantics",
                },
            },
            {
                "name": "workflow",
                "paths": [".github/workflows/pr-v2.yml"],
                "expected": full,
                "affected": "all",
                "reasons": {"workflow_or_ci_change", "contract_semantics"},
            },
            {
                "name": "planner-test",
                "paths": ["scripts/tests/test_ci_checks.py"],
                "expected": full,
                "affected": "all",
                "reasons": {"ci_planner_test_change", "contract_semantics"},
            },
            {
                "name": "unknown",
                "paths": ["Unclassified/thing.data"],
                "expected": full,
                "affected": "all",
                "reasons": {"unknown_path", "contract_semantics"},
            },
            {
                "name": "rename-docs-to-workflow",
                "paths": ["docs/old.md", ".github/workflows/new.yml"],
                "expected": full,
                "affected": "all",
                "reasons": {"workflow_or_ci_change", "contract_semantics"},
            },
            {
                "name": "main",
                "paths": ["docs/README.md"],
                "event": "push",
                "expected": full,
                "affected": "all",
                "reasons": {"push_main", "contract_semantics"},
            },
            {
                "name": "merge-queue",
                "paths": ["docs/README.md"],
                "event": "merge_group",
                "expected": full,
                "affected": "all",
                "reasons": {"merge_queue_full", "contract_semantics"},
            },
            {
                "name": "schedule",
                "paths": ["docs/README.md"],
                "event": "schedule",
                "expected": full,
                "affected": "all",
                "reasons": {"scheduled_full", "contract_semantics"},
            },
            {
                "name": "manual-clean",
                "paths": ["docs/README.md"],
                "event": "workflow_dispatch",
                "mode": "clean",
                "expected": full,
                "affected": "all",
                "reasons": {"mode_clean", "contract_semantics"},
            },
            {
                "name": "full-label",
                "paths": ["docs/README.md"],
                "labels": ["ci-full"],
                "expected": full,
                "affected": "all",
                "reasons": {"ci_full_label", "contract_semantics"},
            },
        )

        self.assertEqual(
            set(plan.SUPPORTED_EVENTS),
            {"pull_request", "push", "merge_group", "schedule", "workflow_dispatch"},
        )
        for row in rows:
            with self.subTest(row=row["name"]):
                result = self.make_plan(
                    row["paths"],
                    event=row.get("event", "pull_request"),
                    mode=row.get("mode", "affected"),
                    labels=row.get("labels", []),
                )
                for field, expected in row["expected"].items():
                    self.assertEqual(result[field], expected, field)
                expected_affected = (
                    set(self.all_packages)
                    if row["affected"] == "all"
                    else row["affected"]
                )
                self.assertEqual(set(result["affected_packages"]), expected_affected)
                self.assertTrue(row["reasons"].issubset(result["reason_codes"]))
                if "unknown_path" not in row["reasons"]:
                    self.assertNotIn("unknown_path", result["reason_codes"])

        for event in ("pull_request_target", "workflow_run", "issue_comment", "unknown"):
            with self.subTest(unsupported_event=event):
                with self.assertRaises(plan.PlanError):
                    self.make_plan(["docs/README.md"], event=event)
        with self.assertRaises(plan.PlanError):
            self.make_plan(["docs/README.md"], mode="fast")
        with self.assertRaises(plan.PlanError):
            self.make_plan(["docs/README.md"], ui="maybe")
        for path in (
            ".",
            " docs/README.md",
            "docs/README.md ",
            "docs\\README.md",
            "docs//README.md",
            "docs/./README.md",
            "docs/../README.md",
            "/docs/README.md",
            "docs/README.md\n",
        ):
            with self.subTest(noncanonical_path=repr(path)):
                with self.assertRaises(plan.PlanError):
                    self.make_plan([path])

    def test_required_failure_and_skip_provenance(self) -> None:
        def expected_results(result: dict[str, object]) -> dict[str, str]:
            contract_required = bool(result["run_contract_semantics"])
            app_required = bool(result["run_app_build"] or result["run_ui_tests"])
            return {
                "plan": "success",
                "contract-semantics": "success" if contract_required else "skipped",
                "contract-proof": (
                    json.dumps(required_gate.EXPECTED_CONTRACT_PROOF, sort_keys=True)
                    if contract_required
                    else ""
                ),
                "lint": "success" if result["run_lint"] else "skipped",
                "package-tests": "success" if result["affected_packages"] else "skipped",
                "app-and-ui": "success" if app_required else "skipped",
                "compile-boundaries": "success" if result["run_app_build"] else "skipped",
            }

        docs = self.make_plan(["docs/README.md"])
        full = self.make_plan([".github/workflows/pr-v2.yml"])
        for result in (docs, full):
            with self.subTest(valid=result["reason_codes"]):
                errors = required_gate.verify_required(
                    json.dumps(result), expected_results(result), self.all_packages
                )
                self.assertEqual(errors, [])

        for outcome in ("failure", "cancelled", "skipped", ""):
            with self.subTest(plan_outcome=outcome):
                results = expected_results(full)
                results["plan"] = outcome
                self.assertTrue(
                    required_gate.verify_required(
                        json.dumps(full), results, self.all_packages
                    )
                )

        planned_jobs = (
            "contract-semantics",
            "lint",
            "package-tests",
            "app-and-ui",
            "compile-boundaries",
        )
        for job in planned_jobs:
            for outcome in ("failure", "cancelled", "skipped", ""):
                with self.subTest(planned_job=job, outcome=outcome):
                    results = expected_results(full)
                    results[job] = outcome
                    self.assertTrue(
                        required_gate.verify_required(
                            json.dumps(full), results, self.all_packages
                        )
                    )

        for job in ("contract-semantics", "lint", "package-tests", "app-and-ui"):
            with self.subTest(unplanned_job=job):
                results = expected_results(docs)
                results[job] = "success"
                self.assertTrue(
                    required_gate.verify_required(
                        json.dumps(docs), results, self.all_packages
                    )
                )

        malformed_full = copy.deepcopy(full)
        malformed_full["run_contract_semantics"] = False
        self.assertTrue(
            required_gate.verify_required(
                json.dumps(malformed_full), expected_results(full), self.all_packages
            )
        )
        for payload in ("", "null", "[]", "{not-json"):
            with self.subTest(malformed_plan=payload):
                self.assertTrue(
                    required_gate.verify_required(
                        payload, expected_results(full), self.all_packages
                    )
                )

        for proof in ("", "{}", "not-json"):
            with self.subTest(contract_proof=proof):
                results = expected_results(full)
                results["contract-proof"] = proof
                self.assertTrue(
                    required_gate.verify_required(
                        json.dumps(full), results, self.all_packages
                    )
                )

        workflow = (ROOT / ".github/workflows/pr-v2.yml").read_text(encoding="utf-8")
        for provenance in (
            "disabled-clean-mode",
            "restore-failed",
            "restore-cancelled",
            "cache_status=hit",
            "cache_status=miss",
            "cancelled",
            "if-no-files-found: error",
            "scripts/ci/required_gate.py",
        ):
            self.assertIn(provenance, workflow)
        self.assertNotIn("disabled-or-miss", workflow)
        for workflow_path in (
            ".github/workflows/pr-v2.yml",
            ".github/workflows/contract-drift.yml",
            ".github/workflows/pr.yml",
        ):
            self.assertNotIn(
                "secrets.", (ROOT / workflow_path).read_text(encoding="utf-8")
            )

    def test_markdown_only_selects_lightweight_validation(self) -> None:
        result = self.make_plan(["docs/ios/CI_PERFORMANCE_AND_OPTIMIZATION.md"])
        self.assertTrue(result["docs_only"])
        self.assertFalse(result["run_contract_semantics"])
        self.assertFalse(result["run_lint"])
        self.assertFalse(result["run_app_build"])
        self.assertFalse(result["run_ui_tests"])
        self.assertEqual(result["affected_packages"], [])

    def test_workflow_change_selects_full_validation(self) -> None:
        self.assert_full(self.make_plan([".github/workflows/pr-v2.yml"]))

    def test_every_production_swift_root_selects_contract_semantics(self) -> None:
        paths = (
            "Packages/AIFeature/Sources/AIFeature/Audio/AudioPlayer.swift",
            "ChapterFlow/ChapterFlowApp.swift",
            "ChapterflowWidgets/ChapterflowWidgetsBundle.swift",
            "NotificationService/NotificationServiceExtension.swift",
            "NotificationContent/NotificationViewController.swift",
            "ShareExtension/ShareView.swift",
            "ActionExtension/ActionView.swift",
            "SharedExtensionKit/ExtensionOutboxWriter.swift",
        )
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue(self.make_plan([path])["run_contract_semantics"])

    def test_nonproduction_swift_test_does_not_select_contract_semantics(self) -> None:
        result = self.make_plan(
            ["Packages/AIFeature/Tests/AIFeatureTests/AudioPlayerTests.swift"]
        )
        self.assertFalse(result["run_contract_semantics"])

    def test_contract_policy_and_verifier_select_fast_and_full_proof(self) -> None:
        for path in sorted(plan.CONTRACT_SEMANTICS_EXACT_PATHS):
            with self.subTest(path=path):
                result = self.make_plan([path])
                self.assert_full(result)
                self.assertTrue(result["run_contract_semantics"])
                self.assertIn(
                    "contract_semantics_policy_or_verifier", result["reason_codes"]
                )
                self.assertNotIn("unknown_path", result["reason_codes"])

    def test_corekit_change_selects_every_package_app_and_ui(self) -> None:
        self.assert_full(
            self.make_plan(["Packages/CoreKit/Sources/CoreKit/Clock.swift"])
        )

    def test_feature_change_selects_owner_and_reverse_dependencies(self) -> None:
        result = self.make_plan(
            ["Packages/AIFeature/Sources/AIFeature/Audio/AudioPlayer.swift"]
        )
        self.assertEqual(
            set(result["affected_packages"]),
            {"AIFeature", "AppFeature", "LibraryFeature"},
        )
        self.assertTrue(result["run_app_build"])
        self.assertFalse(result["run_ui_tests"])

    def test_appfeature_change_selects_full_app_and_ui(self) -> None:
        result = self.make_plan(
            ["Packages/AppFeature/Sources/AppFeature/AppRootView.swift"]
        )
        self.assert_full(result)
        self.assertTrue(result["high_risk"])
        flattened = [
            package
            for shard in result["package_matrix"]["include"]
            for package in shard["packages"]
        ]
        self.assertEqual(flattened.count("AppFeature"), 1)

    def test_compile_boundary_script_forces_known_full_validation(self) -> None:
        result = self.make_plan([plan.COMPILE_BOUNDARY_SCRIPT])
        self.assert_full(result)
        self.assertTrue(result["high_risk"])
        self.assertIn("compile_boundary_gate_change", result["reason_codes"])
        self.assertNotIn("unknown_path", result["reason_codes"])

    def test_package_resolved_change_selects_full_validation(self) -> None:
        self.assert_full(self.make_plan(["Packages/AuthKit/Package.resolved"]))

    def test_ui_test_only_change_selects_full_app_and_ui(self) -> None:
        self.assert_full(
            self.make_plan(["ChapterFlowUITests/Flows/SignInFlowTests.swift"])
        )

    def test_ci_full_label_forces_full_validation(self) -> None:
        self.assert_full(
            self.make_plan(["docs/README.md"], labels=["ci-full"])
        )

    def test_unknown_path_fails_safe_to_full(self) -> None:
        result = self.make_plan(["Unclassified/thing.data"])
        self.assert_full(result)
        self.assertIn("unknown_path", result["reason_codes"])

    def test_nested_agents_instructions_force_full(self) -> None:
        self.assert_full(self.make_plan(["docs/AGENTS.md"]))

    def test_empty_or_unavailable_diff_fails_safe_to_full(self) -> None:
        self.assert_full(self.make_plan([]))
        result = self.make_plan([], diff_failed=True)
        self.assert_full(result)
        self.assertIn("diff_unavailable", result["reason_codes"])

    def test_rename_from_docs_to_executable_cannot_escape_full_scope(self) -> None:
        result = self.make_plan(
            ["docs/old.md", ".github/workflows/renamed-from-docs.yml"]
        )
        self.assert_full(result)

    def test_git_diff_preserves_deleted_and_renamed_risk_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(
                ["git", "config", "user.email", "ci-tests@example.invalid"],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "CI Tests"], cwd=root, check=True
            )
            (root / "docs").mkdir()
            (root / "docs/old.md").write_text("same content\n", encoding="utf-8")
            (root / ".github/workflows").mkdir(parents=True)
            (root / ".github/workflows/deleted.yml").write_text(
                "name: deleted\n", encoding="utf-8"
            )
            subprocess.run(["git", "add", "docs", ".github"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "base"], cwd=root, check=True)
            base = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=root,
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            ).stdout.strip()

            subprocess.run(
                ["git", "mv", "docs/old.md", ".github/workflows/renamed.yml"],
                cwd=root,
                check=True,
            )
            (root / ".github/workflows/deleted.yml").unlink()
            subprocess.run(["git", "add", "-A"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "rename-delete"], cwd=root, check=True)
            head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=root,
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            ).stdout.strip()

            diff = plan.resolve_git_diff(root, base, head)
            self.assertFalse(diff.failed)
            self.assertEqual(
                set(diff.paths),
                {
                    "docs/old.md",
                    ".github/workflows/renamed.yml",
                    ".github/workflows/deleted.yml",
                },
            )
            self.assert_full(self.make_plan(list(diff.paths)))

    def test_ui_view_change_selects_ui(self) -> None:
        result = self.make_plan(
            [
                "Packages/LibraryFeature/Sources/LibraryFeature/Views/"
                "BookDetailView.swift"
            ]
        )
        self.assertTrue(result["run_ui_tests"])
        self.assertTrue(result["run_app_build"])

    def test_storekit_and_entitlement_changes_select_ui(self) -> None:
        for file_name in ("StoreKitService.swift", "EntitlementService.swift"):
            with self.subTest(file_name=file_name):
                result = self.make_plan(
                    [
                        "Packages/PaywallFeature/Sources/PaywallFeature/"
                        + file_name
                    ]
                )
                self.assertTrue(result["run_ui_tests"])
                self.assertTrue(result["run_app_build"])

    def test_navigation_route_change_selects_ui(self) -> None:
        result = self.make_plan(
            [
                "Packages/LibraryFeature/Sources/LibraryFeature/Routes/"
                "LibraryRoute.swift"
            ]
        )
        self.assertTrue(result["run_ui_tests"])
        self.assertTrue(result["run_app_build"])

    def test_ui_surfaces_outside_views_directories_select_ui(self) -> None:
        for path in (
            "Packages/ReaderFeature/Sources/ReaderFeature/Controls/ReaderToolbar.swift",
            "Packages/ReaderFeature/Sources/ReaderFeature/Appearance/ReaderBodyText.swift",
            "Packages/SettingsFeature/Sources/SettingsFeature/DeleteAccountSheet.swift",
            "Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/ScenarioRow.swift",
        ):
            with self.subTest(path=path):
                self.assertTrue(self.make_plan([path])["run_ui_tests"])

    def test_full_modes_and_events_are_authoritative(self) -> None:
        for event, mode in (
            ("push", "affected"),
            ("schedule", "affected"),
            ("merge_group", "affected"),
            ("workflow_dispatch", "full"),
            ("workflow_dispatch", "benchmark"),
            ("workflow_dispatch", "clean"),
        ):
            with self.subTest(event=event, mode=mode):
                result = self.make_plan(["docs/README.md"], event=event, mode=mode)
                self.assert_full(result)

    def test_full_mode_cannot_disable_ui(self) -> None:
        result = self.make_plan(
            ["docs/README.md"],
            event="workflow_dispatch",
            mode="full",
            ui="off",
        )
        self.assert_full(result)
        self.assertIn("manual_ui_off_ignored", result["reason_codes"])

    def test_manual_package_override_is_validated(self) -> None:
        result = self.make_plan(
            [], event="workflow_dispatch", packages=["SyncEngine"]
        )
        self.assertEqual(
            set(result["affected_packages"]),
            {"AppFeature", "SettingsFeature", "SyncEngine"},
        )
        self.assertFalse(result["run_full_packages"])
        self.assertNotIn("empty_diff", result["reason_codes"])
        with self.assertRaises(plan.PlanError):
            self.make_plan(
                [], event="workflow_dispatch", packages=["NotAPackage"]
            )

    def test_graph_represents_every_manifest_and_dependency(self) -> None:
        plan.verify_graph(ROOT, self.graph)
        manifests = {path.parent.name for path in (ROOT / "Packages").glob("*/Package.swift")}
        self.assertEqual(set(self.graph), manifests)
        self.assertEqual(len(self.graph), 19)
        self.assertEqual(len(self.all_packages), 19)
        self.assertEqual(set(self.all_packages), set(self.graph))
        self.assertIn("AppFeature", self.all_packages)
        self.assertIn("SyncEngine", self.all_packages)

    def test_semantic_graph_parser_reads_swiftpm_file_system_dependencies(self) -> None:
        payload = {
            "dependencies": [
                {
                    "fileSystem": [
                        {
                            "identity": "corekit",
                            "path": str(ROOT / "Packages/CoreKit"),
                        }
                    ]
                },
                {"sourceControl": [{"identity": "remote"}]},
            ]
        }
        self.assertEqual(
            generate_package_graph.local_dependencies(
                payload,
                ROOT / "Packages",
                set(self.graph),
            ),
            ["CoreKit"],
        )

    def test_package_weights_recompute_from_raw_baseline(self) -> None:
        baseline = json.loads(
            (ROOT / "scripts/ci/baseline-runs.json").read_text(encoding="utf-8")
        )
        durations = json.loads(
            (ROOT / "scripts/ci/package-durations.json").read_text(encoding="utf-8")
        )
        samples: dict[str, list[float]] = {}
        for measurement in baseline["green_pull_request_measurements"]:
            for package in measurement["package_tests"]:
                samples.setdefault(package["name"], []).append(
                    float(package["duration_seconds"])
                )
        self.assertEqual(set(samples), set(durations["p50_seconds"]))
        for package, expected in durations["p50_seconds"].items():
            with self.subTest(package=package):
                self.assertEqual(
                    round(statistics.median(samples[package]), 1),
                    expected,
                )
        self.assertNotIn("AppFeature", durations["p50_seconds"])
        self.assertEqual(
            set(durations["unmeasured_packages"]),
            {"AppFeature", "SyncEngine"},
        )
        appfeature_matrix = plan.build_package_matrix(
            ["AppFeature"],
            durations["p50_seconds"],
            durations["affinity_groups"],
            max_shards=2,
        )
        self.assertEqual(
            appfeature_matrix["include"][0]["estimated_seconds"],
            durations["unmeasured_default_seconds"],
        )

    def test_matrix_union_is_exact_and_unique(self) -> None:
        result = self.make_plan([".github/workflows/pr-v2.yml"])
        include = result["package_matrix"]["include"]
        flattened = [package for shard in include for package in shard["packages"]]
        self.assertEqual(set(flattened), set(result["affected_packages"]))
        self.assertEqual(len(flattened), len(set(flattened)))
        self.assertEqual(len(flattened), 19)
        self.assertEqual(flattened.count("AppFeature"), 1)
        self.assertTrue(all(shard["packages"] for shard in include))

    def test_malformed_plan_is_rejected(self) -> None:
        result = self.make_plan([".github/workflows/pr-v2.yml"])
        malformed = copy.deepcopy(result)
        malformed["package_matrix"] = {"include": []}
        with self.assertRaises(plan.PlanError):
            plan.validate_plan(malformed, self.all_packages)
        malformed = copy.deepcopy(result)
        malformed["run_ui_tests"] = "true"
        with self.assertRaises(plan.PlanError):
            plan.validate_plan(malformed, self.all_packages)
        malformed = copy.deepcopy(result)
        del malformed["run_contract_semantics"]
        with self.assertRaises(plan.PlanError):
            plan.validate_plan(malformed, self.all_packages)
        malformed = copy.deepcopy(result)
        malformed["run_contract_semantics"] = "true"
        with self.assertRaises(plan.PlanError):
            plan.validate_plan(malformed, self.all_packages)


if __name__ == "__main__":
    unittest.main()
