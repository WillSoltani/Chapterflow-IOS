#!/usr/bin/env python3
"""Conservative, repository-owned change planner for ChapterFlow CI.

The planner deliberately fails toward broader validation. It can inspect a real
git merge-base diff or accept explicit paths for deterministic unit tests.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable, Sequence


SCHEMA_VERSION = 2
GRAPH_SCHEMA_VERSION = 2

SUPPORTED_EVENTS = (
    "pull_request",
    "push",
    "merge_group",
    "schedule",
    "workflow_dispatch",
)
SUPPORTED_MODES = ("affected", "full", "benchmark", "clean")
SUPPORTED_UI_OVERRIDES = ("auto", "on", "off")

FOUNDATION_PACKAGES = {
    "AppFeature",
    "CoreKit",
    "DesignSystem",
    "Fixtures",
    "Models",
    "Networking",
    "Persistence",
}

FULL_PREFIXES = (
    ".github/actions/",
    ".github/workflows/",
    "ChapterFlow.xcodeproj/",
    "ChapterFlow/",
    "ChapterFlowUITests/",
    "Config/",
    "scripts/ci/",
)

APP_EXTENSION_PREFIXES = (
    "ActionExtension/",
    "ChapterflowWidgets/",
    "NotificationContent/",
    "NotificationService/",
    "ShareExtension/",
    "SharedExtensionKit/",
)

CONTRACT_SEMANTICS_EXACT_PATHS = {
    "contracts/native-ios/v1/incremental-drift-policy.json",
    "scripts/contracts/verify_ios_incremental_contract_drift.py",
}

FULL_EXACT_PATHS = {
    "AGENTS.md",
    "ChapterFlow.xctestplan",
    "Secrets.example.xcconfig",
}

COMPILE_BOUNDARY_SCRIPT = "scripts/verify-wp-dev-01-compile-boundaries.sh"

UI_RISK_PACKAGES = {
    "AIFeature",
    "AuthKit",
    "EngagementFeature",
    "LibraryFeature",
    "NotificationsFeature",
    "OnboardingFeature",
    "PaywallFeature",
    "QuizFeature",
    "ReaderFeature",
    "SettingsFeature",
    "SocialFeature",
}

UI_RISK_COMPONENTS = {
    "appdelegate",
    "appmodel",
    "approot",
    "auth",
    "bootstrap",
    "coordinator",
    "model",
    "navigation",
    "entitlement",
    "purchase",
    "route",
    "router",
    "scene",
    "storekit",
    "subscription",
    "view",
}

# UI-bearing feature sources default to UI validation. Exceptions must be
# narrow, source-backed pure-logic areas with a planner canary. A UI-looking
# symbol inside an exception still triggers UI through UI_RISK_COMPONENTS.
UI_SAFE_SOURCE_PREFIXES = {
    "AIFeature": (
        "Packages/AIFeature/Sources/AIFeature/Audio/",
    ),
}

REASON_CODES = {
    "app_host",
    "ci_full_label",
    "ci_planner_test_change",
    "compile_boundary_gate_change",
    "contract_semantics",
    "contract_semantics_policy_or_verifier",
    "diff_unavailable",
    "docs_only",
    "embedded_extension_change",
    "empty_diff",
    "execution_policy_or_shared_config",
    "foundation_or_shared_package",
    "manifest_or_lockfile",
    "manual_package_override",
    "manual_ui_off_ignored",
    "manual_ui_on",
    "merge_queue_full",
    "mode_benchmark",
    "mode_clean",
    "mode_full",
    "no_executable_impact",
    "package_impact",
    "project_configuration",
    "push_main",
    "scheduled_full",
    "shared_build_configuration",
    "shared_test_configuration",
    "ui_risk",
    "ui_test_surface",
    "unknown_path",
    "workflow_or_ci_change",
}

class PlanError(RuntimeError):
    """A deterministic planning or validation failure."""


@dataclass(frozen=True)
class DiffResult:
    paths: tuple[str, ...]
    merge_base: str
    failed: bool = False


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _run_git(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=root,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _normalise_path(raw_path: str) -> str:
    if not isinstance(raw_path, str):
        raise PlanError(f"changed path is not text: {raw_path!r}")
    if not raw_path.isprintable():
        raise PlanError(f"changed path contains a control character: {raw_path!r}")
    if raw_path != raw_path.strip() or "\\" in raw_path:
        raise PlanError(f"noncanonical changed path: {raw_path!r}")
    candidate = PurePosixPath(raw_path)
    if (
        not raw_path
        or not candidate.parts
        or candidate.is_absolute()
        or ".." in candidate.parts
        or str(candidate) != raw_path
    ):
        raise PlanError(f"unsafe or empty changed path: {raw_path!r}")
    return str(candidate)


def resolve_git_diff(root: Path, base: str, head: str) -> DiffResult:
    if not base or not head or set(base) == {"0"}:
        return DiffResult((), "unavailable", failed=True)

    merge_base_result = _run_git(root, "merge-base", base, head)
    if merge_base_result.returncode != 0:
        return DiffResult((), "unavailable", failed=True)
    merge_base = merge_base_result.stdout.strip()
    if not re.fullmatch(r"[0-9a-fA-F]{40}", merge_base):
        return DiffResult((), "unavailable", failed=True)

    diff = subprocess.run(
        [
            "git",
            "diff",
            "--name-status",
            "--find-renames",
            "--diff-filter=ACDMRTUXB",
            "-z",
            merge_base,
            head,
        ],
        cwd=root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if diff.returncode != 0:
        return DiffResult((), merge_base, failed=True)

    tokens = diff.stdout.decode("utf-8", errors="surrogateescape").split("\0")
    if tokens and tokens[-1] == "":
        tokens.pop()

    paths: list[str] = []
    index = 0
    try:
        while index < len(tokens):
            status = tokens[index]
            index += 1
            if not status:
                raise PlanError("empty git diff status")
            if status[0] in {"R", "C"}:
                old_path, new_path = tokens[index], tokens[index + 1]
                index += 2
                paths.extend((_normalise_path(old_path), _normalise_path(new_path)))
            else:
                paths.append(_normalise_path(tokens[index]))
                index += 1
    except (IndexError, PlanError):
        return DiffResult((), merge_base, failed=True)

    return DiffResult(tuple(sorted(set(paths))), merge_base)


def manifest_digests(root: Path) -> dict[str, str]:
    manifests = sorted((root / "Packages").glob("*/Package.swift"))
    if not manifests:
        raise PlanError("no package manifests discovered")
    return {
        manifest.parent.name: hashlib.sha256(manifest.read_bytes()).hexdigest()
        for manifest in manifests
    }


def load_graph(root: Path) -> dict[str, list[str]]:
    graph_path = root / "scripts/ci/package-graph.json"
    try:
        payload = json.loads(graph_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read package graph: {error}") from error

    if payload.get("schema_version") != GRAPH_SCHEMA_VERSION:
        raise PlanError("unsupported package graph schema")
    if payload.get("generated_by") != "swift package dump-package":
        raise PlanError("package graph was not generated from SwiftPM semantics")
    package_payload = payload.get("packages")
    if not isinstance(package_payload, dict) or not package_payload:
        raise PlanError("package graph has no packages")

    digests = manifest_digests(root)
    graph: dict[str, list[str]] = {}
    for package, value in package_payload.items():
        if not isinstance(package, str) or not isinstance(value, dict):
            raise PlanError("malformed package graph entry")
        dependencies = value.get("dependencies")
        manifest_sha256 = value.get("manifest_sha256")
        if not isinstance(dependencies, list) or not all(
            isinstance(item, str) for item in dependencies
        ):
            raise PlanError(f"malformed dependencies for {package}")
        if (
            not isinstance(manifest_sha256, str)
            or not re.fullmatch(r"[0-9a-f]{64}", manifest_sha256)
            or digests.get(package) != manifest_sha256
        ):
            raise PlanError(f"stale or malformed manifest digest for {package}")
        graph[package] = sorted(set(dependencies))

    if set(graph) != set(digests):
        raise PlanError("package graph does not represent every current manifest")

    unknown_dependencies = {
        dependency
        for dependencies in graph.values()
        for dependency in dependencies
        if dependency not in graph
    }
    if unknown_dependencies:
        raise PlanError(
            f"package graph contains unknown dependencies: {sorted(unknown_dependencies)}"
        )
    return dict(sorted(graph.items()))


def verify_graph(root: Path, graph: dict[str, list[str]]) -> None:
    if graph != load_graph(root):
        raise PlanError("package graph changed during verification")


def testable_packages(root: Path, graph: dict[str, list[str]]) -> list[str]:
    packages = [
        package
        for package in graph
        if any((root / "Packages" / package / "Tests").rglob("*.swift"))
    ]
    if not packages:
        raise PlanError("no testable packages discovered")
    return sorted(packages)


def reverse_dependencies(graph: dict[str, list[str]]) -> dict[str, set[str]]:
    reverse = {package: set() for package in graph}
    for package, dependencies in graph.items():
        for dependency in dependencies:
            reverse[dependency].add(package)
    return reverse


def reverse_closure(
    changed_packages: Iterable[str], graph: dict[str, list[str]]
) -> set[str]:
    reverse = reverse_dependencies(graph)
    selected = set(changed_packages)
    pending = list(selected)
    while pending:
        package = pending.pop()
        for dependent in reverse[package]:
            if dependent not in selected:
                selected.add(dependent)
                pending.append(dependent)
    return selected


def load_duration_weights(root: Path) -> tuple[dict[str, float], list[list[str]]]:
    path = root / "scripts/ci/package-durations.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read package duration evidence: {error}") from error
    weights = payload.get("p50_seconds")
    affinities = payload.get("affinity_groups", [])
    if not isinstance(weights, dict) or not all(
        isinstance(name, str)
        and isinstance(value, (int, float))
        and not isinstance(value, bool)
        and value > 0
        for name, value in weights.items()
    ):
        raise PlanError("invalid package duration weights")
    if not isinstance(affinities, list) or not all(
        isinstance(group, list) and all(isinstance(name, str) for name in group)
        for group in affinities
    ):
        raise PlanError("invalid package affinity groups")
    return {name: float(value) for name, value in weights.items()}, affinities


def build_package_matrix(
    selected_packages: Sequence[str],
    weights: dict[str, float],
    affinity_groups: Sequence[Sequence[str]],
    max_shards: int,
) -> dict[str, list[dict[str, object]]]:
    selected = sorted(set(selected_packages))
    if not selected:
        return {"include": []}
    if max_shards < 1 or max_shards > 4:
        raise PlanError("max_shards must be between 1 and 4")

    shard_count = 1 if len(selected) <= 6 else min(max_shards, len(selected))
    if shard_count == 1:
        estimate = round(sum(weights.get(package, 60.0) for package in selected), 1)
        return {
            "include": [
                {
                    "shard": "1-of-1",
                    "packages": selected,
                    "estimated_seconds": estimate,
                }
            ]
        }

    remaining = set(selected)
    work_items: list[tuple[list[str], float]] = []
    for affinity in affinity_groups:
        group = sorted(remaining.intersection(affinity))
        if len(group) > 1:
            remaining.difference_update(group)
            work_items.append(
                (group, sum(weights.get(package, 60.0) for package in group))
            )
    work_items.extend(
        ([package], weights.get(package, 60.0)) for package in sorted(remaining)
    )
    work_items.sort(key=lambda item: (-item[1], item[0]))

    shards: list[list[str]] = [[] for _ in range(shard_count)]
    totals = [0.0 for _ in range(shard_count)]
    for packages, estimate in work_items:
        target = min(range(shard_count), key=lambda index: (totals[index], index))
        shards[target].extend(packages)
        totals[target] += estimate

    include: list[dict[str, object]] = []
    for index, packages in enumerate(shards):
        if not packages:
            raise PlanError("planner produced an empty package shard")
        include.append(
            {
                "shard": f"{index + 1}-of-{shard_count}",
                "packages": sorted(packages),
                "estimated_seconds": round(totals[index], 1),
            }
        )

    flattened = [
        package for shard in include for package in shard["packages"]  # type: ignore[index]
    ]
    if sorted(flattened) != selected or len(flattened) != len(set(flattened)):
        raise PlanError("package matrix omitted or duplicated a requested package")
    return {"include": include}


def is_docs_only_path(path: str) -> bool:
    if path.startswith("docs/") and path.endswith(".md"):
        return True
    return path in {
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "LICENSE.md",
        "README.md",
    }


def package_for_path(path: str, graph: dict[str, list[str]]) -> str | None:
    parts = PurePosixPath(path).parts
    if len(parts) >= 2 and parts[0] == "Packages" and parts[1] in graph:
        return parts[1]
    return None


def path_forces_full(path: str, package: str | None) -> str | None:
    if path == COMPILE_BOUNDARY_SCRIPT:
        return "compile_boundary_gate_change"
    if path in CONTRACT_SEMANTICS_EXACT_PATHS:
        return "contract_semantics_policy_or_verifier"
    if path in FULL_EXACT_PATHS or PurePosixPath(path).name == "AGENTS.md":
        return "execution_policy_or_shared_config"
    if path.startswith(FULL_PREFIXES):
        if path.startswith((".github/actions/", ".github/workflows/", "scripts/ci/")):
            return "workflow_or_ci_change"
        if path.startswith("ChapterFlowUITests/"):
            return "ui_test_surface"
        if path.startswith("ChapterFlow.xcodeproj/"):
            return "project_configuration"
        if path.startswith("ChapterFlow/"):
            return "app_host"
        return "shared_build_configuration"
    if path.endswith((".xctestplan", ".xcscheme")):
        return "shared_test_configuration"
    if PurePosixPath(path).name in {"Package.swift", "Package.resolved"}:
        return "manifest_or_lockfile"
    if package in FOUNDATION_PACKAGES:
        return "foundation_or_shared_package"
    if path.startswith("scripts/tests/test_ci_"):
        return "ci_planner_test_change"
    return None


def package_path_needs_ui(path: str, package: str) -> bool:
    if package not in UI_RISK_PACKAGES or "/Sources/" not in path:
        return False
    lowered_parts = [part.lower() for part in PurePosixPath(path).parts]
    stem = PurePosixPath(path).stem.lower()
    if any(
        marker in part
        for marker in UI_RISK_COMPONENTS
        for part in [*lowered_parts, stem]
    ):
        return True
    safe_prefixes = UI_SAFE_SOURCE_PREFIXES.get(package, ())
    return not any(path.startswith(prefix) for prefix in safe_prefixes)


def path_needs_contract_semantics(path: str) -> bool:
    if path in CONTRACT_SEMANTICS_EXACT_PATHS:
        return True
    if not path.endswith(".swift"):
        return False
    if path.startswith("Packages/") and "/Sources/" in path:
        return True
    return path.startswith(("ChapterFlow/", *APP_EXTENSION_PREFIXES))


def _add_reason(reasons: list[str], reason: str) -> None:
    if reason not in reasons:
        reasons.append(reason)


def create_plan(
    *,
    root: Path,
    graph: dict[str, list[str]],
    changed_files: Sequence[str],
    base_sha: str,
    head_sha: str,
    merge_base: str,
    event: str,
    mode: str,
    labels: Sequence[str],
    package_override: Sequence[str],
    ui_override: str,
    max_shards: int,
    diff_failed: bool = False,
) -> dict[str, object]:
    if event not in SUPPORTED_EVENTS:
        raise PlanError(f"unsupported event: {event!r}")
    if mode not in SUPPORTED_MODES:
        raise PlanError(f"unsupported mode: {mode!r}")
    if ui_override not in SUPPORTED_UI_OVERRIDES:
        raise PlanError(f"unsupported UI override: {ui_override!r}")
    normalised = sorted({_normalise_path(path) for path in changed_files})
    full_packages = testable_packages(root, graph)
    weights, affinities = load_duration_weights(root)
    reasons: list[str] = []

    docs_only = bool(normalised) and all(is_docs_only_path(path) for path in normalised)
    force_full = False
    high_risk = False

    if diff_failed:
        force_full = high_risk = True
        _add_reason(reasons, "diff_unavailable")
    manual_affected_override = (
        event == "workflow_dispatch"
        and mode == "affected"
        and bool(package_override)
        and not diff_failed
    )
    if not normalised and not manual_affected_override:
        force_full = high_risk = True
        _add_reason(reasons, "empty_diff")
    if event == "push":
        force_full = high_risk = True
        _add_reason(reasons, "push_main")
    elif event == "schedule":
        force_full = high_risk = True
        _add_reason(reasons, "scheduled_full")
    elif event == "merge_group":
        force_full = high_risk = True
        _add_reason(reasons, "merge_queue_full")
    if mode in {"full", "benchmark", "clean"}:
        force_full = high_risk = True
        _add_reason(reasons, f"mode_{mode}")
    if "ci-full" in labels:
        force_full = high_risk = True
        _add_reason(reasons, "ci_full_label")

    directly_changed_packages: set[str] = set()
    unknown_paths: list[str] = []
    app_extension_change = False
    ui_risk = False

    for path in normalised:
        package = package_for_path(path, graph)
        if package:
            directly_changed_packages.add(package)
        full_reason = path_forces_full(path, package)
        if full_reason:
            force_full = high_risk = True
            _add_reason(reasons, full_reason)
            continue
        if package:
            _add_reason(reasons, "package_impact")
            if package_path_needs_ui(path, package):
                ui_risk = True
                _add_reason(reasons, "ui_risk")
            continue
        if is_docs_only_path(path):
            continue
        if path.startswith(APP_EXTENSION_PREFIXES):
            app_extension_change = True
            _add_reason(reasons, "embedded_extension_change")
            continue
        unknown_paths.append(path)

    if unknown_paths:
        force_full = high_risk = True
        _add_reason(reasons, "unknown_path")

    invalid_override = sorted(set(package_override) - set(graph))
    if invalid_override:
        raise PlanError(f"unknown package override: {invalid_override}")
    directly_changed_packages.update(package_override)
    if package_override:
        docs_only = False
        _add_reason(reasons, "manual_package_override")

    impacted = reverse_closure(directly_changed_packages, graph)
    selected = set(full_packages) if force_full else impacted
    selected.intersection_update(full_packages)

    run_full_packages = force_full
    run_contract_semantics = force_full or any(
        path_needs_contract_semantics(path) for path in normalised
    )
    if run_contract_semantics:
        _add_reason(reasons, "contract_semantics")
    run_lint = force_full or any(path.endswith(".swift") for path in normalised)
    app_linked_packages = set(graph) - {"Fixtures"}
    run_app_build = force_full or app_extension_change or bool(
        directly_changed_packages.intersection(app_linked_packages)
    )
    run_ui_tests = force_full or ui_risk

    if docs_only and not force_full:
        _add_reason(reasons, "docs_only")
        selected.clear()
        run_lint = run_app_build = run_ui_tests = False

    if ui_override == "on":
        docs_only = False
        if "docs_only" in reasons:
            reasons.remove("docs_only")
        run_ui_tests = run_app_build = True
        _add_reason(reasons, "manual_ui_on")
    elif ui_override == "off" and run_ui_tests:
        _add_reason(reasons, "manual_ui_off_ignored")

    if run_ui_tests:
        run_app_build = True

    matrix = build_package_matrix(
        sorted(selected), weights, affinities, max_shards=max_shards
    )
    plan: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "merge_base": merge_base,
        "event": event,
        "mode": mode,
        "changed_files": normalised,
        "docs_only": docs_only and not force_full,
        "run_contract_semantics": run_contract_semantics,
        "run_lint": run_lint,
        "run_app_build": run_app_build,
        "run_ui_tests": run_ui_tests,
        "run_full_packages": run_full_packages,
        "affected_packages": sorted(selected),
        "package_matrix": matrix,
        "high_risk": high_risk,
        "reason_codes": reasons or ["no_executable_impact"],
    }
    validate_plan(plan, full_packages, graph)
    return plan


def _validate_semantic_risk_floor(
    plan: dict[str, object],
    allowed_packages: Sequence[str],
    graph: dict[str, list[str]],
) -> None:
    """Reject plans that structurally parse but under-select required work."""

    allowed = set(allowed_packages)
    if not allowed or allowed - set(graph):
        raise PlanError("semantic validation lacks the authoritative package graph")

    changed_files = plan["changed_files"]
    affected = set(plan["affected_packages"])
    reasons = set(plan["reason_codes"])
    event = plan["event"]
    mode = plan["mode"]

    required_reasons: set[str] = set()
    full_required = False

    event_reasons = {
        "push": "push_main",
        "schedule": "scheduled_full",
        "merge_group": "merge_queue_full",
    }
    if event in event_reasons:
        full_required = True
        required_reasons.add(event_reasons[event])
    if mode in {"full", "benchmark", "clean"}:
        full_required = True
        required_reasons.add(f"mode_{mode}")

    if plan.get("merge_base") == "unavailable":
        full_required = True
        required_reasons.add("diff_unavailable")
    if "diff_unavailable" in reasons or "ci_full_label" in reasons:
        full_required = True

    manual_override = "manual_package_override" in reasons
    if manual_override and (event != "workflow_dispatch" or mode != "affected"):
        raise PlanError(
            "manual package override provenance is not valid for this event/mode"
        )
    if not changed_files:
        if manual_override:
            if not affected:
                raise PlanError("manual package override selected no testable package")
        else:
            full_required = True
            required_reasons.add("empty_diff")

    directly_changed_packages: set[str] = set()
    required_contract = False
    required_lint = False
    required_app_build = False
    required_ui = False

    for path in changed_files:
        package = package_for_path(path, graph)
        if package:
            directly_changed_packages.add(package)

        full_reason = path_forces_full(path, package)
        if full_reason:
            full_required = True
            required_reasons.add(full_reason)
        elif package:
            required_reasons.add("package_impact")
        elif is_docs_only_path(path):
            pass
        elif path.startswith(APP_EXTENSION_PREFIXES):
            required_app_build = True
            required_reasons.add("embedded_extension_change")
        else:
            full_required = True
            required_reasons.add("unknown_path")

        if package and package_path_needs_ui(path, package):
            required_ui = True
            required_reasons.add("ui_risk")
        if path_needs_contract_semantics(path):
            required_contract = True
        if path.endswith(".swift"):
            required_lint = True

    impacted = reverse_closure(directly_changed_packages, graph).intersection(allowed)
    missing_impacted = impacted - affected
    if missing_impacted:
        raise PlanError(
            "affected package selection omitted reverse dependents: "
            f"{sorted(missing_impacted)}"
        )

    app_linked_packages = set(graph) - {"Fixtures"}
    if directly_changed_packages.intersection(app_linked_packages):
        required_app_build = True

    if manual_override:
        required_reasons.add("manual_package_override")
        override_closure = reverse_closure(affected, graph).intersection(allowed)
        missing_override_dependents = override_closure - affected
        if missing_override_dependents:
            raise PlanError(
                "manual package override omitted reverse dependents: "
                f"{sorted(missing_override_dependents)}"
            )

    if "manual_ui_on" in reasons:
        required_app_build = required_ui = True
    if "manual_ui_off_ignored" in reasons and not plan["run_ui_tests"]:
        raise PlanError("manual UI-off provenance hid required UI validation")

    if full_required:
        required_contract = required_lint = required_app_build = required_ui = True
        if not plan["run_full_packages"]:
            raise PlanError("risk classification requires full validation")

    required_decisions = {
        "run_contract_semantics": required_contract,
        "run_lint": required_lint,
        "run_app_build": required_app_build,
        "run_ui_tests": required_ui,
    }
    for field, required in required_decisions.items():
        if required and not plan[field]:
            raise PlanError(f"risk classification requires {field}")

    if plan["run_contract_semantics"]:
        required_reasons.add("contract_semantics")
    elif "contract_semantics" in reasons:
        raise PlanError("contract semantic provenance has no selected lane")

    missing_reasons = required_reasons - reasons
    if missing_reasons:
        raise PlanError(
            f"plan omitted derived reason codes: {sorted(missing_reasons)}"
        )

    all_docs = bool(changed_files) and all(
        is_docs_only_path(path) for path in changed_files
    )
    if plan["docs_only"] and (not all_docs or manual_override):
        raise PlanError("docs-only provenance does not match the changed paths")
    executable_selected = bool(affected) or any(
        plan[field]
        for field in (
            "run_contract_semantics",
            "run_lint",
            "run_app_build",
            "run_ui_tests",
            "run_full_packages",
        )
    )
    if all_docs and not executable_selected and not plan["docs_only"]:
        raise PlanError("safe docs-only skip lacks explicit provenance")
    if "docs_only" in reasons and not plan["docs_only"]:
        raise PlanError("docs-only reason does not match the plan decision")


def validate_plan(
    plan: dict[str, object],
    allowed_packages: Sequence[str],
    graph: dict[str, list[str]],
) -> None:
    if plan.get("schema_version") != SCHEMA_VERSION:
        raise PlanError("invalid plan schema")
    boolean_fields = (
        "docs_only",
        "run_contract_semantics",
        "run_lint",
        "run_app_build",
        "run_ui_tests",
        "run_full_packages",
        "high_risk",
    )
    if not all(isinstance(plan.get(field), bool) for field in boolean_fields):
        raise PlanError("plan contains a non-boolean decision")
    if plan["run_ui_tests"] and not plan["run_app_build"]:
        raise PlanError("UI tests require app build validation")

    event = plan.get("event")
    mode = plan.get("mode")
    if event not in SUPPORTED_EVENTS:
        raise PlanError("plan contains an unsupported event")
    if mode not in SUPPORTED_MODES:
        raise PlanError("plan contains an unsupported mode")

    changed_files = plan.get("changed_files")
    if not isinstance(changed_files, list) or not all(
        isinstance(path, str) for path in changed_files
    ):
        raise PlanError("malformed changed file list")
    try:
        canonical_files = sorted({_normalise_path(path) for path in changed_files})
    except PlanError as error:
        raise PlanError(f"plan contains a noncanonical changed path: {error}") from error
    if canonical_files != changed_files:
        raise PlanError("changed file list is not canonical, sorted, and unique")

    affected = plan.get("affected_packages")
    if not isinstance(affected, list) or not all(
        isinstance(package, str) for package in affected
    ):
        raise PlanError("malformed affected package list")
    if set(affected) - set(allowed_packages):
        raise PlanError("plan selected an unknown or untestable package")
    if affected != sorted(set(affected)):
        raise PlanError("affected package list is not canonical, sorted, and unique")

    matrix = plan.get("package_matrix")
    if not isinstance(matrix, dict) or not isinstance(matrix.get("include"), list):
        raise PlanError("malformed package matrix")
    flattened: list[str] = []
    for shard in matrix["include"]:
        if not isinstance(shard, dict):
            raise PlanError("malformed matrix shard")
        packages = shard.get("packages")
        if not isinstance(packages, list) or not packages:
            raise PlanError("empty or malformed matrix shard")
        flattened.extend(packages)
    if sorted(flattened) != sorted(affected):
        raise PlanError("matrix union does not equal affected packages")
    if len(flattened) != len(set(flattened)):
        raise PlanError("matrix duplicates a package")
    if plan["run_full_packages"] and set(affected) != set(allowed_packages):
        raise PlanError("full validation omitted a testable package")

    if plan["high_risk"] != plan["run_full_packages"]:
        raise PlanError("high-risk and full-package decisions must agree")
    if plan["run_full_packages"] and not all(
        plan[field]
        for field in (
            "run_contract_semantics",
            "run_lint",
            "run_app_build",
            "run_ui_tests",
        )
    ):
        raise PlanError("full/high-risk validation omitted a required lane")
    if plan["docs_only"] and (
        affected
        or plan["run_contract_semantics"]
        or plan["run_lint"]
        or plan["run_app_build"]
        or plan["run_ui_tests"]
        or plan["run_full_packages"]
        or plan["high_risk"]
    ):
        raise PlanError("docs-only validation selected an executable lane")

    if event in {"push", "schedule", "merge_group"} and not plan["run_full_packages"]:
        raise PlanError(f"{event} must select full validation")
    if mode in {"full", "benchmark", "clean"} and not plan["run_full_packages"]:
        raise PlanError(f"{mode} mode must select full validation")

    reasons = plan.get("reason_codes")
    if not isinstance(reasons, list) or not reasons or not all(
        isinstance(reason, str) and reason for reason in reasons
    ):
        raise PlanError("plan has no valid reason codes")
    unknown_reasons = set(reasons) - REASON_CODES
    if unknown_reasons:
        raise PlanError(f"plan has unsupported reason codes: {sorted(unknown_reasons)}")
    if plan["docs_only"] and "docs_only" not in reasons:
        raise PlanError("docs-only plan has no explicit safe-skip reason")

    _validate_semantic_risk_floor(plan, allowed_packages, graph)


def write_github_outputs(path: Path, plan: dict[str, object]) -> None:
    output_values = {
        "docs_only": str(plan["docs_only"]).lower(),
        "run_contract_semantics": str(plan["run_contract_semantics"]).lower(),
        "run_lint": str(plan["run_lint"]).lower(),
        "run_app_build": str(plan["run_app_build"]).lower(),
        "run_ui_tests": str(plan["run_ui_tests"]).lower(),
        "run_full_packages": str(plan["run_full_packages"]).lower(),
        "run_package_tests": str(bool(plan["affected_packages"])).lower(),
        "affected_packages": json.dumps(plan["affected_packages"], separators=(",", ":")),
        "package_matrix": json.dumps(plan["package_matrix"], separators=(",", ":")),
        "high_risk": str(plan["high_risk"]).lower(),
        "reason_codes": json.dumps(plan["reason_codes"], separators=(",", ":")),
        "plan_json": json.dumps(plan, separators=(",", ":"), sort_keys=True),
    }
    with path.open("a", encoding="utf-8") as stream:
        for key, value in output_values.items():
            if "\n" in value or "\r" in value:
                raise PlanError(f"multiline GitHub output rejected: {key}")
            stream.write(f"{key}={value}\n")


def parse_labels(raw_labels: str) -> list[str]:
    if not raw_labels:
        return []
    try:
        decoded = json.loads(raw_labels)
    except json.JSONDecodeError:
        decoded = [label.strip() for label in raw_labels.split(",") if label.strip()]
    if not isinstance(decoded, list) or not all(isinstance(label, str) for label in decoded):
        raise PlanError("labels must be a JSON string array or comma-separated list")
    return decoded


def parse_package_override(raw_packages: str) -> list[str]:
    return [
        package
        for package in re.split(r"[\s,]+", raw_packages.strip())
        if package
    ]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--event", choices=SUPPORTED_EVENTS, default="pull_request")
    parser.add_argument(
        "--mode",
        choices=SUPPORTED_MODES,
        default="affected",
    )
    parser.add_argument("--labels", default="[]")
    parser.add_argument("--packages", default="")
    parser.add_argument("--ui", choices=SUPPORTED_UI_OVERRIDES, default="auto")
    parser.add_argument("--max-shards", type=int, default=2)
    parser.add_argument("--changed-file", action="append", default=[])
    parser.add_argument("--output")
    parser.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT"))
    parser.add_argument("--verify-graph", action="store_true")
    parser.add_argument("--print-graph", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    root = repository_root()
    try:
        if arguments.print_graph:
            import generate_package_graph

            payload = generate_package_graph.build_payload(root)
            print(json.dumps(payload, indent=2, sort_keys=True))
            return 0
        graph = load_graph(root)
        verify_graph(root, graph)
        if arguments.verify_graph and not arguments.changed_file:
            print("package graph matches all current Package.swift manifests")
            return 0

        if arguments.changed_file:
            diff = DiffResult(
                tuple(_normalise_path(path) for path in arguments.changed_file),
                "explicit",
            )
        else:
            diff = resolve_git_diff(root, arguments.base, arguments.head)

        plan = create_plan(
            root=root,
            graph=graph,
            changed_files=diff.paths,
            base_sha=arguments.base,
            head_sha=arguments.head,
            merge_base=diff.merge_base,
            event=arguments.event,
            mode=arguments.mode,
            labels=parse_labels(arguments.labels),
            package_override=parse_package_override(arguments.packages),
            ui_override=arguments.ui,
            max_shards=arguments.max_shards,
            diff_failed=diff.failed,
        )
        rendered = json.dumps(plan, indent=2, sort_keys=True)
        print(rendered)
        if arguments.output:
            Path(arguments.output).write_text(rendered + "\n", encoding="utf-8")
        if arguments.github_output:
            write_github_outputs(Path(arguments.github_output), plan)
    except PlanError as error:
        print(f"CI plan error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
