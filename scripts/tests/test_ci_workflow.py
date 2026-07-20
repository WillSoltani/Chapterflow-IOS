#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = ROOT / ".github/workflows/pr-v2.yml"
LEGACY_WORKFLOW_PATH = ROOT / ".github/workflows/pr.yml"
sys.path.insert(0, str(ROOT / "scripts/ci"))

import plan  # noqa: E402
import required_gate  # noqa: E402


GRAPH = plan.load_graph(ROOT)
ALL_PACKAGES = plan.testable_packages(ROOT, GRAPH)
CONTRACT_PROOF = json.dumps(
    {
        "schema_version": 1,
        "operations": 83,
        "producers": 92,
        "matrix_rows": 29,
        "relations": 92,
        "policy_digest_valid": True,
    },
    separators=(",", ":"),
    sort_keys=True,
)


def workflow_text() -> str:
    return WORKFLOW_PATH.read_text(encoding="utf-8")


def plan_payload(*, app: bool) -> dict[str, object]:
    if app:
        return required_gate.authoritative_plan_from_environment(
            ROOT, GRAPH, trusted_environment()
        )
    return plan.create_plan(
        root=ROOT,
        graph=GRAPH,
        changed_files=["docs/README.md"],
        base_sha="a" * 40,
        head_sha="b" * 40,
        merge_base="a" * 40,
        event="pull_request",
        mode="affected",
        labels=[],
        package_override=[],
        ui_override="auto",
        max_shards=2,
    )


