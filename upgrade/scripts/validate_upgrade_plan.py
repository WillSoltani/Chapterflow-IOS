#!/usr/bin/env python3
"""Fail-closed structural and semantic checks for the ChapterFlow upgrade plan."""

from __future__ import annotations

import fnmatch
import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []
JSON: dict[Path, object] = {}


def fail(message: str) -> None:
    ERRORS.append(message)


def load_json(path: Path) -> object:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"invalid JSON {path.relative_to(ROOT)}: {error}")
        return {}
    JSON[path] = value
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        fail(f"{path.relative_to(ROOT)} must be a schemaVersion 1 object")
    return value


def require_files() -> None:
    required = {
        "README.md",
        "PROGRAM_CHARTER.md",
        "CURRENT_STATE.md",
        "COMPLETION_RUBRIC.md",
        "DESIGN_STANDARD.md",
        "SKILLS.md",
        "VALIDATION_POLICY.md",
        "DELIVERY_POLICY.md",
        "program/backlog.json",
        "program/dependency-dag.json",
        "program/performance-budgets.json",
        "program/resource-locks.json",
        "prompts/LANE_RUNNER.md",
        "prompts/RISK_REVIEWER.md",
        "prompts/RECOVERY_AND_RESUME.md",
        "prompts/templates/WORK_PACKAGE_SPEC.md",
        "prompts/templates/WORK_PACKAGE_RUN.md",
        "prompts/templates/WORK_PACKAGE_VALIDATE.md",
        "evals/prompt-cases.json",
        "evals/expected-behaviors.md",
        "evals/baselines/old-v02-orchestrator.json",
        "evals/baselines/draft-v0-shared-prompts.json",
        "evals/results/final-semantic-evaluation.json",
        "evals/results/prompt-static-analysis.json",
        "results/README.md",
        "results/PLANNING_CHECKPOINT.md",
        "scripts/validate_upgrade_plan.py",
    }
    for relative in sorted(required):
        if not (ROOT / relative).is_file():
            fail(f"missing required file: {relative}")


def validate_text_integrity() -> None:
    """Check the untracked corpus directly; ordinary git diff --check cannot see it."""
    conflict = re.compile(r"^(<<<<<<<|=======|>>>>>>>)(?: |$)", re.MULTILINE)
    for path in sorted(item for item in ROOT.rglob("*") if item.is_file()):
        data = path.read_bytes()
        if b"\0" in data:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            fail(f"non-UTF-8 text file: {path.relative_to(ROOT)}")
            continue
        if data and not data.endswith(b"\n"):
            fail(f"missing final newline: {path.relative_to(ROOT)}")
        if conflict.search(text):
            fail(f"merge-conflict marker: {path.relative_to(ROOT)}")
        for number, line in enumerate(text.splitlines(), 1):
            if line.rstrip(" \t") != line:
                fail(f"trailing whitespace: {path.relative_to(ROOT)}:{number}")


def validate_links() -> None:
    link_pattern = re.compile(r"!?(?:\[[^\]]*\])\(([^)]+)\)")
    for markdown in sorted(ROOT.rglob("*.md")):
        text = markdown.read_text(encoding="utf-8")
        for raw_target in link_pattern.findall(text):
            target = raw_target.strip().strip("<>").split(" ", 1)[0]
            if not target or target.startswith("#") or re.match(r"^[a-z]+://", target):
                continue
            path_part = target.split("#", 1)[0]
            resolved = (markdown.parent / path_part).resolve()
            try:
                resolved.relative_to(ROOT)
            except ValueError:
                fail(f"link escapes upgrade/: {markdown.relative_to(ROOT)} -> {target}")
                continue
            if not resolved.exists():
                fail(f"broken link: {markdown.relative_to(ROOT)} -> {target}")

    readme = (ROOT / "README.md").read_text(encoding="utf-8") if (ROOT / "README.md").exists() else ""
    directly_linked = [
        "evals/baselines/old-v02-orchestrator.json",
        "evals/baselines/draft-v0-shared-prompts.json",
        "evals/results/final-semantic-evaluation.json",
        "evals/results/prompt-static-analysis.json",
    ]
    for relative in directly_linked:
        if relative not in readme:
            fail(f"README.md must link contract-specific artifact: {relative}")


def static_prefix(pattern: str) -> str:
    positions = [position for token in "*?[" if (position := pattern.find(token)) >= 0]
    return pattern[: min(positions)] if positions else pattern


def globs_overlap(first: str, second: str) -> bool:
    first_wild = any(token in first for token in "*?[")
    second_wild = any(token in second for token in "*?[")
    if not first_wild and not second_wild:
        return first == second
    if not first_wild:
        return fnmatch.fnmatchcase(first, second)
    if not second_wild:
        return fnmatch.fnmatchcase(second, first)
    first_prefix = static_prefix(first)
    second_prefix = static_prefix(second)
    return first_prefix.startswith(second_prefix) or second_prefix.startswith(first_prefix)


