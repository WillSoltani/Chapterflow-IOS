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


def workflow_text() -> str:
    return WORKFLOW_PATH.read_text(encoding="utf-8")


def aggregate_script() -> str:
    workflow = workflow_text()
    step = workflow.split("      - name: Verify every planned result\n", 1)[1]
    marker = "          python3 - <<'PY'\n"
    start = step.index(marker) + len(marker)
    end = step.index("\n          PY", start)
    return textwrap.dedent(step[start:end])


def plan_payload(*, app: bool) -> dict[str, object]:
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
        "schema_version": 1,
        "docs_only": not app,
        "run_lint": app,
        "run_app_build": app,
        "run_ui_tests": app,
        "run_full_packages": app,
        "high_risk": app,
        "affected_packages": packages,
        "package_matrix": {"include": include},
        "reason_codes": ["workflow_test"],
    }


def run_aggregate(*, app: bool, compile_boundary_result: str) -> subprocess.CompletedProcess[str]:
    expected_job_result = "success" if app else "skipped"
    environment = os.environ.copy()
    environment.update(
        {
            "APP_RESULT": expected_job_result,
            "COMPILE_BOUNDARY_RESULT": compile_boundary_result,
            "LINT_RESULT": expected_job_result,
            "PACKAGE_RESULT": expected_job_result,
            "PLAN_JSON": json.dumps(plan_payload(app=app)),
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


if __name__ == "__main__":
    unittest.main()