def trusted_environment() -> dict[str, str]:
    def revision(name: str) -> str:
        return subprocess.run(
            ["git", "rev-parse", name],
            cwd=ROOT,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout.strip()

    return {
        "CI_BASE_SHA": revision("HEAD"),
        "CI_EVENT_NAME": "pull_request",
        "CI_HEAD_SHA": revision("HEAD"),
        "CI_INPUT_MODE": "affected",
        "CI_INPUT_PACKAGES": "",
        "CI_INPUT_SHARDS": "2",
        "CI_INPUT_UI": "auto",
        "CI_LABELS_JSON": "[]",
    }


def expected_results(
    selected: dict[str, object],
    *,
    compile_boundary_result: str,
    contract_result: str | None = None,
    contract_proof: str | None = None,
) -> dict[str, str]:
    contract_required = bool(selected["run_contract_semantics"])
    app_required = bool(selected["run_app_build"] or selected["run_ui_tests"])
    return {
        "app-and-ui": "success" if app_required else "skipped",
        "compile-boundaries": compile_boundary_result,
        "contract-proof": (
            CONTRACT_PROOF if contract_required else ""
        ) if contract_proof is None else contract_proof,
        "contract-semantics": (
            "success" if contract_required else "skipped"
        ) if contract_result is None else contract_result,
        "lint": "success" if selected["run_lint"] else "skipped",
        "package-tests": "success" if selected["affected_packages"] else "skipped",
        "plan": "success",
    }


def run_aggregate(
    *,
    app: bool,
    compile_boundary_result: str,
    contract_result: str | None = None,
    contract_proof: str | None = None,
    payload: dict[str, object] | None = None,
) -> subprocess.CompletedProcess[str]:
    if not app:
        raise ValueError("subprocess integration uses independently recomputed full authority")
    authority = trusted_environment()
    selected = copy.deepcopy(payload if payload is not None else plan_payload(app=True))
    results = expected_results(
        selected,
        compile_boundary_result=compile_boundary_result,
        contract_result=contract_result,
        contract_proof=contract_proof,
    )
    environment = os.environ.copy()
    environment.update(authority)
    environment.update(
        {
            "APP_RESULT": results["app-and-ui"],
            "COMPILE_BOUNDARY_RESULT": results["compile-boundaries"],
            "CONTRACT_PROOF": results["contract-proof"],
            "CONTRACT_RESULT": results["contract-semantics"],
            "LINT_RESULT": results["lint"],
            "PACKAGE_RESULT": results["package-tests"],
            "PLAN_JSON": json.dumps(selected),
            "PLAN_RESULT": results["plan"],
            "PYTHONDONTWRITEBYTECODE": "1",
        }
    )
    return subprocess.run(
        [sys.executable, str(ROOT / "scripts/ci/required_gate.py")],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
    )


def cache_classifier_scripts() -> dict[str, str]:
    source = workflow_text()
    scripts: dict[str, str] = {}
    for step_name in (
        "Summarize package shard",
        "Summarize app and UI validation",
    ):
        step = source.split(f"      - name: {step_name}\n", 1)[1].split(
            "\n      - name:", 1
        )[0]
        start = step.index("          cache_status=unavailable\n")
        end = step.index("          failure_category=none\n", start)
        scripts[step_name] = textwrap.dedent(step[start:end])
    return scripts


def run_cache_classifier(
    script: str,
    *,
    event: str,
    mode: str,
    outcome: str,
    hit: str,
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment.update(
        {
            "CACHE_HIT": hit,
            "EVENT_NAME": event,
            "INPUT_MODE": mode,
            "SOURCE_CACHE_OUTCOME": outcome,
        }
    )
    with tempfile.TemporaryDirectory() as directory:
        environment["GITHUB_OUTPUT"] = str(Path(directory) / "github-output.txt")
        return subprocess.run(
            [
                "bash",
                "-eu",
                "-o",
                "pipefail",
                "-c",
                f"{script}\nprintf '%s\\n' \"$cache_status\"\n",
            ],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )


class CIWorkflowTests(unittest.TestCase):
    def test_contract_job_runs_current_worktree_verifier_once_on_ubuntu(self) -> None:
        workflow = workflow_text()
        contract_job = workflow.split("\n  contract-semantics:\n", 1)[1].split(
            "\n  lint:\n", 1
        )[0]
        command = (
            "python3 scripts/contracts/verify_ios_incremental_contract_drift.py "
            "--layer worktree"
        )
        self.assertEqual(contract_job.count(command), 1)
        self.assertIn("name: Native Contract Semantics", contract_job)
        self.assertIn("runs-on: ubuntu-latest", contract_job)
        self.assertIn("fetch-depth: 0", contract_job)
        self.assertIn("persist-credentials: false", contract_job)
        self.assertNotIn("continue-on-error", contract_job)

    def test_authoritative_and_fallback_trigger_contracts(self) -> None:
        workflow = workflow_text()
        self.assertIn("name: CI — Required", workflow)
        self.assertIn(
            "types: [opened, synchronize, reopened, labeled, unlabeled]", workflow
        )
        self.assertNotIn("ready_for_review", workflow)
        self.assertIn("&& 'CI / Required'", workflow)
        self.assertIn("run: python3 scripts/ci/required_gate.py", workflow)
        required_job = workflow.split("\n  required:\n", 1)[1]
        self.assertIn("fetch-depth: 0", required_job)
        for authority in (
            "CI_BASE_SHA:",
            "CI_EVENT_NAME:",
            "CI_HEAD_SHA:",
            "CI_INPUT_MODE:",
            "CI_INPUT_PACKAGES:",
            "CI_INPUT_SHARDS:",
            "CI_INPUT_UI:",
            "CI_LABELS_JSON:",
        ):
            self.assertIn(authority, required_job)

        legacy = LEGACY_WORKFLOW_PATH.read_text(encoding="utf-8")
        trigger = legacy.split("\non:\n", 1)[1].split("\nconcurrency:\n", 1)[0]
        self.assertIn("workflow_dispatch:", trigger)
        self.assertNotIn("pull_request:", trigger)
        self.assertNotIn("push:", trigger)

    def test_compile_boundary_step_runs_once_in_app_job(self) -> None:
        workflow = workflow_text()
        command = "run: scripts/verify-wp-dev-01-compile-boundaries.sh"
        self.assertEqual(workflow.count(command), 1)
        app_job = workflow.split("\n  app-and-ui:\n", 1)[1].split(
            "\n  required:\n", 1
        )[0]
        self.assertEqual(app_job.count(command), 1)
        step = app_job.split(
            "      - name: Verify WP-DEV-01 non-Debug compile boundaries\n",
            1,
        )[1].split("\n      - name:", 1)[0]
        self.assertIn("id: compile-boundaries", step)
        self.assertIn("needs.plan.outputs.run_app_build == 'true'", step)
        self.assertNotIn("continue-on-error", step)
        self.assertLess(
            app_job.index("      - name: Set up exact iOS toolchain"),
            app_job.index(command),
        )

    def test_cache_status_provenance_is_exhaustive_in_every_lane(self) -> None:
        rows = (
            ("hit", "pull_request", "affected", "success", "true", "hit"),
            ("miss", "pull_request", "affected", "success", "false", "miss"),
            (
                "missing-output",
                "pull_request",
                "affected",
                "success",
                "",
                "unavailable",
            ),
            (
                "malformed-output",
                "pull_request",
                "affected",
                "success",
                "unknown",
                "unavailable",
            ),
            (
                "clean",
                "workflow_dispatch",
                "clean",
                "skipped",
                "false",
                "disabled-clean-mode",
            ),
            (
                "failure",
                "pull_request",
                "affected",
                "failure",
                "false",
                "restore-failed",
            ),
            (
                "cancelled",
                "pull_request",
                "affected",
                "cancelled",
                "false",
                "restore-cancelled",
            ),
            (
                "skipped",
                "pull_request",
                "affected",
                "skipped",
                "false",
                "not-run",
            ),
            (
                "unavailable",
                "pull_request",
                "affected",
                "",
                "unknown",
                "unavailable",
            ),
        )
        scripts = cache_classifier_scripts()
        workflow = workflow_text()
        self.assertEqual(
            workflow.count(
                "CACHE_HIT: ${{ steps.source-cache.outputs.cache-hit }}"
            ),
            2,
        )
        self.assertNotIn("outputs.cache-hit || 'false'", workflow)
        self.assertEqual(
            set(scripts),
            {"Summarize package shard", "Summarize app and UI validation"},
        )
        for step_name, script in scripts.items():
            for name, event, mode, outcome, hit, expected in rows:
                with self.subTest(step=step_name, row=name):
                    result = run_cache_classifier(
                        script,
                        event=event,
                        mode=mode,
                        outcome=outcome,
                        hit=hit,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip().splitlines()[-1], expected)

    def test_aggregate_accepts_successful_compile_boundary(self) -> None:
        result = run_aggregate(app=True, compile_boundary_result="success")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_aggregate_rejects_failed_compile_boundary_even_if_app_job_is_green(self) -> None:
        result = run_aggregate(app=True, compile_boundary_result="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("compile-boundaries: expected success", result.stderr)

    def test_aggregate_accepts_unrun_boundary_for_docs_only_plan(self) -> None:
        docs = plan_payload(app=False)
        errors = required_gate.verify_required(
            json.dumps(docs),
            expected_results(docs, compile_boundary_result=""),
            ALL_PACKAGES,
            GRAPH,
            docs,
        )
        self.assertEqual(errors, [])

    def test_aggregate_rejects_risk_inconsistent_all_skipped_plan(self) -> None:
        forged = plan_payload(app=True)
        for field in (
            "run_contract_semantics",
            "run_lint",
            "run_app_build",
            "run_ui_tests",
            "run_full_packages",
            "high_risk",
        ):
            forged[field] = False
        forged["affected_packages"] = []
        forged["package_matrix"] = {"include": []}

        result = run_aggregate(
            app=True,
            compile_boundary_result="skipped",
            payload=forged,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("risk classification requires full validation", result.stderr)

        forged_paths = plan_payload(app=False)
        result = run_aggregate(
            app=True,
            compile_boundary_result="skipped",
            payload=forged_paths,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "plan does not match independently recomputed authority", result.stderr
        )

    def test_aggregate_rejects_skipped_required_contract_job(self) -> None:
        result = run_aggregate(
            app=True,
            compile_boundary_result="success",
            contract_result="skipped",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("contract-semantics: expected success", result.stderr)

    def test_aggregate_rejects_failed_or_cancelled_contract_job(self) -> None:
        for observed in ("failure", "cancelled"):
            with self.subTest(observed=observed):
                result = run_aggregate(
                    app=True,
                    compile_boundary_result="success",
                    contract_result=observed,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    f"contract-semantics: expected success, observed '{observed}'",
                    result.stderr,
                )

    def test_aggregate_rejects_missing_or_malformed_contract_proof(self) -> None:
        for proof in ("", "not-json", '{"operations":83}'):
            with self.subTest(proof=proof):
                result = run_aggregate(
                    app=True,
                    compile_boundary_result="success",
                    contract_proof=proof,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("contract-semantics:", result.stderr)

    def test_aggregate_rejects_unplanned_contract_execution(self) -> None:
        docs = plan_payload(app=False)
        results = expected_results(
            docs,
            compile_boundary_result="",
            contract_result="success",
            contract_proof=CONTRACT_PROOF,
        )
        errors = required_gate.verify_required(
            json.dumps(docs),
            results,
            ALL_PACKAGES,
            GRAPH,
            docs,
        )
        self.assertTrue(
            any("contract-semantics: expected skipped" in error for error in errors)
        )


if __name__ == "__main__":
    unittest.main()