def validate_packages(backlog: dict, locks_doc: dict) -> dict[str, dict]:
    package_paths = sorted(ROOT.glob("workstreams/*/WP-*/package.json"))
    packages: dict[str, dict] = {}
    owners: set[str] = set()
    criteria: set[str] = set()
    skills_index = (ROOT / "SKILLS.md").read_text(encoding="utf-8")
    required_fields = {
        "schemaVersion", "id", "title", "outcome", "riskTier", "status", "priority",
        "workstream", "verifiedBase", "evidenceAnchors", "blockedBy", "blocks",
        "criticalPath", "integrationOrder", "ownership", "resourceLocks", "estimate",
        "skills", "tools", "handoff", "acceptanceCriteria", "validationLanes",
        "physicalDevice", "backend", "ownerDecisionGates", "git", "mergePredicate",
        "cleanupPredicate", "releaseBoundary",
    }
    banned_broad_paths = {
        "Packages/**", "Packages/AppFeature/**", "Packages/Networking/**",
        "app/app/api/book/**", "app/api/book/**",
    }

    for path in package_paths:
        raw = load_json(path)
        if not isinstance(raw, dict):
            continue
        package = raw
        missing = sorted(required_fields - package.keys())
        if missing:
            fail(f"{path.relative_to(ROOT)} missing fields: {', '.join(missing)}")
            continue
        package_id = package.get("id")
        if not isinstance(package_id, str) or not re.fullmatch(r"WP-[A-Z]+-[0-9]{2}", package_id):
            fail(f"invalid package ID in {path.relative_to(ROOT)}: {package_id!r}")
            continue
        if package_id in packages:
            fail(f"duplicate package ID: {package_id}")
        packages[package_id] = package
        if path.parent.name != package_id:
            fail(f"directory/ID mismatch: {path.parent.name} != {package_id}")
        if path.parents[1].name != package.get("workstream"):
            fail(f"workstream mismatch for {package_id}")
        for companion in ("SPEC.md", "RUN.md", "VALIDATE.md"):
            if not (path.parent / companion).is_file():
                fail(f"{package_id} missing {companion}")

        owner = package.get("ownership", {}).get("ownerLane")
        if not owner or owner in owners:
            fail(f"{package_id} must have a unique non-empty owner lane")
        owners.add(owner)
        if package.get("ownership", {}).get("writableOwner") != "single":
            fail(f"{package_id} writableOwner must be single")
        allowed = package.get("ownership", {}).get("allowedPaths", [])
        if not allowed:
            fail(f"{package_id} has no allowed paths")
        for claim in allowed:
            glob = claim.get("glob", "") if isinstance(claim, dict) else ""
            if glob in banned_broad_paths:
                fail(f"{package_id} has overbroad write claim: {glob}")
            if glob.startswith("upgrade/") or glob.startswith("/Users/radinsoltani/Chapterflow-IOS"):
                fail(f"{package_id} claims prohibited plan/owner path: {glob}")
        prohibited_text = json.dumps(package.get("ownership", {}).get("prohibitedPaths", []))
        for marker in ("upgrade/**", "/Users/radinsoltani/Chapterflow-IOS/**", "#117"):
            if marker not in prohibited_text:
                fail(f"{package_id} prohibited paths omit {marker}")

        estimate = package.get("estimate", {})
        minutes = estimate.get("minutes")
        planned_files = estimate.get("plannedFiles")
        max_files = estimate.get("maxFiles")
        roots = estimate.get("primaryRoots")
        max_roots = estimate.get("maxPrimaryRoots")
        if not isinstance(minutes, int) or not 60 <= minutes <= 120:
            fail(f"{package_id} estimate.minutes must be 60..120")
        if package_id == "WP-DEVICE-01":
            sublanes = estimate.get("sublanes", [])
            sublane_minutes = [item.get("minutes") for item in sublanes if isinstance(item, dict)]
            if len(sublanes) != 4 or not all(isinstance(value, int) and 1 <= value <= 120 for value in sublane_minutes):
                fail("WP-DEVICE-01 must declare four independently bounded sublanes")
            if estimate.get("totalMinutes") != sum(sublane_minutes) or estimate.get("maxSublaneMinutes") != max(sublane_minutes):
                fail("WP-DEVICE-01 total/max sublane estimates must be explicit and arithmetically exact")
        if not all(isinstance(value, int) for value in (planned_files, max_files)) or not (1 <= planned_files <= max_files <= 20):
            fail(f"{package_id} file envelope must satisfy 1 <= planned <= max <= 20")
        if not all(isinstance(value, int) for value in (roots, max_roots)) or not (1 <= roots <= max_roots <= 3):
            fail(f"{package_id} root envelope must satisfy 1 <= roots <= max <= 3")

        if package_id in {"WP-NATIVE-01", "WP-EXT-01", "WP-READER-01"}:
            accounting = estimate.get("rootAccounting", {})
            groups = accounting.get("primaryGroups", [])
            non_primary = accounting.get("nonPrimaryPaths", [])
            if not isinstance(groups, list) or len(groups) != roots:
                fail(f"{package_id} rootAccounting must declare exactly primaryRoots groups")
                groups = []
            if not isinstance(non_primary, list):
                fail(f"{package_id} rootAccounting.nonPrimaryPaths must be a list")
                non_primary = []

            allowed_globs = {
                claim.get("glob") for claim in allowed
                if isinstance(claim, dict) and claim.get("repo") == "ios"
            }
            assigned: list[str] = []
            planned_allocation = 0
            group_ids: set[str] = set()

            def implementation_root(glob: str) -> str:
                parts = glob.split("/")
                if parts and parts[0] == "Packages" and len(parts) >= 2:
                    return "/".join(parts[:2])
                return parts[0] if parts else ""

            approved_multi_root = {
                "ShareExtension/ShareViewController.swift",
                "ActionExtension/ActionViewController.swift",
                "SharedExtensionKit/**",
            }
            for group in groups:
                if not isinstance(group, dict):
                    fail(f"{package_id} rootAccounting primary group must be an object")
                    continue
                group_id = group.get("id")
                group_paths = group.get("paths", [])
                group_files = group.get("plannedFiles")
                if not isinstance(group_id, str) or not group_id or group_id in group_ids:
                    fail(f"{package_id} rootAccounting primary group IDs must be unique and non-empty")
                else:
                    group_ids.add(group_id)
                if not isinstance(group_paths, list) or not group_paths:
                    fail(f"{package_id} rootAccounting group {group_id} has no paths")
                    group_paths = []
                if not isinstance(group_files, int) or group_files < 1:
                    fail(f"{package_id} rootAccounting group {group_id} needs positive plannedFiles")
                else:
                    planned_allocation += group_files
                assigned.extend(path for path in group_paths if isinstance(path, str))
                root_keys = {implementation_root(path) for path in group_paths if isinstance(path, str)}
                if len(root_keys) > 1 and not (
                    package_id == "WP-EXT-01"
                    and group_id == "extension-transaction-boundary"
                    and set(group_paths) == approved_multi_root
                ):
                    fail(f"{package_id} rootAccounting group {group_id} crosses implementation roots")

            allowed_non_primary_classes = {
                "validation-support", "validation-tooling", "project-configuration"
            }
            validation_support_paths = 0
            for item in non_primary:
                if not isinstance(item, dict):
                    fail(f"{package_id} rootAccounting non-primary entry must be an object")
                    continue
                path_value = item.get("path")
                path_class = item.get("class")
                path_files = item.get("plannedFiles")
                if not isinstance(path_value, str) or not path_value:
                    fail(f"{package_id} rootAccounting non-primary path must be non-empty")
                    continue
                assigned.append(path_value)
                if path_class not in allowed_non_primary_classes:
                    fail(f"{package_id} rootAccounting has invalid non-primary class {path_class}")
                if path_class == "validation-support":
                    validation_support_paths += 1
                    if not path_value.startswith("ChapterFlowUITests/UpgradeEvidence/"):
                        fail(f"{package_id} validation-support path is outside UpgradeEvidence")
                elif path_class == "validation-tooling" and not path_value.startswith("scripts/"):
                    fail(f"{package_id} validation-tooling path is outside scripts")
                elif path_class == "project-configuration" and not path_value.startswith("ChapterFlow.xcodeproj/"):
                    fail(f"{package_id} project-configuration path is outside the Xcode project")
                if not isinstance(path_files, int) or path_files < 1:
                    fail(f"{package_id} rootAccounting non-primary path needs positive plannedFiles")
                else:
                    planned_allocation += path_files

            if validation_support_paths != estimate.get("validationSupportRoots"):
                fail(f"{package_id} rootAccounting validation-support count drift")
            if len(assigned) != len(set(assigned)):
                fail(f"{package_id} rootAccounting assigns a path more than once")
            if set(assigned) != allowed_globs:
                fail(
                    f"{package_id} rootAccounting path drift; "
                    f"missing={sorted(allowed_globs - set(assigned))}, "
                    f"extra={sorted(set(assigned) - allowed_globs)}"
                )
            if planned_allocation != planned_files:
                fail(
                    f"{package_id} rootAccounting planned-file allocation "
                    f"{planned_allocation} != plannedFiles {planned_files}"
                )

        primary_skills = package.get("skills", {}).get("primary", [])
        review_skills = package.get("skills", {}).get("review", [])
        routed_skills = primary_skills + review_skills
        if not (1 <= len(primary_skills) and 1 <= len(review_skills) and 2 <= len(routed_skills) <= 4):
            fail(f"{package_id} must route 2..4 skills with primary and review coverage")
        for skill in routed_skills:
            if f"`{skill}`" not in skills_index:
                fail(f"{package_id} skill missing from SKILLS.md: {skill}")

        package_locks = package.get("resourceLocks", [])
        high_count = 0
        for lock in package_locks:
            if lock not in locks_doc.get("locks", {}):
                fail(f"{package_id} references unknown lock: {lock}")
            elif locks_doc["locks"][lock].get("highContention"):
                high_count += 1
        if high_count > 1:
            fail(f"{package_id} claims more than one high-contention lock")

        package_criteria = package.get("acceptanceCriteria", [])
        if not 3 <= len(package_criteria) <= 8:
            fail(f"{package_id} must have 3..8 acceptance criteria")
        spec = (path.parent / "SPEC.md").read_text(encoding="utf-8")
        validate = (path.parent / "VALIDATE.md").read_text(encoding="utf-8")
        run = (path.parent / "RUN.md").read_text(encoding="utf-8")
        assertion_ids: set[str] = set()
        for criterion in package_criteria:
            if criterion in criteria:
                fail(f"duplicate acceptance criterion: {criterion}")
            criteria.add(criterion)
            if criterion not in spec or criterion not in validate:
                fail(f"{package_id} criterion missing from SPEC/VALIDATE: {criterion}")
            rows = [line for line in validate.splitlines() if line.startswith(f"| {criterion} |")]
            if not rows:
                fail(f"{package_id} has no atomic evidence row for {criterion}")
            for row in rows:
                if "`" not in row or "results/" not in row:
                    fail(f"{package_id} {criterion} row needs a literal command and named results artifact")
                if len([cell for cell in row.split("|") if cell.strip()]) < 5:
                    fail(f"{package_id} {criterion} evidence row is incomplete")
                cells = [cell.strip() for cell in row.split("|")[1:-1]]
                if len(cells) >= 2:
                    assertion_id = cells[1]
                    if assertion_id in assertion_ids:
                        fail(f"{package_id} repeats assertion ID: {assertion_id}")
                    assertion_ids.add(assertion_id)
                command = cells[2] if len(cells) >= 3 else ""
                if " && " in command:
                    fail(f"{package_id} {criterion} bundles independent commands with &&")
                if "xcodebuild test" in command and "-resultBundlePath" not in command:
                    fail(f"{package_id} {criterion} xcodebuild test omits -resultBundlePath")
                if "xcodebuild test" in command and "-derivedDataPath" not in command:
                    fail(f"{package_id} {criterion} xcodebuild test omits isolated -derivedDataPath")
                if "run_native_matrix.py" in command:
                    required_dimensions = {
                        "light", "dark", "compact-iphone", "regular-ipad", "accessibility",
                        "voiceover", "increased-contrast", "reduce-motion", "reduce-transparency",
                        "real-locale", "pseudo-long", "rtl", "keyboard-pointer",
                    }
                    if "--derived-data" not in command:
                        fail(f"{package_id} {criterion} native matrix omits isolated --derived-data")
                    dimension_match = re.search(r"--require-dimensions ([^ `|]+)", command)
                    dimensions = set(dimension_match.group(1).split(",")) if dimension_match else set()
                    if dimensions != required_dimensions:
                        fail(f"{package_id} {criterion} native matrix dimension contract drift")
                if "scripts/validation/run_evidence.py" in command:
                    if "--assertion " not in command or "--attempt " not in command:
                        fail(f"{package_id} {criterion} direct evidence-runner invocation omits assertion/attempt identity")
                for vague_command in ("for each", "GitHub connector", "connector queries", "schema check"):
                    if vague_command.lower() in command.lower():
                        fail(f"{package_id} {criterion} uses non-literal command prose: {vague_command}")
        if spec.count("- Given ") < len(package_criteria) or spec.count("- When ") < len(package_criteria) or spec.count("- Then ") < len(package_criteria):
            fail(f"{package_id} SPEC lacks Given/When/Then coverage for every criterion")
        heading_alternatives = (
            ("## Problem and verified root cause",),
            ("## Functional and non-functional requirements", "## Requirements"),
            ("## Acceptance criteria",),
            ("## Invariant matrix", "## Invariants, compatibility, and rollback"),
            ("## Test plan", "## Test plan and definition of done"),
        )
        for alternatives in heading_alternatives:
            if not any(heading in spec for heading in alternatives):
                fail(f"{package_id} SPEC missing section: {' or '.join(alternatives)}")
        for marker in ("exact", "worktree", "P0/P1/P2", "PR #117"):
            if marker not in run:
                fail(f"{package_id} RUN missing required marker: {marker}")
        if "skill" not in run.lower():
            fail(f"{package_id} RUN does not require live skill revalidation")
        if not ("Commit candidate first" in run or "create local candidate commit" in run or "Commit the candidate" in run):
            fail(f"{package_id} RUN must commit before exact-head validation/review")
        for marker in ("passed", "failed", "skipped", "blocked", "not run", "git diff --check"):
            if marker not in validate:
                fail(f"{package_id} VALIDATE missing evidence state/command: {marker}")
        if not ("matched >= 1" in validate or "nonzero match" in validate or "nonzero matches" in validate):
            fail(f"{package_id} VALIDATE must reject zero matching selectors")
        for vague in ("targeted XCUITest", "XcodeBuildMCP screenshot matrix", "when keys change", "unsigned Debug iOS Simulator build"):
            if vague in validate:
                fail(f"{package_id} VALIDATE contains non-executable evidence prose: {vague}")

        git = package.get("git", {})
        if git.get("repository") != "WillSoltani/Chapterflow-IOS":
            fail(f"{package_id} must name the iOS repository in git metadata")
        if not str(git.get("branch", "")).startswith("codex/") or "wp-rel-01" in str(git.get("branch", "")):
            fail(f"{package_id} has invalid branch contract")
        if git.get("target") != "main" or not git.get("focusedPR"):
            fail(f"{package_id} must target main with a focused PR")
        backend = package.get("backend", {})
        if backend.get("deploymentAuthorized") is not False:
            fail(f"{package_id} must not authorize backend deployment")
        backend_claimed = any(claim.get("repo") == "backend" for claim in allowed if isinstance(claim, dict))
        if backend_claimed or backend.get("sourceChange") in {"expected", "conditional"}:
            backend_git = backend.get("git", {})
            if backend_git.get("repository") != "WillSoltani/ChapterFlow":
                fail(f"{package_id} backend source scope must name WillSoltani/ChapterFlow")
            if not str(backend_git.get("branch", "")).startswith("codex/"):
                fail(f"{package_id} backend branch must use codex/")
            if not str(backend_git.get("worktree", "")).startswith("/private/tmp/ChapterFlow-"):
                fail(f"{package_id} backend worktree must be separately package-owned")
            if backend_git.get("target") != "main" or not backend_git.get("focusedPR"):
                fail(f"{package_id} backend Git contract must target main with a focused PR")
            compatibility = backend.get("compatibilityAndMergeOrder", "")
            if "deploy" not in compatibility.lower() or "merge" not in compatibility.lower():
                fail(f"{package_id} must declare backend compatibility/merge/deployment semantics")
            if not any("every affected repository PR head" in predicate for predicate in package.get("mergePredicate", [])):
                fail(f"{package_id} merge predicate must bind every affected repository head")
        if not all(term in package.get("releaseBoundary", "") for term in ("App Store", "TestFlight", "PR #117")):
            fail(f"{package_id} release boundary is incomplete")

    expected_count = backlog.get("counts", {}).get("packages")
    if len(packages) != expected_count or not 8 <= len(packages) <= 24:
        fail(f"package count {len(packages)} must match backlog and remain within 8..24")
    if len(packages) > 20:
        charter = (ROOT / "PROGRAM_CHARTER.md").read_text(encoding="utf-8")
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        if "24-package hard cap" not in charter or "consolidation" not in charter.lower() or "24 bounded work packages" not in readme:
            fail("a >20 package program requires the explicit 24-package hard-cap consolidation rationale")
    return packages


