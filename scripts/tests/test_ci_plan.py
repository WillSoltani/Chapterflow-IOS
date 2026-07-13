#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import statistics
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/ci"))

import plan  # noqa: E402
import generate_package_graph  # noqa: E402


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
        self.assertTrue(result["run_app_build"])
        self.assertTrue(result["run_ui_tests"])
        self.assertTrue(result["run_lint"])
        self.assertEqual(set(result["affected_packages"]), set(self.all_packages))

    def test_markdown_only_selects_lightweight_validation(self) -> None:
        result = self.make_plan(["docs/ios/CI_PERFORMANCE_AND_OPTIMIZATION.md"])
        self.assertTrue(result["docs_only"])
        self.assertFalse(result["run_lint"])
        self.assertFalse(result["run_app_build"])
        self.assertFalse(result["run_ui_tests"])
        self.assertEqual(result["affected_packages"], [])

    def test_workflow_change_selects_full_validation(self) -> None:
        self.assert_full(self.make_plan([".github/workflows/pr-v2.yml"]))

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


if __name__ == "__main__":
    unittest.main()
