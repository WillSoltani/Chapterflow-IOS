#!/usr/bin/env python3
"""Fail-closed verifier for the stable ChapterFlow development CI gate."""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

import plan as ci_plan


EXPECTED_CONTRACT_PROOF = {
    "schema_version": 1,
    "operations": 83,
    "producers": 92,
    "matrix_rows": 29,
    "relations": 92,
    "policy_digest_valid": True,
}

RESULT_ENVIRONMENTS = {
    "plan": "PLAN_RESULT",
    "contract-semantics": "CONTRACT_RESULT",
    "lint": "LINT_RESULT",
    "package-tests": "PACKAGE_RESULT",
    "app-and-ui": "APP_RESULT",
    "compile-boundaries": "COMPILE_BOUNDARY_RESULT",
}


def authoritative_plan_from_environment(
    root: Path,
    graph: dict[str, list[str]],
    environment: Mapping[str, str],
) -> dict[str, object]:
    """Recompute the complete plan from GitHub-owned event and input context."""

    required = (
        "CI_BASE_SHA",
        "CI_EVENT_NAME",
        "CI_HEAD_SHA",
        "CI_INPUT_MODE",
        "CI_INPUT_PACKAGES",
        "CI_INPUT_SHARDS",
        "CI_INPUT_UI",
        "CI_LABELS_JSON",
    )
    missing = [name for name in required if name not in environment]
    if missing:
        raise ci_plan.PlanError(f"missing trusted plan authority: {missing}")

    base_sha = environment["CI_BASE_SHA"]
    head_sha = environment["CI_HEAD_SHA"]
    if not base_sha or not head_sha:
        raise ci_plan.PlanError("trusted base/head authority is empty")

    labels_raw = environment["CI_LABELS_JSON"]
    labels = (
        []
        if not labels_raw or labels_raw == "null"
        else ci_plan.parse_labels(labels_raw)
    )
    try:
        max_shards = int(environment["CI_INPUT_SHARDS"])
    except ValueError as error:
        raise ci_plan.PlanError("trusted shard authority is not an integer") from error

    diff = ci_plan.resolve_git_diff(root, base_sha, head_sha)
    return ci_plan.create_plan(
        root=root,
        graph=graph,
        changed_files=diff.paths,
        base_sha=base_sha,
        head_sha=head_sha,
        merge_base=diff.merge_base,
        event=environment["CI_EVENT_NAME"],
        mode=environment["CI_INPUT_MODE"],
        labels=labels,
        package_override=ci_plan.parse_package_override(
            environment["CI_INPUT_PACKAGES"]
        ),
        ui_override=environment["CI_INPUT_UI"],
        max_shards=max_shards,
        diff_failed=diff.failed,
    )


def verify_required(
    plan_json: str,
    results: Mapping[str, str | None],
    allowed_packages: Sequence[str],
    graph: dict[str, list[str]],
    authoritative_plan: dict[str, object],
) -> list[str]:
    """Return every deterministic gate error; an empty list means success."""

    errors: list[str] = []
    if results.get("plan") != "success":
        errors.append(f"plan job result={results.get('plan')!r}")

    try:
        decoded = json.loads(plan_json)
    except (TypeError, json.JSONDecodeError) as error:
        return [*errors, f"malformed or missing plan output: {error}"]
    if not isinstance(decoded, dict):
        return [*errors, "malformed plan output: top level is not an object"]

    try:
        ci_plan.validate_plan(authoritative_plan, allowed_packages, graph)
    except ci_plan.PlanError as error:
        errors.append(f"invalid independently recomputed plan: {error}")
        return errors

    try:
        ci_plan.validate_plan(decoded, allowed_packages, graph)
    except ci_plan.PlanError as error:
        errors.append(f"invalid plan: {error}")
        return errors

    if decoded != authoritative_plan:
        differing_fields = sorted(
            key
            for key in set(decoded).union(authoritative_plan)
            if decoded.get(key) != authoritative_plan.get(key)
        )
        errors.append(
            "plan does not match independently recomputed authority; differing fields: "
            + ", ".join(differing_fields)
        )
        return errors

    affected = decoded["affected_packages"]
    if decoded["run_app_build"] and results.get("compile-boundaries") != "success":
        errors.append(
            "compile-boundaries: expected success, "
            f"observed {results.get('compile-boundaries')!r}"
        )
    elif not decoded["run_app_build"] and results.get("compile-boundaries") not in {
        None,
        "",
        "skipped",
    }:
        errors.append(
            "compile-boundaries: unplanned validation reported "
            f"{results.get('compile-boundaries')!r}"
        )

    expected = {
        "contract-semantics": decoded["run_contract_semantics"],
        "lint": decoded["run_lint"],
        "package-tests": bool(affected),
        "app-and-ui": decoded["run_app_build"] or decoded["run_ui_tests"],
    }
    for job, is_required in expected.items():
        wanted = "success" if is_required else "skipped"
        observed = results.get(job)
        if observed != wanted:
            errors.append(f"{job}: expected {wanted}, observed {observed!r}")

    proof_raw = results.get("contract-proof") or ""
    if expected["contract-semantics"]:
        try:
            proof = json.loads(proof_raw)
        except (TypeError, json.JSONDecodeError) as error:
            errors.append(f"contract-semantics: malformed proof output: {error}")
        else:
            if proof != EXPECTED_CONTRACT_PROOF:
                errors.append(
                    "contract-semantics: proof output does not match 83/92/29/92 "
                    "with a valid policy digest"
                )
    elif proof_raw:
        errors.append("contract-semantics: unplanned job emitted proof output")

    return errors


def results_from_environment(environment: Mapping[str, str]) -> dict[str, str]:
    results = {
        name: environment.get(variable, "")
        for name, variable in RESULT_ENVIRONMENTS.items()
    }
    results["contract-proof"] = environment.get("CONTRACT_PROOF", "")
    return results


def main() -> int:
    root = ci_plan.repository_root()
    try:
        graph = ci_plan.load_graph(root)
        ci_plan.verify_graph(root, graph)
        allowed_packages = ci_plan.testable_packages(root, graph)
        authoritative_plan = authoritative_plan_from_environment(root, graph, os.environ)
    except ci_plan.PlanError as error:
        print(f"aggregate failure: cannot establish package authority: {error}", file=sys.stderr)
        return 1

    plan_json = os.environ.get("PLAN_JSON", "")
    results = results_from_environment(os.environ)
    errors = verify_required(
        plan_json,
        results,
        allowed_packages,
        graph,
        authoritative_plan,
    )

    try:
        decoded = json.loads(plan_json)
    except (TypeError, json.JSONDecodeError):
        decoded = {}
    reasons = decoded.get("reason_codes", []) if isinstance(decoded, dict) else []
    affected = decoded.get("affected_packages", []) if isinstance(decoded, dict) else []
    print("Plan reasons:", ", ".join(reasons) if isinstance(reasons, list) else "invalid")
    print(
        "Packages:",
        ", ".join(affected) if isinstance(affected, list) and affected else "none",
    )
    for job in (
        "plan",
        "contract-semantics",
        "lint",
        "package-tests",
        "app-and-ui",
        "compile-boundaries",
    ):
        print(f"{job}: {results.get(job) or 'missing'}")

    if errors:
        for error in errors:
            print(f"aggregate failure: {error}", file=sys.stderr)
        return 1
    print("All required work succeeded and all unrequired work skipped explicitly.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