def validate_graph(backlog: dict, dag: dict, locks_doc: dict, packages: dict[str, dict]) -> None:
    backlog_packages = backlog.get("packages", [])
    backlog_by_id = {item.get("id"): item for item in backlog_packages if isinstance(item, dict)}
    if set(backlog_by_id) != set(packages):
        fail("backlog package IDs do not match package directories")
    mirrored = ("title", "outcome", "riskTier", "priority", "status", "workstream", "blockedBy", "blocks", "criticalPath", "integrationOrder", "resourceLocks", "ownerDecisionGates")
    for package_id, package in packages.items():
        summary = backlog_by_id.get(package_id, {})
        for field in mirrored:
            if summary.get(field) != package.get(field):
                fail(f"backlog drift for {package_id}.{field}")

    workstreams = [path for path in (ROOT / "workstreams").iterdir() if path.is_dir()]
    if len(workstreams) != backlog.get("counts", {}).get("workstreams"):
        fail("workstream count does not match backlog")
    if len(backlog.get("ownerDecisions", [])) != backlog.get("counts", {}).get("decisions"):
        fail("owner-decision count does not match backlog")
    if backlog.get("releaseExcluded") is not True:
        fail("backlog must explicitly exclude release execution")

    expected_edges: set[tuple[str, str]] = set()
    for package_id, package in packages.items():
        for dependency in package.get("blockedBy", []):
            if dependency not in packages:
                fail(f"{package_id} has unknown dependency {dependency}")
                continue
            expected_edges.add((dependency, package_id))
            if package_id not in packages[dependency].get("blocks", []):
                fail(f"inverse blocks missing: {dependency} -> {package_id}")
            if package.get("integrationOrder", 0) <= packages[dependency].get("integrationOrder", 0):
                fail(f"integration order does not advance: {dependency} -> {package_id}")
        for blocked in package.get("blocks", []):
            if blocked not in packages or package_id not in packages[blocked].get("blockedBy", []):
                fail(f"inverse blockedBy missing: {package_id} -> {blocked}")

    nodes = {node.get("id") for node in dag.get("nodes", []) if isinstance(node, dict)}
    edges = {(edge.get("from"), edge.get("to")) for edge in dag.get("edges", []) if isinstance(edge, dict)}
    if nodes != set(packages):
        fail("DAG nodes do not match package IDs")
    if edges != expected_edges:
        missing = sorted(expected_edges - edges)
        extra = sorted(edges - expected_edges)
        fail(f"DAG edge drift; missing={missing}, extra={extra}")

    adjacency = {package_id: set() for package_id in packages}
    indegree = {package_id: 0 for package_id in packages}
    for source, target in expected_edges:
        adjacency[source].add(target)
        indegree[target] += 1
    queue = sorted(package_id for package_id, degree in indegree.items() if degree == 0)
    visited: list[str] = []
    while queue:
        current = queue.pop(0)
        visited.append(current)
        for target in sorted(adjacency[current]):
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)
    if len(visited) != len(packages):
        fail("dependency DAG contains a cycle")

    for path_name in ("criticalPath", "secondaryCriticalPaths"):
        paths = [dag.get(path_name, [])] if path_name == "criticalPath" else dag.get(path_name, [])
        for path in paths:
            if not isinstance(path, list) or len(path) < 2:
                fail(f"{path_name} must contain an edge-valid package path")
                continue
            for source, target in zip(path, path[1:]):
                if (source, target) not in expected_edges:
                    fail(f"{path_name} has non-edge hop {source} -> {target}")

    declared_paths = [dag.get("criticalPath", [])] + list(dag.get("secondaryCriticalPaths", []))
    critical_members = {item for path in declared_paths if isinstance(path, list) for item in path}
    marked_critical = {package_id for package_id, package in packages.items() if package.get("criticalPath")}
    if critical_members != marked_critical:
        fail(f"criticalPath markers/chains drift; marked={sorted(marked_critical)}, paths={sorted(critical_members)}")

    for node in dag.get("nodes", []):
        package = packages.get(node.get("id"), {}) if isinstance(node, dict) else {}
        for field in ("workstream", "criticalPath", "integrationOrder"):
            if node.get(field) != package.get(field):
                fail(f"DAG node drift for {node.get('id')}.{field}")

    selection = backlog.get("readySelection", {})
    algorithm = selection.get("algorithm", [])
    for marker in ("base status == planned", "not superseded", "all blockedBy", "owner decisions", "atomic package claim", "base and live instructions"):
        if not any(marker in rule for rule in algorithm):
            fail(f"readySelection algorithm missing derived-readiness rule: {marker}")

    reopen_schema = selection.get("reopenRecordSchema", {})
    required_reopen_fields = {
        "schemaVersion", "packageId", "failedQualificationPackage", "defectId",
        "candidateRepoHeads", "evidenceAnchors", "declaredVersusObservedEnvelope",
        "invalidatedGates", "ownerAndLockDisposition", "observedAt",
    }
    if reopen_schema.get("writer") != "root scheduler only; package lanes and product worktrees are read-only":
        fail("reopen record must be root-scheduler-owned and read-only to package lanes")
    if reopen_schema.get("immutable") is not True:
        fail("reopen record must be immutable")
    if set(reopen_schema.get("requiredFields", [])) != required_reopen_fields:
        fail("reopen record required fields drift")
    if "$CHAPTERFLOW_EVIDENCE_ROOT" not in str(reopen_schema.get("location", "")):
        fail("reopen record must live under the external evidence root")

    def ready_set(integrated: set[str], resolved_decisions: set[str], reopened: set[str] | None = None) -> list[str]:
        reopened = reopened or set()
        ready: list[dict] = []
        priority_rank = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
        for package_id, package in packages.items():
            if package.get("status") != "planned" or (package_id in integrated and package_id not in reopened):
                continue
            if not set(package.get("blockedBy", [])).issubset(integrated):
                continue
            if not set(package.get("ownerDecisionGates", [])).issubset(resolved_decisions):
                continue
            ready.append(package)
        ready.sort(key=lambda item: (priority_rank.get(item.get("priority"), 99), item.get("integrationOrder", 99), item.get("id")))
        return [item["id"] for item in ready]

    initial_ready = ready_set(set(), set())
    if selection.get("initialReady", []) != initial_ready:
        fail(f"initialReady does not match derived readiness: expected {initial_ready}")
    assertions = selection.get("transitionAssertions", [])
    if not isinstance(assertions, list) or len(assertions) < 2:
        fail("readySelection requires at least initial and after-recovery transition assertions")
    else:
        names: set[str] = set()
        for assertion in assertions:
            name = assertion.get("name")
            if not name or name in names:
                fail("readiness transition assertion names must be unique")
                continue
            names.add(name)
            integrated_raw = assertion.get("integrated", [])
            integrated = set(packages) if integrated_raw == "ALL_PACKAGES" else set(integrated_raw)
            resolved = set(assertion.get("resolvedDecisions", []))
            reopened = set(assertion.get("reopened", []))
            if not reopened.issubset(packages):
                fail(f"readiness transition {name} reopens unknown package")
            expected = ready_set(integrated, resolved, reopened)
            if assertion.get("expectedReady") != expected:
                fail(f"readiness transition {name} drift: expected {expected}")
        if not {"initial", "after-recovery", "reopen-protocol"}.issubset(names):
            fail("readiness transition assertions must include initial, after-recovery, and reopen-protocol")
    if selection.get("maximumConcurrentEditors") != 2:
        fail("maximum concurrent editors must be two")

    acquisition = locks_doc.get("acquisition", {})
    required_acquisition = {
        "authority": "root scheduler only",
        "claimRoot": "/private/tmp/chapterflow-upgrade-locks",
        "atomicPrimitive": "mkdir",
    }
    for field, expected in required_acquisition.items():
        if acquisition.get(field) != expected:
            fail(f"resource-lock acquisition.{field} must be {expected!r}")
    claims_text = " ".join(acquisition.get("requiredClaims", []))
    metadata_text = " ".join(acquisition.get("metadata", []))
    for marker in ("package-<PACKAGE_ID>", "declared resource lock", "capacity"):
        if marker not in claims_text:
            fail(f"resource-lock acquisition claims omit {marker}")
    for marker in ("package ID", "repository", "owner task ID", "branch/worktree", "start time", "heartbeat"):
        if marker not in metadata_text:
            fail(f"resource-lock acquisition metadata omit {marker}")
    for field in ("failure", "release", "fallback"):
        if not acquisition.get(field):
            fail(f"resource-lock acquisition missing {field} semantics")

    reachable_cache: dict[tuple[str, str], bool] = {}

    def reaches(source: str, target: str) -> bool:
        key = (source, target)
        if key in reachable_cache:
            return reachable_cache[key]
        pending = list(adjacency[source])
        seen: set[str] = set()
        while pending:
            current = pending.pop()
            if current == target:
                reachable_cache[key] = True
                return True
            if current not in seen:
                seen.add(current)
                pending.extend(adjacency[current])
        reachable_cache[key] = False
        return False

    high_locks = {
        name for name, lock in locks_doc.get("locks", {}).items()
        if isinstance(lock, dict) and lock.get("highContention")
    }
    package_ids = sorted(packages)
    for index, first_id in enumerate(package_ids):
        for second_id in package_ids[index + 1 :]:
            if reaches(first_id, second_id) or reaches(second_id, first_id):
                continue
            first_locks = set(packages[first_id].get("resourceLocks", []))
            second_locks = set(packages[second_id].get("resourceLocks", []))
            serialized = bool(first_locks & second_locks & high_locks)
            for first_claim in packages[first_id].get("ownership", {}).get("allowedPaths", []):
                for second_claim in packages[second_id].get("ownership", {}).get("allowedPaths", []):
                    if first_claim.get("repo") != second_claim.get("repo"):
                        continue
                    if globs_overlap(first_claim.get("glob", ""), second_claim.get("glob", "")) and not serialized:
                        fail(
                            f"concurrent write collision without dependency/shared lock: {first_id} {first_claim.get('glob')} <> "
                            f"{second_id} {second_claim.get('glob')}"
                        )


