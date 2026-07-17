#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = ROOT / ".github/workflows/pr-v2.yml"
LEGACY_WORKFLOW_PATH = ROOT / ".github/workflows/pr.yml"

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


def aggregate_script() -> str:
    workflow = workflow_text()
    step = workflow.split("      - name: Verify every planned result\n", 1)[1]
    marker = "          python3 - <<'PY'\n"
    start = step.index(marker) + len(marker)
    end = step.index("\n          PY", start)
    return textwrap.dedent(step[start:end])


def plan_payload(*, app: bool, contract: bool | None = None) -> dict[str, object]:
    contract = app if contract is None else contract
    packages = ["AppFeature"] if app else []
    include = (
        [
            {
                "shard": "1-of-1",
                "packages": packages,
                "estimated_seconds": 60.0,
            }
        ]
        if app
        else []
    )
    return {
        "schema_version": 2,
        "docs_only": not app,
        "run_contract_semantics": contract,
        "run_lint": app,
        "run_app_build": app,
        "run_ui_tests": app,
        "run_full_packages": app,
        "high_risk": app,
        "affected_packages": packages,
        "package_matrix": {"include": include},
        "reason_codes": ["workflow_test"],
    }


def run_aggregate(
    *,
    app: bool,
    compile_boundary_result: str,
    contract: bool | None = None,
    contract_result: str | None = None,
    contract_proof: str | None = None,
) -> subprocess.CompletedProcess[str]:
    contract = app if contract is None else contract
    expected_job_result = "success" if app else "skipped"
    expected_contract_result = "success" if contract else "skipped"
    environment = os.environ.copy()
    environment.update(
        {
            "APP_RESULT": expected_job_result,
            "COMPILE_BOUNDARY_RESULT": compile_boundary_result,
            "CONTRACT_PROOF": (
                CONTRACT_PROOF if contract else ""
            ) if contract_proof is None else contract_proof,
            "CONTRACT_RESULT": contract_result or expected_contract_result,
            "LINT_RESULT": expected_job_result,
            "PACKAGE_RESULT": expected_job_result,
            "PLAN_JSON": json.dumps(plan_payload(app=app, contract=contract)),
            "PLAN_RESULT": "success",
        }
    )
    return subprocess.run(
        [sys.executable, "-c", aggregate_script()],
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
        self.assertIn("types: [opened, synchronize, reopened]", workflow)
        for duplicate_event in ("labeled", "unlabeled", "ready_for_review"):
            self.assertNotIn(duplicate_event, workflow)
        self.assertIn("&& 'CI / Required'", workflow)

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

    def test_aggregate_accepts_successful_compile_boundary(self) -> None:
        result = run_aggregate(app=True, compile_boundary_result="success")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_aggregate_rejects_failed_compile_boundary_even_if_app_job_is_green(self) -> None:
        result = run_aggregate(app=True, compile_boundary_result="failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("compile-boundaries: expected success", result.stderr)

    def test_aggregate_accepts_unrun_boundary_for_docs_only_plan(self) -> None:
        result = run_aggregate(app=False, compile_boundary_result="")
        self.assertEqual(result.returncode, 0, result.stderr)

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
        result = run_aggregate(
            app=False,
            compile_boundary_result="",
            contract=False,
            contract_result="success",
            contract_proof=CONTRACT_PROOF,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("contract-semantics: expected skipped", result.stderr)


if __name__ == "__main__":
    unittest.main()