def validate_evaluations(backlog: dict) -> None:
    cases_doc = load_json(ROOT / "evals/prompt-cases.json")
    if not isinstance(cases_doc, dict):
        return
    cases = cases_doc.get("cases", [])
    ids = [case.get("id") for case in cases if isinstance(case, dict)]
    if not 16 <= len(cases) <= 20 or len(cases) != backlog.get("counts", {}).get("evaluationCases"):
        fail("evaluation case count must be 16..20 and match backlog")
    if ids != [f"E{number:02d}" for number in range(1, 21)]:
        fail("evaluation IDs must be the complete ordered E01..E20 set")
    for case in cases:
        if not case.get("critical"):
            fail(f"evaluation case is not critical: {case.get('id')}")
        for field in ("expectedOutcome", "failureConditions", "artifactAssertions", "promptTargets", "evaluatorIdentity"):
            if not case.get(field):
                fail(f"evaluation {case.get('id')} missing {field}")

    final_doc = load_json(ROOT / "evals/results/final-semantic-evaluation.json")
    if isinstance(final_doc, dict):
        results = final_doc.get("results", [])
        result_ids = [result.get("caseId") for result in results if isinstance(result, dict)]
        if len(results) != len(cases) or len(set(result_ids)) != len(result_ids) or set(result_ids) != set(ids):
            fail("final semantic evaluation requires exactly one unique result per case")
        if any(result.get("status") != "pass" for result in results):
            fail("final semantic evaluation must pass every declared case")
        evaluator = final_doc.get("evaluatorIdentity", "")
        if not evaluator or evaluator.startswith("root-"):
            fail("final semantic evaluation requires an independent non-author evaluator identity")
        case_by_id = {case.get("id"): case for case in cases}
        anchor_fingerprints: set[str] = set()
        for result in results:
            case_id = result.get("caseId")
            if result.get("evaluatorIdentity") != evaluator:
                fail(f"{case_id} evaluator identity does not match final independent evaluator")
            expected_assertions = case_by_id.get(case_id, {}).get("artifactAssertions", [])
            assertion_results = result.get("assertionResults", [])
            if len(assertion_results) != len(expected_assertions):
                fail(f"{case_id} assertion result count does not match declared artifact assertions")
                continue
            by_assertion = {
                item.get("assertion"): item for item in assertion_results if isinstance(item, dict)
            }
            if set(by_assertion) != set(expected_assertions):
                fail(f"{case_id} assertion results do not cover exact declared artifact assertions")
            for assertion in expected_assertions:
                disposition = by_assertion.get(assertion, {})
                anchors = disposition.get("evidenceAnchors", [])
                if disposition.get("status") != "pass" or not isinstance(anchors, list) or not anchors:
                    fail(f"{case_id} assertion lacks passing exact evidence anchors: {assertion}")
                for anchor in anchors:
                    if not re.fullmatch(r"[A-Za-z0-9_./-]+:[0-9]+(?:-[0-9]+)?", str(anchor)):
                        fail(f"{case_id} has non-exact evidence anchor: {anchor!r}")
            fingerprint = json.dumps(assertion_results, sort_keys=True)
            if fingerprint in anchor_fingerprints:
                fail(f"{case_id} reuses a generic assertion/evidence bundle")
            anchor_fingerprints.add(fingerprint)
        summary = final_doc.get("summary", {})
        if summary.get("passed") != len(cases) or summary.get("failed") != 0 or not 0 <= summary.get("revisionRounds", 99) <= 2:
            fail("final semantic summary is inconsistent or exceeds two revision rounds")
        if summary.get("criticalPassed") != len(cases) or summary.get("criticalFailed") != 0:
            fail("final semantic critical summary is inconsistent")
        for source in final_doc.get("sources", []):
            source_path = ROOT.parent / source.get("path", "")
            if not source_path.is_file():
                fail(f"final evaluation source missing: {source.get('path')}")
                continue
            digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
            if digest != source.get("sha256"):
                fail(f"final evaluation hash drift: {source.get('path')}")

    static_doc = load_json(ROOT / "evals/results/prompt-static-analysis.json")
    if isinstance(static_doc, dict):
        if static_doc.get("tool", {}).get("status") != "passed":
            fail("prompt static analyzer did not pass")
        expected_sources = {
            "upgrade/prompts/LANE_RUNNER.md",
            "upgrade/prompts/RISK_REVIEWER.md",
            "upgrade/prompts/RECOVERY_AND_RESUME.md",
        }
        sources = static_doc.get("sources", [])
        source_paths = {source.get("path") for source in sources if isinstance(source, dict)}
        if source_paths != expected_sources or len(sources) != len(expected_sources):
            fail("prompt static analysis must hash-bind the three shared prompts")
        for source in sources:
            source_path = ROOT.parent / source.get("path", "")
            if not source_path.is_file():
                fail(f"prompt static source missing: {source.get('path')}")
                continue
            digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
            if digest != source.get("sha256"):
                fail(f"prompt static analysis hash drift: {source.get('path')}")
        final_names = {
            item.get("name") for item in static_doc.get("final", {}).get("perPrompt", [])
            if isinstance(item, dict)
        }
        if final_names != {"LANE_RUNNER", "RISK_REVIEWER", "RECOVERY_AND_RESUME"}:
            fail("prompt static final metrics must cover each shared prompt exactly once")

    old = load_json(ROOT / "evals/baselines/old-v02-orchestrator.json")
    draft = load_json(ROOT / "evals/baselines/draft-v0-shared-prompts.json")
    if isinstance(old, dict) and old.get("semantic", {}).get("failed", 0) == 0:
        fail("old baseline must retain its measured failures")
    if isinstance(draft, dict) and draft.get("semantic", {}).get("failed") != 1:
        fail("draft-v0 baseline must retain the single pre-revision failure")


def validate_performance_budgets() -> None:
    path = ROOT / "program/performance-budgets.json"
    document = JSON.get(path, {})
    if not isinstance(document, dict):
        fail("performance budgets must be a JSON object")
        return
    source = document.get("source", {})
    source_path = ROOT.parent / str(source.get("path", ""))
    if not source_path.is_file():
        fail("performance budget source path is missing")
    else:
        digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
        if digest != source.get("sha256AtPlanningBase"):
            fail("performance budget source hash drift")
    required_ids = {
        "PERF-COLD-LAUNCH", "PERF-READER-HITCH", "PERF-CATALOG-HITCH",
        "PERF-READER-PAGINATION",
        "PERF-IMAGE-CACHE", "PERF-MEMORY-ONE-BOOK", "PERF-MEMORY-THREE-BOOKS",
        "PERF-CHAPTER-FETCH", "PERF-MAIN-STALL", "PERF-ENERGY-JOURNEY",
        "PERF-LONG-AUDIO", "PERF-DOWNLOAD-LIFECYCLE",
    }
    budgets = document.get("budgets", [])
    ids = [budget.get("id") for budget in budgets if isinstance(budget, dict)]
    if set(ids) != required_ids or len(ids) != len(set(ids)):
        fail("performance budget IDs must be unique and cover every declared device metric")
    for budget in budgets:
        if not isinstance(budget, dict):
            fail("performance budget entry must be an object")
            continue
        for field in ("id", "metric", "operator", "value", "unit", "method", "samplePolicy"):
            if budget.get(field) in (None, "", []):
                fail(f"performance budget {budget.get('id')} omits {field}")
        if str(budget.get("operator", "")).startswith("pairedBaseline"):
            sample_policy = str(budget.get("samplePolicy", ""))
            if "current-main first" not in sample_policy or "candidate" not in sample_policy:
                fail(f"paired budget {budget.get('id')} lacks fixed baseline-before-candidate policy")
    if len(document.get("requiredDeviceClasses", [])) < 2:
        fail("performance budgets must name compact-iPhone and regular-iPad device classes")
    if "never loosen" not in str(document.get("changePolicy", "")):
        fail("performance budget change policy must fail closed on relaxation")


def validate_final_remediation_contracts(packages: dict[str, dict], locks_doc: dict) -> None:
    """Keep independently found execution gaps closed in future plan edits."""
    leasing = locks_doc.get("commandScopedLeasing", {})
    required_triggers = {
        "xcodebuild test",
        "run_native_matrix.py",
        "scripts/qa/device/run_matrix.py",
        "run_paired_performance.py",
    }
    if leasing.get("authority") != "root scheduler through the standard evidence wrapper":
        fail("command-scoped leasing authority must be the root scheduler through the evidence wrapper")
    if leasing.get("lock") != "simulator-device":
        fail("command-scoped leasing must select simulator-device")
    if set(leasing.get("triggerPatterns", [])) != required_triggers:
        fail("command-scoped simulator leasing trigger patterns drift")
    leasing_text = " ".join(str(leasing.get(field, "")) for field in ("claim", "reentrant", "failure", "release"))
    for marker in ("assertion attempt", "same package owner", "LOCKED", "finally"):
        if marker not in leasing_text:
            fail(f"command-scoped simulator leasing omits {marker!r}")
    simulator = locks_doc.get("locks", {}).get("simulator-device", {})
    if simulator.get("mode") != "capacity" or simulator.get("capacity") != 1 or simulator.get("commandScoped") is not True:
        fail("simulator-device must be a command-scoped capacity-one lock")

    all_validation = "\n".join(
        (ROOT / "workstreams" / package["workstream"] / package_id / "VALIDATE.md").read_text(encoding="utf-8")
        for package_id, package in packages.items()
    )
    for executable in required_triggers:
        if executable not in all_validation:
            fail(f"no validation command exercises command-scoped lease trigger: {executable}")

    validation_policy = (ROOT / "VALIDATION_POLICY.md").read_text(encoding="utf-8")
    delivery_policy = (ROOT / "DELIVERY_POLICY.md").read_text(encoding="utf-8")
    lane_runner = (ROOT / "prompts/LANE_RUNNER.md").read_text(encoding="utf-8")
    attempt_markers = (
        "attempts/<attempt-id>", "exclusive-create", "refuses an existing ID", "attemptId",
        "retryOf", "append-only", "command-scoped", "fail `LOCKED`", "`finally` path",
        "attempt://<attempt-id>/results/<path>",
    )
    for marker in attempt_markers:
        if marker not in validation_policy:
            fail(f"validation policy omits append-only evidence/lease marker: {marker}")
    if "command-scoped `simulator-device` lease" not in delivery_policy:
        fail("delivery policy omits command-scoped simulator lease")
    if "automatically acquires every command-scoped lease" not in lane_runner:
        fail("lane runner omits automatic command-scoped lease acquisition")

    rec_root = ROOT / "workstreams/01-current-work-recovery/WP-REC-01"
    rec_contract = "\n".join((rec_root / name).read_text(encoding="utf-8") for name in ("SPEC.md", "RUN.md", "VALIDATE.md"))
    for marker in (
        "--build-recovery-inventory", "--compare-artifacts", "inventory.json",
        "owner-status-comparison.json", "owner-diff-comparison.json", "pr117-comparison.json",
        "exclusive attempt collision", "retry linkage/retention", "command-scoped lease",
        "attempt://<attempt-id>/results/...",
    ):
        if marker not in rec_contract:
            fail(f"WP-REC-01 executable recovery contract omits {marker}")
    if rec_contract.count("--compare-artifacts") < 3:
        fail("WP-REC-01 needs explicit status, diff, and PR #117 comparators")

    contract = packages.get("WP-CONTRACT-02", {})
    inspection = contract.get("backend", {}).get("readOnlyInspection", {})
    expected_backend_sha = "858d2d7ffd620a7c28cdad5a75007536ccd5b391"
    if inspection.get("worktree") != "/private/tmp/ChapterFlow-wp-contract-02-inspect":
        fail("WP-CONTRACT-02 must declare its exact read-only backend inspection worktree")
    if inspection.get("revision") != expected_backend_sha or "read-only" not in str(inspection.get("mode", "")):
        fail("WP-CONTRACT-02 backend inspection must bind the exact SHA in read-only mode")
    contract_validate = (ROOT / "workstreams/02-contracts-and-foundations/WP-CONTRACT-02/VALIDATE.md").read_text(encoding="utf-8")
    for marker in (
        "git -C /private/tmp/ChapterFlow-wp-contract-02-inspect rev-parse HEAD",
        "npm --prefix /private/tmp/ChapterFlow-wp-contract-02-inspect run contract:native:check",
        expected_backend_sha,
    ):
        if marker not in contract_validate:
            fail(f"WP-CONTRACT-02 validation omits exact backend proof: {marker}")

    expected_criteria = {
        "WP-ACCOUNT-02": "AC-ACCOUNT-02-08",
        "WP-PAYWALL-01": "AC-PAYWALL-01-06",
        "WP-READER-01": "AC-READER-01-06",
        "WP-LEARN-01": "AC-LEARN-01-07",
        "WP-ENGAGE-01": "AC-ENGAGE-01-08",
        "WP-GRAPH-01": "AC-GRAPH-01-07",
    }
    for package_id, criterion in expected_criteria.items():
        if criterion not in packages.get(package_id, {}).get("acceptanceCriteria", []):
            fail(f"{package_id} omits required adverse/account/lifecycle criterion {criterion}")

    native = packages.get("WP-NATIVE-01", {})
    native_paths = {claim.get("glob") for claim in native.get("ownership", {}).get("allowedPaths", [])}
    required_extension_paths = {
        "ShareExtension/ShareView.swift", "ShareExtension/Localizable.xcstrings",
        "ActionExtension/ActionView.swift", "ActionExtension/Localizable.xcstrings",
    }
    if not required_extension_paths.issubset(native_paths) or "WP-EXT-01" not in native.get("blocks", []):
        fail("WP-NATIVE-01 must own and precede real Share/Action localization")
    controller_paths = {
        "ShareExtension/ShareViewController.swift",
        "ActionExtension/ActionViewController.swift",
    }
    if native_paths & controller_paths:
        fail("WP-NATIVE-01 presentation ownership must not include production extension controllers")

    ext = packages.get("WP-EXT-01", {})
    ext_paths = {claim.get("glob") for claim in ext.get("ownership", {}).get("allowedPaths", [])}
    if not controller_paths.issubset(ext_paths) or ext_paths & required_extension_paths:
        fail("WP-EXT-01 must own only the two production controllers, not NATIVE views/catalogs")
    if ext.get("estimate", {}).get("plannedFiles") != 17 or ext.get("estimate", {}).get("maxFiles") != 20:
        fail("WP-EXT-01 result wiring must remain at 17 planned files inside the unchanged 20-file cap")
    if ext.get("estimate", {}).get("primaryRoots") != 3 or ext.get("estimate", {}).get("maxPrimaryRoots") != 3:
        fail("WP-EXT-01 result wiring must remain inside the unchanged three-root cap")
    if "AC-EXT-01-08" not in ext.get("acceptanceCriteria", []):
        fail("WP-EXT-01 must fail closed on Share/Action capture failure transitions")

    native_root = ROOT / "workstreams/03-native-design-accessibility-localization/WP-NATIVE-01"
    ext_root = ROOT / "workstreams/09-routing-notifications-extensions/WP-EXT-01"
    reader_root = ROOT / "workstreams/06-reader-annotations-ai/WP-READER-01"
    native_contract = "\n".join(
        (native_root / name).read_text(encoding="utf-8")
        for name in ("SPEC.md", "RUN.md", "VALIDATE.md")
    )
    ext_contract = "\n".join(
        (ext_root / name).read_text(encoding="utf-8")
        for name in ("SPEC.md", "RUN.md", "VALIDATE.md")
    )
    reader_contract = "\n".join(
        (reader_root / name).read_text(encoding="utf-8")
        for name in ("SPEC.md", "RUN.md", "VALIDATE.md")
    )
    for marker in (
        "stateSource=fixture", "transactionClaim=none", "owner-closure-required",
        "reader-toolbar.depth-option", "reader-toolbar.tone-option",
    ):
        if marker not in native_contract:
            fail(f"WP-NATIVE-01 presentation/inventory boundary omits {marker}")
    for marker in (
        "fresh reopen/decode", "testShareAndActionSuccessFollowsDurableCommit",
        "testShareAndActionFailuresNeverShowSuccessOrDismiss", "AC-EXT-01-08",
    ):
        if marker not in ext_contract:
            fail(f"WP-EXT-01 durable-result boundary omits {marker}")
    for marker in (
        "reader-toolbar.depth-option", "reader-toolbar.tone-option",
        "READER-03-TARGETS-02", "--owner-package WP-READER-01",
    ):
        if marker not in reader_contract:
            fail(f"WP-READER-01 target closure omits {marker}")

    reader = packages.get("WP-READER-01", {})
    if "WP-NATIVE-01" not in reader.get("blockedBy", []) or "WP-NATIVE-01" not in ext.get("blockedBy", []):
        fail("NATIVE must retain its existing dependency direction into READER and EXT")
    if len(packages) != 24:
        fail("NATIVE/EXT/READER revision must preserve the 24-package hard cap")
    learn = packages.get("WP-LEARN-01", {})
    learn_paths = {claim.get("glob") for claim in learn.get("ownership", {}).get("allowedPaths", [])}
    required_review_paths = {
        "Packages/EngagementFeature/Package.swift",
        "Packages/EngagementFeature/Sources/EngagementFeature/Resources/Review.xcstrings",
    }
    if not required_review_paths.issubset(learn_paths) or "WP-ENGAGE-01" not in learn.get("blocks", []):
        fail("WP-LEARN-01 must own and precede real localized Review resources")

    graph_validate = (ROOT / "workstreams/10-engagement-community/WP-GRAPH-01/VALIDATE.md").read_text(encoding="utf-8")
    for marker in ("run_paired_performance.py", "--samples 30", "--instruments-template Hangs", ".xcresult"):
        if marker not in graph_validate:
            fail(f"WP-GRAPH-01 performance proof omits {marker}")
    device_validate = (ROOT / "workstreams/11-qualification-performance-security-ci/WP-DEVICE-01/VALIDATE.md").read_text(encoding="utf-8")
    if (
        "DEVICE-01-SURFACES-02" not in device_validate
        or "DEVICE-06-VOICEOVER-SURFACES-02" not in device_validate
        or "--inventory attempt://<DEVICE_SURFACE_INVENTORY_ATTEMPT_ID>/results/device/changed-visible-surfaces.json" not in device_validate
    ):
        fail("WP-DEVICE-01 must physically qualify VoiceOver on every changed visible surface")

    auth_anchors = packages.get("WP-AUTH-02", {}).get("evidenceAnchors", [])
    if any("AuthKit/KeychainConfiguration.swift" in anchor or "AuthKit/TokenStore.swift" in anchor for anchor in auth_anchors):
        fail("WP-AUTH-02 retains nonexistent AuthKit Keychain/TokenStore anchors")


def main() -> int:
    require_files()
    validate_text_integrity()
    for path in sorted(ROOT.rglob("*.json")):
        if path not in JSON:
            load_json(path)
    backlog = JSON.get(ROOT / "program/backlog.json", {})
    dag = JSON.get(ROOT / "program/dependency-dag.json", {})
    locks_doc = JSON.get(ROOT / "program/resource-locks.json", {})
    if not all(isinstance(value, dict) for value in (backlog, dag, locks_doc)):
        fail("program JSON documents must be objects")
    else:
        packages = validate_packages(backlog, locks_doc)
        validate_graph(backlog, dag, locks_doc, packages)
        validate_evaluations(backlog)
        validate_performance_budgets()
        validate_final_remediation_contracts(packages, locks_doc)
    validate_links()

    if ERRORS:
        print(f"FAIL: {len(ERRORS)} upgrade-plan error(s)")
        for error in ERRORS:
            print(f"- {error}")
        return 1
    package_count = backlog.get("counts", {}).get("packages")
    workstream_count = backlog.get("counts", {}).get("workstreams")
    case_count = backlog.get("counts", {}).get("evaluationCases")
    print(f"PASS: upgrade plan validated ({workstream_count} workstreams, {package_count} packages, {case_count} eval cases)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
