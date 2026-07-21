#!/usr/bin/env python3
"""Fail-closed structural and semantic checks for the ChapterFlow upgrade plan."""

from __future__ import annotations

import argparse
import copy
import fnmatch
import hashlib
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []
JSON: dict[Path, object] = {}


class DuplicateJSONKeyError(ValueError):
    pass


def fail(message: str) -> None:
    ERRORS.append(message)


def unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise DuplicateJSONKeyError(f"duplicate JSON key: {key}")
        value[key] = item
    return value


def load_json(path: Path) -> object:
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=unique_json_object,
        )
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError) as error:
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


REVISED_ROOT_PACKAGES = {"WP-NATIVE-01", "WP-EXT-01", "WP-READER-01"}
EXTENSION_TRANSACTION_CLAIMS = {
    ("ios", "ShareExtension/ShareViewController.swift"),
    ("ios", "ActionExtension/ActionViewController.swift"),
    ("ios", "SharedExtensionKit/**"),
}
EXPECTED_NON_PRIMARY = {
    "WP-NATIVE-01": [
        ("ios", "ChapterFlowUITests/UpgradeEvidence/NativeUpgradeEvidenceTests.swift", "validation-support"),
        ("ios", "ChapterFlow.xcodeproj/project.pbxproj", "project-configuration"),
        ("ios", "scripts/visual/**", "validation-tooling"),
        ("ios", "scripts/localization/**", "validation-tooling"),
    ],
    "WP-EXT-01": [
        ("ios", "ChapterFlowUITests/UpgradeEvidence/ExtensionUpgradeEvidenceTests.swift", "validation-support"),
    ],
    "WP-READER-01": [
        ("ios", "ChapterFlowUITests/UpgradeEvidence/ReaderUpgradeEvidenceTests.swift", "validation-support"),
    ],
}

EXPECTED_CANDIDATE_DISPOSITION = "known-red-scope-only-not-runtime-approved"
EXPECTED_NATIVE_BEFORE_PATHS = [
    "ActionExtension/ActionView.swift",
    "ActionExtension/Localizable.xcstrings",
    "ChapterFlow.xcodeproj/project.pbxproj",
    "ChapterFlowUITests/UpgradeEvidence/NativeUpgradeEvidenceTests.swift",
    "Packages/DesignSystem/Sources/DesignSystem/NativeEvidenceAccessibility.swift",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/DesignSystemSnapshotTests.swift",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/SnapshotHelper.swift",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/__Snapshots__/gallery-dark.png",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/__Snapshots__/gallery-light.png",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/__Snapshots__/gallery-xxl.png",
    "ShareExtension/Localizable.xcstrings",
    "ShareExtension/ShareView.swift",
    "scripts/localization/inventory.py",
    "scripts/localization/scenarios.json",
    "scripts/localization/validate_matrix.py",
    "scripts/visual/native-matrix.json",
    "scripts/visual/run_native_matrix.py",
    "scripts/visual/run_paired_performance.py",
    "scripts/visual/touch_targets.py",
    "scripts/visual/validate_upgrade_ui_test_membership.py",
]
EXPECTED_NATIVE_AFTER_PATHS = [
    "ActionExtension/ActionView.swift",
    "ActionExtension/Localizable.xcstrings",
    "ChapterFlow.xcodeproj/project.pbxproj",
    "ChapterFlowUITests/UpgradeEvidence/NativeUpgradeEvidenceTests.swift",
    "Packages/DesignSystem/Sources/DesignSystem/NativeEvidenceAccessibility.swift",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/DesignSystemSnapshotTests.swift",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/SnapshotHelper.swift",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/__Snapshots__/gallery-dark.png",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/__Snapshots__/gallery-light.png",
    "Packages/DesignSystem/Tests/DesignSystemSnapshotTests/__Snapshots__/gallery-xxl.png",
    "ShareExtension/Localizable.xcstrings",
    "ShareExtension/ShareView.swift",
    "scripts/localization/NativeExtensionEvidenceHost.swift",
    "scripts/localization/inventory.py",
    "scripts/localization/validate_matrix.py",
    "scripts/visual/native-matrix.json",
    "scripts/visual/run_native_matrix.py",
    "scripts/visual/run_paired_performance.py",
    "scripts/visual/touch_targets.py",
    "scripts/visual/validate_upgrade_ui_test_membership.py",
]
EXPECTED_NATIVE_CANDIDATE_BINDING = {
    "base": "cdc68d05aed931b43668253bbf19f192f78e7ad8",
    "head": "d332ae2f9091026d879be909f631bcd31bc39c82",
    "tree": "a525441ab1a0dd91434d4b700794a22f9a1912ed",
    "diffSha256": "5d71334dfcdb04cd2c17323db44c239be4a1b79bcaee76ea6718f7a887a3daba",
    "disposition": EXPECTED_CANDIDATE_DISPOSITION,
    "paths": EXPECTED_NATIVE_BEFORE_PATHS,
}
EXPECTED_NATIVE_PRESERVED_ORACLES = {
    "localizationAssertionID": "NATIVE-04-UNIT-01",
    "localizationValidator": "scripts/localization/validate_matrix.py",
    "mergedManifest": "scripts/visual/native-matrix.json",
    "mergedManifestKey": "localizationMatrix",
    "membershipAssertionID": "NATIVE-07-PROJECT-01",
    "membershipValidator": "scripts/visual/validate_upgrade_ui_test_membership.py",
}
EXPECTED_NATIVE_EXTENSION_EVIDENCE_HOST = {
    "sourcePath": "scripts/localization/NativeExtensionEvidenceHost.swift",
    "sourceTargets": ["ShareExtension", "ActionExtension"],
    "forbiddenSourceTargets": ["ChapterFlow", "ChapterFlowUITests"],
    "evidenceBuild": {
        "configuration": "Debug",
        "commonCompilationConditions": ["DEBUG", "CF_NATIVE_EXTENSION_EVIDENCE_BUILD"],
        "targetCompilationConditions": {
            "ShareExtension": "CF_NATIVE_SHARE_EVIDENCE_TARGET",
            "ActionExtension": "CF_NATIVE_ACTION_EVIDENCE_TARGET",
        },
        "sourceExclusionBuildSetting": "EXCLUDED_SOURCE_FILE_NAMES",
        "sourceExclusionVariable": "CF_NATIVE_EXTENSION_EXCLUDED_SOURCES",
        "ordinaryExcludedSource": "NativeExtensionEvidenceHost.swift",
        "excludedProductionSources": {
            "ShareExtension": "ShareViewController.swift",
            "ActionExtension": "ActionViewController.swift",
        },
    },
    "principalControllers": {
        "ShareExtension": "ShareViewController",
        "ActionExtension": "ActionViewController",
    },
    "readOnlyInfoPlists": {
        "ShareExtension": "ShareExtension/Info.plist",
        "ActionExtension": "ActionExtension/Info.plist",
    },
    "productionConfigurations": {
        "Debug": {
            "activeEvidenceConditions": [],
            "hostDisposition": "excluded",
            "productionControllerDisposition": "included",
        },
        "Release": {
            "activeEvidenceConditions": [],
            "hostDisposition": "excluded",
            "productionControllerDisposition": "included",
        },
    },
    "invocation": {
        "containingProduct": "ChapterFlow.app",
        "extensionProducts": ["ShareExtension.appex", "ActionExtension.appex"],
        "flow": [
            "build-and-install-containing-app-with-real-appex",
            "open-containing-or-system-host",
            "invoke-real-appex-through-system-extension-ui",
            "assert-extension-process-and-target-owned-fixture-state",
        ],
        "forbiddenSubstitutes": [
            "source-scan-as-runtime-evidence",
            "main-app-source-import",
            "ui-test-source-import",
            "static-fixture-claim-as-runtime-evidence",
        ],
    },
    "fixtureEvidence": {
        "stateSource": "fixture",
        "transactionClaim": "none",
        "proves": ["presentation", "localization", "accessibility"],
        "doesNotProve": [
            "outbox-write",
            "durability",
            "committed-only-production-success",
            "dismissal",
            "app-opening",
        ],
    },
}
EXPECTED_REVISED_OWNERSHIP = {
    "WP-NATIVE-01": [
        "Packages/DesignSystem/**",
        "ShareExtension/ShareView.swift",
        "ShareExtension/Localizable.xcstrings",
        "ActionExtension/ActionView.swift",
        "ActionExtension/Localizable.xcstrings",
        "ChapterFlowUITests/UpgradeEvidence/NativeUpgradeEvidenceTests.swift",
        "ChapterFlow.xcodeproj/project.pbxproj",
        "scripts/visual/**",
        "scripts/localization/**",
    ],
    "WP-EXT-01": [
        "ShareExtension/ShareViewController.swift",
        "ActionExtension/ActionViewController.swift",
        "SharedExtensionKit/**",
        "Packages/Persistence/Sources/Persistence/PendingExtensionItem.swift",
        "Packages/Persistence/Sources/Persistence/ExtensionOutbox.swift",
        "Packages/Persistence/Sources/Persistence/SharedAppStateSnapshot.swift",
        "Packages/Persistence/Sources/Persistence/SharedStateWriter.swift",
        "Packages/Persistence/Tests/PersistenceTests/ExtensionOutboxTests.swift",
        "Packages/Persistence/Tests/PersistenceTests/SharedSnapshotOwnershipTests.swift",
        "Packages/AppFeature/Sources/AppFeature/AppModel+Extensions.swift",
        "Packages/AppFeature/Tests/AppFeatureTests/ExtensionImportTests.swift",
        "ChapterFlowUITests/UpgradeEvidence/ExtensionUpgradeEvidenceTests.swift",
    ],
    "WP-READER-01": [
        "Packages/ReaderFeature/**",
        "ChapterFlowUITests/UpgradeEvidence/ReaderUpgradeEvidenceTests.swift",
    ],
}
EXPECTED_REVISED_GRAPH = {
    "WP-NATIVE-01": {
        "blockedBy": ["WP-REC-01"],
        "blocks": [
            "WP-SHELL-02", "WP-AUTH-02", "WP-ENTRY-01", "WP-PAYWALL-01",
            "WP-CATALOG-01", "WP-READER-01", "WP-ASK-01", "WP-LEARN-01",
            "WP-NOTIFY-01", "WP-EXT-01", "WP-ENGAGE-01", "WP-GRAPH-01",
            "WP-SOCIAL-01",
        ],
        "resourceLocks": ["xcode-project", "simulator-device"],
    },
    "WP-EXT-01": {
        "blockedBy": ["WP-ACCOUNT-02", "WP-CONTRACT-02", "WP-NATIVE-01"],
        "blocks": ["WP-ENGAGE-01", "WP-NOTIFY-01", "WP-OFFLINE-01", "WP-JOURNEY-01"],
        "resourceLocks": ["persistence-schema"],
    },
    "WP-READER-01": {
        "blockedBy": ["WP-NATIVE-01", "WP-CONTRACT-02"],
        "blocks": ["WP-ANNOTATE-01", "WP-ASK-01", "WP-LOOP-01", "WP-AUDIO-01"],
        "resourceLocks": [],
    },
}
EXPECTED_REVISED_CAPS = {
    "WP-NATIVE-01": (20, 20, 3, 3, 1),
    "WP-EXT-01": (17, 20, 3, 3, 1),
    "WP-READER-01": (12, 16, 1, 3, 1),
}
NATIVE_AC07_COMMAND = (
    "python3 scripts/visual/validate_upgrade_ui_test_membership.py "
    "--project ChapterFlow.xcodeproj/project.pbxproj "
    "--root ChapterFlowUITests/UpgradeEvidence --require-target ChapterFlowUITests "
    "--extension-evidence-host scripts/localization/NativeExtensionEvidenceHost.swift "
    "--require-extension-target ShareExtension --require-extension-target ActionExtension "
    "--forbid-extension-target ChapterFlow --forbid-extension-target ChapterFlowUITests "
    "--require-target-flag ShareExtension=CF_NATIVE_SHARE_EVIDENCE_TARGET "
    "--require-target-flag ActionExtension=CF_NATIVE_ACTION_EVIDENCE_TARGET "
    "--ordinary-excluded-source NativeExtensionEvidenceHost.swift "
    "--show-build-settings-project ChapterFlow.xcodeproj --scheme ChapterFlow "
    "--configuration Debug "
    "--require-build-setting ShareExtension:EXCLUDED_SOURCE_FILE_NAMES=NativeExtensionEvidenceHost.swift "
    "--require-build-setting ActionExtension:EXCLUDED_SOURCE_FILE_NAMES=NativeExtensionEvidenceHost.swift "
    "--output results/native/ui-test-membership.json"
)
NATIVE_AC04_UNIT_COMMAND = (
    "python3 scripts/localization/validate_matrix.py "
    "--manifest scripts/visual/native-matrix.json --manifest-key localizationMatrix "
    "--candidate <SHA> --output results/native/localization.json"
)
NATIVE_AC04_EXTENSION_COMMAND = (
    "python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj "
    "--scheme ChapterFlow "
    "--test ChapterFlowUITests/NativeEvidenceTests/testShareActionLocalizedAccessibilityMatrix "
    "--candidate <EXACT_CANDIDATE_SHA> "
    "--iphone-udid <PINNED_IPHONE_UDID> --ipad-udid <PINNED_IPAD_UDID> "
    "--scenarios scripts/visual/native-matrix.json "
    "--derived-data /private/tmp/Chapterflow-DD-native-extensions-<EXACT_CANDIDATE_SHA> "
    "--require-dimensions light,dark,compact-iphone,regular-ipad,accessibility,voiceover,"
    "increased-contrast,reduce-motion,reduce-transparency,real-locale,pseudo-long,rtl,keyboard-pointer "
    "--extension-evidence-host scripts/localization/NativeExtensionEvidenceHost.swift "
    "--extension-evidence-condition CF_NATIVE_EXTENSION_EVIDENCE_BUILD "
    "--source-exclusion-variable CF_NATIVE_EXTENSION_EXCLUDED_SOURCES "
    "--exclude-production-source ShareViewController.swift "
    "--exclude-production-source ActionViewController.swift "
    "--require-appex ShareExtension.appex --require-appex ActionExtension.appex "
    "--require-containing-or-system-host-invocation "
    "--require-named-system-elements --require-installed-extension-display-names "
    "--expected-record-count 62 --expected-xcresult-count 2 "
    "--require-system-input-source system "
    "--require-system-trait-values colorSchemeContrast,accessibilityReduceMotion,accessibilityReduceTransparency "
    "--require-fixture-input-source fixture --require-fixture-system-trait-claim none "
    "--require-observed-consequences localization,rtl,plural,formatting,accessibility "
    "--require-token-scoped-reset-observers --require-exact-payload-digest "
    "--require-exact-configuration-digest "
    "--require-extension-identity process,executable,Info.plist "
    "--attempt-chain-id <ATTEMPT_CHAIN_ID> --stage 4-of-4 --require-attempt-number 1 "
    "--require-predecessor-manifest results/native/extension-production-boundary/manifest.json "
    "--require-predecessor-stage 3-of-4 --fail-if-stage-artifact-exists "
    "--stop-on-first-deterministic-mismatch --forbid-retry-greening "
    "--output results/native/extension-localization-matrix"
)
NATIVE_AC04_BOUNDARY_COMMAND = (
    "python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj "
    "--scheme ChapterFlow --extension-production-boundary "
    "--candidate-worktree <CANDIDATE_WORKTREE> --candidate <EXACT_CANDIDATE_SHA> "
    "--expected-head <EXACT_CANDIDATE_SHA> --iphone-udid <PINNED_IPHONE_UDID> "
    "--test ChapterFlowUITests/NativeEvidenceTests/"
    "testExtensionPresentationResultInputSeparatesFixtureAndLegacyProduction "
    "--derived-data /private/tmp/Chapterflow-DD-native-extension-boundary-<EXACT_CANDIDATE_SHA> "
    "--result-bundle results/native/extension-presentation-boundary.xcresult "
    "--extension-evidence-condition CF_NATIVE_EXTENSION_EVIDENCE_BUILD "
    "--source-exclusion-variable CF_NATIVE_EXTENSION_EXCLUDED_SOURCES "
    "--exclude-production-source ShareViewController.swift "
    "--exclude-production-source ActionViewController.swift "
    "--negative-candidate-case missing --negative-candidate-case all-zero "
    "--negative-candidate-case malformed --negative-candidate-case mismatched "
    "--attempt-chain-id <ATTEMPT_CHAIN_ID> --stage 3-of-4 --require-attempt-number 1 "
    "--require-predecessor-manifest results/native/extension-representative/manifest.json "
    "--require-predecessor-stage 2-of-4 --fail-if-stage-artifact-exists "
    "--stop-on-first-deterministic-mismatch --forbid-retry-greening "
    "--output results/native/extension-production-boundary"
)
NATIVE_AC04_BUILD_BOUNDARY_COMMAND = (
    "python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj "
    "--scheme ChapterFlow --extension-build-boundary "
    "--base <BASE_SHA> --candidate <SHA> "
    "--ordinary-configuration Debug --ordinary-configuration Release "
    "--evidence-configuration Debug "
    "--derived-data /private/tmp/Chapterflow-DD-native-extension-build-boundary-<SHA> "
    "--extension-evidence-host scripts/localization/NativeExtensionEvidenceHost.swift "
    "--extension-evidence-condition CF_NATIVE_EXTENSION_EVIDENCE_BUILD "
    "--source-exclusion-variable CF_NATIVE_EXTENSION_EXCLUDED_SOURCES "
    "--require-production-source ShareExtension:ShareExtension/ShareViewController.swift "
    "--require-production-source ActionExtension:ActionExtension/ActionViewController.swift "
    "--exclude-production-source ShareExtension:ShareViewController.swift "
    "--exclude-production-source ActionExtension:ActionViewController.swift "
    "--require-ordinary-host-exclusion --require-evidence-host-inclusion "
    "--require-evidence-production-source-exclusion --require-evidence-marker-separation "
    "--require-unchanged-info-plist ShareExtension/Info.plist "
    "--require-unchanged-info-plist ActionExtension/Info.plist "
    "--require-principal-class ShareExtension=ShareViewController "
    "--require-principal-class ActionExtension=ActionViewController "
    "--require-appex ShareExtension.appex --require-appex ActionExtension.appex "
    "--negative-build-case ShareExtension:missing-debug "
    "--negative-build-case ActionExtension:missing-debug "
    "--negative-build-case ShareExtension:missing-evidence-condition "
    "--negative-build-case ActionExtension:missing-evidence-condition "
    "--negative-build-case ShareExtension:missing-target-flag "
    "--negative-build-case ActionExtension:missing-target-flag "
    "--negative-build-case ShareExtension:dual-target-flags "
    "--negative-build-case ActionExtension:dual-target-flags "
    "--negative-build-case ShareExtension:cross-wired-target-flag "
    "--negative-build-case ActionExtension:cross-wired-target-flag "
    "--negative-build-case ShareExtension:controller-host-collision "
    "--negative-build-case ActionExtension:controller-host-collision "
    "--negative-build-case ShareExtension:release-evidence-reachability "
    "--negative-build-case ActionExtension:release-evidence-reachability "
    "--attempt-chain-id <ATTEMPT_CHAIN_ID> --stage 1-of-4 --require-attempt-number 1 "
    "--require-empty-attempt-chain --fail-if-stage-artifact-exists "
    "--stop-on-first-deterministic-mismatch --forbid-retry-greening "
    "--output results/native/extension-build-boundary"
)
NATIVE_AC04_REPRESENTATIVE_COMMAND = (
    "python3 scripts/visual/run_native_matrix.py --project ChapterFlow.xcodeproj "
    "--scheme ChapterFlow --extension-representative-records "
    "--candidate <EXACT_CANDIDATE_SHA> --iphone-udid <PINNED_IPHONE_UDID> "
    "--scenarios scripts/visual/native-matrix.json "
    "--derived-data /private/tmp/Chapterflow-DD-native-extension-representative-<EXACT_CANDIDATE_SHA> "
    "--record shareextension-compact-iphone-light "
    "--record actionextension-compact-iphone-light --expected-record-count 2 "
    "--require-named-system-elements --require-installed-extension-display-names "
    "--attempt-chain-id <ATTEMPT_CHAIN_ID> --stage 2-of-4 --require-attempt-number 1 "
    "--require-predecessor-manifest results/native/extension-build-boundary/manifest.json "
    "--require-predecessor-stage 1-of-4 --fail-if-stage-artifact-exists "
    "--stop-on-first-deterministic-mismatch --forbid-retry-greening "
    "--output results/native/extension-representative"
)
NATIVE_AC06_TARGETS_REGRESSION_COMMAND = (
    "python3 scripts/visual/touch_targets.py --self-test "
    "--output results/native/touch-target-scanner-regressions.json"
)
EXPECTED_NATIVE_ASSERTION_COMMANDS = {
    "NATIVE-04-UNIT-01": NATIVE_AC04_UNIT_COMMAND,
    "NATIVE-04-EXTENSION-02": NATIVE_AC04_EXTENSION_COMMAND,
    "NATIVE-04-PRODUCTION-BOUNDARY-03": NATIVE_AC04_BOUNDARY_COMMAND,
    "NATIVE-04-BUILD-BOUNDARY-04": NATIVE_AC04_BUILD_BOUNDARY_COMMAND,
    "NATIVE-04-REPRESENTATIVE-05": NATIVE_AC04_REPRESENTATIVE_COMMAND,
    "NATIVE-06-TARGETS-REGRESSION-02": NATIVE_AC06_TARGETS_REGRESSION_COMMAND,
    "NATIVE-07-PROJECT-01": NATIVE_AC07_COMMAND,
}
EXPECTED_NATIVE_ASSERTION_AC = {
    "NATIVE-04-UNIT-01": "AC-NATIVE-01-04",
    "NATIVE-04-EXTENSION-02": "AC-NATIVE-01-04",
    "NATIVE-04-PRODUCTION-BOUNDARY-03": "AC-NATIVE-01-04",
    "NATIVE-04-BUILD-BOUNDARY-04": "AC-NATIVE-01-04",
    "NATIVE-04-REPRESENTATIVE-05": "AC-NATIVE-01-04",
    "NATIVE-06-TARGETS-REGRESSION-02": "AC-NATIVE-01-06",
    "NATIVE-07-PROJECT-01": "AC-NATIVE-01-07",
}
EXPECTED_NATIVE_ASSERTION_ROW_SHA256 = {
    "NATIVE-04-UNIT-01": "76382608cc88d69f790643f9adf610345ceb6a5982f65905390fd5181c5d0d58",
    "NATIVE-04-EXTENSION-02": "a5842ba451f19b616270669cf553be31cca5c23903ded9c65b2b1ab99279db99",
    "NATIVE-04-PRODUCTION-BOUNDARY-03": "c1c0780696d1ac88c14df9a0ebb7b7c9ce89c51c13aee1a3426054d2d1561ecf",
    "NATIVE-04-BUILD-BOUNDARY-04": "c9c78538d629239f94dd71841b30004d90eafd48dd68b1a1aeab54c3e451bbe4",
    "NATIVE-04-REPRESENTATIVE-05": "31be602950771d79b1cb941657e86eae601cf01721a8e5aa5c3a7382cb598584",
    "NATIVE-06-TARGETS-REGRESSION-02": "2a283eec9501b2944390a9a1ed2db142b23e35a953fabbef7b346aafce1e3661",
    "NATIVE-07-PROJECT-01": "56b1d628a1f8a25aa0fd35fcfda3ab253509e23bc9a418c7c286c8b8e9f3f999",
}
EXPECTED_NATIVE_RUNTIME_CORRECTION_PATHS = [
    "ActionExtension/ActionView.swift",
    "ChapterFlowUITests/UpgradeEvidence/NativeUpgradeEvidenceTests.swift",
    "ShareExtension/ShareView.swift",
    "scripts/localization/NativeExtensionEvidenceHost.swift",
    "scripts/visual/native-matrix.json",
    "scripts/visual/run_native_matrix.py",
]
EXPECTED_NATIVE_SYSTEM_TRAITS = [
    "colorSchemeContrast",
    "accessibilityReduceMotion",
    "accessibilityReduceTransparency",
]
EXPECTED_NATIVE_RUNTIME_ORDER = [
    "build-boundary",
    "representative-share-action",
    "production-boundary",
    "full-62-record-matrix",
]
EXPECTED_NATIVE_VALIDATION_ORDER = [
    "NATIVE-04-BUILD-BOUNDARY-04",
    "NATIVE-04-REPRESENTATIVE-05",
    "NATIVE-04-PRODUCTION-BOUNDARY-03",
    "NATIVE-04-EXTENSION-02",
]
EXPECTED_NATIVE_ASSERTION_IDS = [
    "NATIVE-01-UNIT-01",
    "NATIVE-02-UI-01",
    "NATIVE-03-UI-01",
    "NATIVE-04-UNIT-01",
    *EXPECTED_NATIVE_VALIDATION_ORDER,
    "NATIVE-05-UNIT-01",
    "NATIVE-05-PERF-RUNNER-02",
    "NATIVE-06-INVENTORY-01",
    "NATIVE-06-TARGETS-01",
    "NATIVE-06-TARGETS-REGRESSION-02",
    "NATIVE-07-PROJECT-01",
    "NATIVE-08-A11Y-01",
]
EXPECTED_PERFORMANCE_BUDGET_DIGESTS = {
    "PERF-COLD-LAUNCH": "db0518f9180f9fe4f4eb4bd332d97649956823ef04127df5b84c6b2e8b6f0259",
    "PERF-READER-HITCH": "064d0451ffa7b2773504463a5145aea9310a04ecaab1777e871698e5d1a553ca",
    "PERF-READER-PAGINATION": "6beb7bba8c466eacc3ddd9deccf1dc598e127e07792ae1825ff5d694a109523a",
    "PERF-GRAPH-INTERACTION": "2637cf7db209ff5de6ffec13528d2f3a089a206edb1919b1f48f61444db650a6",
    "PERF-CATALOG-HITCH": "cbd9e02863a3c983cb22c161b6e46e60af3cf19cf6d79d952fe98feae7f37884",
    "PERF-IMAGE-CACHE": "2bdd456e74475632809d623afae30096395f44865af48cd9fa46578bc9e75d8d",
    "PERF-MEMORY-ONE-BOOK": "07c382193c3daf7dc2df6e0344feb492cef3a81944eb89a84e55cff4bebdfa7c",
    "PERF-MEMORY-THREE-BOOKS": "f457a50dfa4ad4533329e6700320127deeb927a75e37cd57172f0d11d77eef24",
    "PERF-CHAPTER-FETCH": "27797a78ae31b536df944a082accce8aa5dad92506971ea52f5c803289d87eb2",
    "PERF-MAIN-STALL": "457110be50ef79edf7e8f9e24f85be221a5edc659d582d4b38d9c804e6d6b351",
    "PERF-ENERGY-JOURNEY": "c9baa57da97e605d0bbcff72e8cc56a9a0e9b2206a3a35a5a758a916f5939e1f",
    "PERF-LONG-AUDIO": "848d2880376e9018f0844df99a8b6670048f2b3797766a23265632e0d0daaa91",
    "PERF-DOWNLOAD-LIFECYCLE": "2bda08604ed50d64dcb60fe1e7268912842d823ffa27e6417967ce9d9c7aea00",
}
NUMERIC_PERFORMANCE_CEILINGS = {
    "PERF-COLD-LAUNCH": ("lessThanOrEqual", 1500),
    "PERF-READER-HITCH": ("lessThan", 5),
    "PERF-MEMORY-ONE-BOOK": ("lessThanOrEqual", 120),
    "PERF-MEMORY-THREE-BOOKS": ("lessThanOrEqual", 180),
    "PERF-CHAPTER-FETCH": ("lessThanOrEqual", 2),
    "PERF-MAIN-STALL": ("equal", 0),
}


def package_container_issues(package_id: str, package: object) -> list[str]:
    if not isinstance(package, dict):
        return [f"{package_id} package must be an object"]
    issues: list[str] = []
    ownership = package.get("ownership")
    if not isinstance(ownership, dict):
        issues.append(f"{package_id} ownership must be an object")
    elif not isinstance(ownership.get("allowedPaths"), list):
        issues.append(f"{package_id} allowedPaths must be a list")
    if not isinstance(package.get("estimate"), dict):
        issues.append(f"{package_id} estimate must be an object")
    return issues


def backlog_container_issues(backlog: object) -> list[str]:
    if not isinstance(backlog, dict):
        return ["backlog must be an object"]
    return [] if isinstance(backlog.get("counts"), dict) else ["backlog counts must be an object"]


def canonical_relative_glob(value: object, context: str, issues: list[str]) -> str | None:
    if not isinstance(value, str) or not value:
        issues.append(f"{context} must be a non-empty string")
        return None
    if value.startswith("/") or "\\" in value or "\0" in value or "//" in value:
        issues.append(f"{context} must be a canonical repository-relative glob")
        return None
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        issues.append(f"{context} contains a noncanonical path segment")
        return None
    if value in {"*", "**", "**/*"}:
        issues.append(f"{context} must not be a repository catch-all")
        return None
    return value


def claim_identity(value: object, context: str, issues: list[str]) -> tuple[str, str] | None:
    if not isinstance(value, dict):
        issues.append(f"{context} must be an object")
        return None
    if set(value) != {"repo", "glob"}:
        issues.append(f"{context} must contain exactly repo and glob")
        return None
    repo = value.get("repo")
    if not isinstance(repo, str) or repo not in {"ios", "backend"}:
        issues.append(f"{context}.repo must be ios or backend")
        return None
    glob = canonical_relative_glob(value.get("glob"), f"{context}.glob", issues)
    return (repo, glob) if glob is not None else None


def implementation_root(claim: tuple[str, str]) -> tuple[str, str]:
    repo, glob = claim
    parts = glob.split("/")
    if parts[0] == "Packages" and len(parts) >= 2:
        return repo, "/".join(parts[:2])
    return repo, parts[0]


def native_path_replacement_issues(
    package: dict, candidate: object, replacement: object,
) -> list[str]:
    issues: list[str] = []
    if not isinstance(replacement, dict):
        return ["WP-NATIVE-01 rootAccounting.pathReplacement must be an object"]
    expected_fields = {
        "adjudicatedMain", "parkedHead", "parkedTree", "feasibilityEvidenceSHA256",
        "removedPath", "addedPath", "beforePaths", "afterPaths", "preservedOracles",
    }
    if set(replacement) != expected_fields:
        issues.append("WP-NATIVE-01 pathReplacement must contain the exact reviewed fields")
    expected_identity = {
        "adjudicatedMain": "6c38802db9e24d7f9843f38ea03879d4a5a72860",
        "parkedHead": "a4569f8d316498dd8f4078cbcce3a560ea33a170",
        "parkedTree": "cbd263f5c904b26cb6c517bf6cb21b0794289861",
        "feasibilityEvidenceSHA256": "dda9ae97c4847367587048530531d5950c9fe98a5c747ed1d36d2e12c603507a",
    }
    for field, expected in expected_identity.items():
        if replacement.get(field) != expected:
            issues.append(f"WP-NATIVE-01 pathReplacement.{field} drifted from the adjudicated evidence")
    removed = replacement.get("removedPath")
    added = replacement.get("addedPath")
    if removed != "scripts/localization/scenarios.json":
        issues.append("WP-NATIVE-01 pathReplacement removedPath must retire scenarios.json")
    if added != "scripts/localization/NativeExtensionEvidenceHost.swift":
        issues.append("WP-NATIVE-01 pathReplacement addedPath must be the DEBUG extension evidence host")

    before = replacement.get("beforePaths")
    after = replacement.get("afterPaths")
    candidate_paths = candidate.get("paths") if isinstance(candidate, dict) else None
    if before != candidate_paths:
        issues.append("WP-NATIVE-01 pathReplacement beforePaths must preserve candidateBinding.paths")
    if before != EXPECTED_NATIVE_BEFORE_PATHS:
        issues.append("WP-NATIVE-01 pathReplacement beforePaths drifted from the immutable 20-path manifest")
    if after != EXPECTED_NATIVE_AFTER_PATHS:
        issues.append("WP-NATIVE-01 pathReplacement afterPaths drifted from the exact replacement manifest")
    for label, paths in (("beforePaths", before), ("afterPaths", after)):
        if not isinstance(paths, list):
            issues.append(f"WP-NATIVE-01 pathReplacement {label} must be a list")
            continue
        if paths != sorted(paths):
            issues.append(f"WP-NATIVE-01 pathReplacement {label} must be sorted")
        if len(paths) != 20 or len(set(map(str, paths))) != 20:
            issues.append(f"WP-NATIVE-01 pathReplacement {label} must contain exactly 20 unique paths")
        issues.extend(candidate_path_issues(package, paths))
    if (
        isinstance(before, list) and isinstance(after, list)
        and all(isinstance(path, str) for path in before + after)
    ):
        removed_set = set(before) - set(after)
        added_set = set(after) - set(before)
        if removed_set != {removed} or added_set != {added}:
            issues.append("WP-NATIVE-01 pathReplacement must exchange exactly one removed and one added path")
    if replacement.get("preservedOracles") != EXPECTED_NATIVE_PRESERVED_ORACLES:
        issues.append("WP-NATIVE-01 pathReplacement weakens or drifts a preserved validation oracle")
    return issues


def root_accounting_issues(package_id: str, allowed: object, estimate: object) -> list[str]:
    issues: list[str] = []
    if not isinstance(allowed, list):
        return [f"{package_id} allowedPaths must be a list"]
    if not isinstance(estimate, dict):
        return [f"{package_id} estimate must be an object"]

    allowed_claims: list[tuple[str, str]] = []
    for index, value in enumerate(allowed):
        identity = claim_identity(value, f"{package_id} allowedPaths[{index}]", issues)
        if identity is not None:
            allowed_claims.append(identity)
    if len(allowed_claims) != len(set(allowed_claims)):
        issues.append(f"{package_id} allowedPaths repeats a repo/glob claim")
    if any(repo != "ios" for repo, _ in allowed_claims):
        issues.append(f"{package_id} root-accounted revision may claim only ios paths")

    accounting = estimate.get("rootAccounting")
    if not isinstance(accounting, dict):
        return issues + [f"{package_id} rootAccounting must be an object"]
    if set(accounting) - {"primaryGroups", "nonPrimaryPaths", "candidateBinding", "pathReplacement"}:
        issues.append(f"{package_id} rootAccounting contains unknown fields")
    groups = accounting.get("primaryGroups")
    non_primary = accounting.get("nonPrimaryPaths")
    roots = estimate.get("primaryRoots")
    if not isinstance(groups, list):
        issues.append(f"{package_id} rootAccounting.primaryGroups must be a list")
        groups = []
    if not isinstance(roots, int) or len(groups) != roots:
        issues.append(f"{package_id} rootAccounting must declare exactly primaryRoots groups")
    if not isinstance(non_primary, list):
        issues.append(f"{package_id} rootAccounting.nonPrimaryPaths must be a list")
        non_primary = []

    assigned: list[tuple[str, str]] = []
    allocations: dict[str, int] = {}
    group_ids: set[str] = set()
    for index, group in enumerate(groups):
        context = f"{package_id} rootAccounting.primaryGroups[{index}]"
        if not isinstance(group, dict):
            issues.append(f"{context} must be an object")
            continue
        if set(group) != {"id", "claims", "plannedFiles"}:
            issues.append(f"{context} must contain exactly id, claims, and plannedFiles")
        group_id = group.get("id")
        if not isinstance(group_id, str) or not group_id or group_id in group_ids:
            issues.append(f"{context}.id must be unique and non-empty")
            group_id = f"invalid-group-{index}"
        group_ids.add(group_id)
        claims = group.get("claims")
        if not isinstance(claims, list) or not claims:
            issues.append(f"{context}.claims must be a non-empty list")
            claims = []
        parsed_claims: list[tuple[str, str]] = []
        for claim_index, value in enumerate(claims):
            identity = claim_identity(value, f"{context}.claims[{claim_index}]", issues)
            if identity is not None:
                parsed_claims.append(identity)
        assigned.extend(parsed_claims)
        group_files = group.get("plannedFiles")
        if not isinstance(group_files, int) or isinstance(group_files, bool) or group_files < 1:
            issues.append(f"{context}.plannedFiles must be a positive integer")
        else:
            allocations[f"primary:{group_id}"] = group_files
        roots_in_group = {implementation_root(claim) for claim in parsed_claims}
        if len(roots_in_group) > 1 and not (
            package_id == "WP-EXT-01"
            and group_id == "extension-transaction-boundary"
            and set(parsed_claims) == EXTENSION_TRANSACTION_CLAIMS
            and len(parsed_claims) == len(EXTENSION_TRANSACTION_CLAIMS)
        ):
            issues.append(f"{package_id} rootAccounting group {group_id} crosses implementation roots")

    non_primary_identities: list[tuple[str, str, str]] = []
    validation_support_count = 0
    for index, item in enumerate(non_primary):
        context = f"{package_id} rootAccounting.nonPrimaryPaths[{index}]"
        if not isinstance(item, dict):
            issues.append(f"{context} must be an object")
            continue
        if set(item) != {"repo", "glob", "class", "plannedFiles"}:
            issues.append(f"{context} must contain exactly repo, glob, class, and plannedFiles")
        identity = claim_identity(
            {"repo": item.get("repo"), "glob": item.get("glob")},
            context,
            issues,
        )
        path_class = item.get("class")
        if not isinstance(path_class, str) or path_class not in {
            "validation-support", "validation-tooling", "project-configuration",
        }:
            issues.append(f"{context}.class is invalid")
        if identity is not None and isinstance(path_class, str):
            assigned.append(identity)
            non_primary_identities.append((*identity, path_class))
            if path_class == "validation-support":
                validation_support_count += 1
            path_files = item.get("plannedFiles")
            if not isinstance(path_files, int) or isinstance(path_files, bool) or path_files < 1:
                issues.append(f"{context}.plannedFiles must be a positive integer")
            else:
                allocations[f"non-primary:{identity[0]}:{identity[1]}"] = path_files

    if non_primary_identities != EXPECTED_NON_PRIMARY.get(package_id, []):
        issues.append(f"{package_id} non-primary claims drift from the exact reviewed set")
    if validation_support_count != estimate.get("validationSupportRoots"):
        issues.append(f"{package_id} rootAccounting validation-support count drift")
    if len(assigned) != len(set(assigned)):
        issues.append(f"{package_id} rootAccounting assigns a repo/glob claim more than once")
    if assigned != allowed_claims:
        issues.append(f"{package_id} ordered rootAccounting claims drift from allowedPaths")
    planned_files = estimate.get("plannedFiles")
    if not isinstance(planned_files, int) or sum(allocations.values()) != planned_files:
        issues.append(f"{package_id} rootAccounting planned-file allocation does not equal plannedFiles")

    candidate = accounting.get("candidateBinding")
    if package_id == "WP-NATIVE-01":
        if not isinstance(candidate, dict):
            issues.append("WP-NATIVE-01 rootAccounting.candidateBinding must be an object")
        else:
            expected_fields = {"base", "head", "tree", "diffSha256", "paths", "disposition"}
            if set(candidate) != expected_fields:
                issues.append(
                    "WP-NATIVE-01 candidateBinding must contain exact identity, disposition, and path fields"
                )
            for field in ("base", "head", "tree"):
                if not re.fullmatch(r"[0-9a-f]{40}", str(candidate.get(field, ""))):
                    issues.append(f"WP-NATIVE-01 candidateBinding.{field} must be a full lowercase SHA")
            if candidate.get("base") == candidate.get("head"):
                issues.append("WP-NATIVE-01 candidateBinding base and head must differ")
            if not re.fullmatch(r"[0-9a-f]{64}", str(candidate.get("diffSha256", ""))):
                issues.append("WP-NATIVE-01 candidateBinding.diffSha256 must be a SHA-256 digest")
            if candidate.get("disposition") != EXPECTED_CANDIDATE_DISPOSITION:
                issues.append("WP-NATIVE-01 candidateBinding must remain known-red and scope-only")
            paths = candidate.get("paths")
            if isinstance(paths, list):
                if not all(isinstance(path, str) for path in paths):
                    issues.append("WP-NATIVE-01 candidateBinding.paths must contain only strings")
                elif paths != sorted(paths):
                    issues.append("WP-NATIVE-01 candidateBinding.paths must be sorted")
            issues.extend(candidate_path_issues(
                {
                    "id": package_id,
                    "estimate": estimate,
                },
                paths,
            ))
            if not isinstance(paths, list) or len(paths) != planned_files:
                issues.append("WP-NATIVE-01 candidateBinding path count must equal plannedFiles")
            if candidate != EXPECTED_NATIVE_CANDIDATE_BINDING:
                issues.append("WP-NATIVE-01 candidateBinding must preserve the immutable known-red identity")
        issues.extend(native_path_replacement_issues(
            {"id": package_id, "estimate": estimate},
            candidate,
            accounting.get("pathReplacement"),
        ))
    elif candidate is not None:
        issues.append(f"{package_id} must not carry an unrelated candidateBinding")
    return issues


def accounting_buckets(package: dict) -> tuple[list[tuple[tuple[str, str], str, int]], list[str]]:
    issues: list[str] = []
    estimate = package.get("estimate", {})
    accounting = estimate.get("rootAccounting", {}) if isinstance(estimate, dict) else {}
    if not isinstance(accounting, dict):
        return [], [f"{package.get('id')} rootAccounting must be an object"]
    buckets: list[tuple[tuple[str, str], str, int]] = []
    groups = accounting.get("primaryGroups", [])
    if not isinstance(groups, list):
        return [], [f"{package.get('id')} rootAccounting.primaryGroups must be a list"]
    for group in groups:
        if not isinstance(group, dict):
            continue
        group_id = group.get("id")
        allocation = group.get("plannedFiles")
        claims = group.get("claims", [])
        if not isinstance(claims, list):
            issues.append(f"{package.get('id')} primary claims must be a list")
            continue
        for value in claims:
            identity = claim_identity(value, f"{package.get('id')} primary claim", issues)
            if identity is not None and isinstance(group_id, str) and isinstance(allocation, int):
                buckets.append((identity, f"primary:{group_id}", allocation))
    non_primary = accounting.get("nonPrimaryPaths", [])
    if not isinstance(non_primary, list):
        return buckets, issues + [f"{package.get('id')} rootAccounting.nonPrimaryPaths must be a list"]
    for item in non_primary:
        if not isinstance(item, dict):
            continue
        identity = claim_identity(
            {"repo": item.get("repo"), "glob": item.get("glob")},
            f"{package.get('id')} non-primary claim",
            issues,
        )
        allocation = item.get("plannedFiles")
        if identity is not None and isinstance(allocation, int):
            buckets.append((identity, f"non-primary:{identity[0]}:{identity[1]}", allocation))
    return buckets, issues


def candidate_path_issues(package: dict, paths: object) -> list[str]:
    package_id = package.get("id", "unknown")
    issues: list[str] = []
    if not isinstance(paths, list) or not paths:
        return [f"{package_id} candidate path manifest must be a non-empty list"]
    buckets, bucket_issues = accounting_buckets(package)
    issues.extend(bucket_issues)
    counts: dict[str, int] = {}
    seen: set[str] = set()
    for index, raw_path in enumerate(paths):
        path = canonical_relative_glob(raw_path, f"{package_id} candidatePaths[{index}]", issues)
        if path is None:
            continue
        if any(token in path for token in "*?["):
            issues.append(f"{package_id} candidate path must be exact: {path}")
            continue
        if path in seen:
            issues.append(f"{package_id} candidate path is duplicated: {path}")
            continue
        seen.add(path)
        matches = [
            (bucket_id, allocation)
            for (repo, glob), bucket_id, allocation in buckets
            if repo == "ios" and fnmatch.fnmatchcase(path, glob)
        ]
        if len(matches) != 1:
            issues.append(f"{package_id} candidate path must match exactly one accounted claim: {path}")
            continue
        bucket_id, allocation = matches[0]
        counts[bucket_id] = counts.get(bucket_id, 0) + 1
        if counts[bucket_id] > allocation:
            issues.append(f"{package_id} candidate exceeds {bucket_id} file allocation")
    estimate = package.get("estimate", {})
    max_files = estimate.get("maxFiles") if isinstance(estimate, dict) else None
    if not isinstance(max_files, int) or len(seen) > max_files:
        issues.append(f"{package_id} candidate exceeds maxFiles")
    touched_primary = {bucket for bucket in counts if bucket.startswith("primary:")}
    max_roots = estimate.get("maxPrimaryRoots") if isinstance(estimate, dict) else None
    if not isinstance(max_roots, int) or len(touched_primary) > max_roots:
        issues.append(f"{package_id} candidate exceeds maxPrimaryRoots")
    return issues


def validate_root_accounting_self_tests(packages: dict[str, dict]) -> list[dict[str, object]]:
    """Mutation checks prove malformed or understated accounting fails deterministically."""
    native = packages.get("WP-NATIVE-01")
    if not isinstance(native, dict):
        fail("root-accounting self-tests require WP-NATIVE-01")
        return []

    cases: list[tuple[str, dict, str]] = []
    results: list[dict[str, object]] = []

    duplicate = copy.deepcopy(native)
    duplicate["ownership"]["allowedPaths"].append(
        copy.deepcopy(duplicate["ownership"]["allowedPaths"][0])
    )
    cases.append(("duplicate-claim", duplicate, "repeats a repo/glob claim"))

    malformed_repo = copy.deepcopy(native)
    malformed_repo["ownership"]["allowedPaths"][0]["repo"] = "mobile"
    cases.append(("malformed-repo", malformed_repo, ".repo must be ios or backend"))

    repo_list = copy.deepcopy(native)
    repo_list["ownership"]["allowedPaths"][0]["repo"] = ["ios"]
    cases.append(("repo-list", repo_list, ".repo must be ios or backend"))

    repo_object = copy.deepcopy(native)
    repo_object["ownership"]["allowedPaths"][0]["repo"] = {"name": "ios"}
    cases.append(("repo-object", repo_object, ".repo must be ios or backend"))

    traversal = copy.deepcopy(native)
    traversal["ownership"]["allowedPaths"][0]["glob"] = "Packages/../Secrets/**"
    cases.append(("path-traversal", traversal, "noncanonical path segment"))

    broad_support = copy.deepcopy(native)
    broad_support["ownership"]["allowedPaths"][5]["glob"] = "ChapterFlowUITests/UpgradeEvidence/**"
    broad_support["estimate"]["rootAccounting"]["nonPrimaryPaths"][0]["glob"] = (
        "ChapterFlowUITests/UpgradeEvidence/**"
    )
    cases.append(("broad-validation-support", broad_support, "exact reviewed set"))

    understated = copy.deepcopy(native)
    understated["estimate"]["rootAccounting"]["nonPrimaryPaths"][2]["plannedFiles"] = 4
    cases.append(("understated-wildcard", understated, "planned-file allocation"))

    malformed_shape = copy.deepcopy(native)
    malformed_shape["estimate"]["rootAccounting"] = []
    cases.append(("malformed-shape", malformed_shape, "must be an object"))

    class_list = copy.deepcopy(native)
    class_list["estimate"]["rootAccounting"]["nonPrimaryPaths"][0]["class"] = [
        "validation-support"
    ]
    cases.append(("class-list", class_list, ".class is invalid"))

    class_object = copy.deepcopy(native)
    class_object["estimate"]["rootAccounting"]["nonPrimaryPaths"][0]["class"] = {
        "name": "validation-support"
    }
    cases.append(("class-object", class_object, ".class is invalid"))

    mixed_candidate_paths = copy.deepcopy(native)
    mixed_candidate_paths["estimate"]["rootAccounting"]["candidateBinding"]["paths"][0] = [
        "ActionExtension/ActionView.swift"
    ]
    cases.append(("candidate-mixed-path-types", mixed_candidate_paths, "paths must contain only strings"))

    for case_id, mutated, expected in cases:
        issues = root_accounting_issues(
            "WP-NATIVE-01",
            mutated.get("ownership", {}).get("allowedPaths"),
            mutated.get("estimate"),
        )
        matched = any(expected in issue for issue in issues)
        results.append({"case": case_id, "expected": expected, "matched": matched, "issues": issues})
        if not matched:
            fail(f"root-accounting self-test {case_id} did not fail with {expected!r}")

    duplicate_paths = copy.deepcopy(
        native.get("estimate", {}).get("rootAccounting", {}).get("candidateBinding", {}).get("paths", [])
    )
    if duplicate_paths:
        duplicate_paths.append(duplicate_paths[0])
        duplicate_issues = candidate_path_issues(native, duplicate_paths)
        duplicate_matched = any("duplicated" in issue for issue in duplicate_issues)
        results.append({
            "case": "candidate-duplicate-path",
            "expected": "duplicated",
            "matched": duplicate_matched,
            "issues": duplicate_issues,
        })
        if not duplicate_matched:
            fail("candidate-path self-test duplicate-path did not fail")

    outside_paths = copy.deepcopy(
        native.get("estimate", {}).get("rootAccounting", {}).get("candidateBinding", {}).get("paths", [])
    )
    if outside_paths:
        outside_paths[0] = "ChapterFlow/Unauthorized.swift"
        outside_issues = candidate_path_issues(native, outside_paths)
        outside_matched = any("exactly one accounted claim" in issue for issue in outside_issues)
        results.append({
            "case": "candidate-outside-scope",
            "expected": "exactly one accounted claim",
            "matched": outside_matched,
            "issues": outside_issues,
        })
        if not outside_matched:
            fail("candidate-path self-test outside-scope did not fail")
    return results


def live_markdown_lines(
    markdown: str, structure_issues: list[str] | None = None,
) -> list[str]:
    """Return executable prose, excluding HTML comments and fenced examples."""
    lines: list[str] = []
    in_comment = False
    fence: tuple[str, int] | None = None
    for raw_line in markdown.splitlines():
        if fence is not None:
            fence_character, opening_length = fence
            indentation = len(raw_line) - len(raw_line.lstrip(" "))
            closing = raw_line[indentation:]
            if indentation <= 3 and not closing.startswith("\t") and re.fullmatch(
                rf"{re.escape(fence_character)}{{{opening_length},}}\s*", closing,
            ):
                fence = None
            continue

        visible: list[str] = []
        cursor = 0
        while cursor < len(raw_line):
            if in_comment:
                end = raw_line.find("-->", cursor)
                if end < 0:
                    cursor = len(raw_line)
                    break
                in_comment = False
                cursor = end + 3
                continue
            start = raw_line.find("<!--", cursor)
            if start < 0:
                visible.append(raw_line[cursor:])
                break
            visible.append(raw_line[cursor:start])
            in_comment = True
            cursor = start + 4

        live_line = "".join(visible)
        indentation = len(live_line) - len(live_line.lstrip(" "))
        stripped = live_line[indentation:]
        if not in_comment:
            opening = (
                re.match(r"^(`{3,}|~{3,})(.*)$", stripped)
                if indentation <= 3 and not stripped.startswith("\t")
                else None
            )
            if opening is not None:
                run, info = opening.groups()
                if run[0] != "`" or "`" not in info:
                    fence = (run[0], len(run))
                    continue
        lines.append(live_line)
    if structure_issues is not None:
        if in_comment:
            structure_issues.append("WP-NATIVE-01 VALIDATE has an unterminated HTML comment")
        if fence is not None:
            structure_issues.append("WP-NATIVE-01 VALIDATE has an unterminated fenced block")
    return lines


def acceptance_evidence_lines(native_validate: str) -> tuple[list[str], list[str]]:
    issues: list[str] = []
    live_lines = live_markdown_lines(native_validate, issues)
    headings = [
        index for index, line in enumerate(live_lines)
        if line.strip() == "## Acceptance evidence"
    ]
    if len(headings) != 1:
        return [], ["WP-NATIVE-01 VALIDATE must contain one live Acceptance evidence section"]
    start = headings[0] + 1
    end = len(live_lines)
    for index in range(start, len(live_lines)):
        if re.match(r"^##\s+", live_lines[index].strip()):
            end = index
            break
    section = live_lines[start:end]
    cursor = 0
    while cursor < len(section) and not section[cursor].strip():
        cursor += 1
    expected_header = (
        "| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |"
    )
    if cursor >= len(section) or section[cursor].strip() != expected_header:
        issues.append("WP-NATIVE-01 Acceptance evidence table header drifted")
    separator_index = cursor + 1
    if separator_index >= len(section) or not re.fullmatch(
        r"\|(?:\s*:?-{3,}:?\s*\|){5}", section[separator_index].strip()
    ):
        issues.append("WP-NATIVE-01 Acceptance evidence table separator drifted")
    table_lines = section[cursor:separator_index + 1]
    table_ended = False
    for line in section[separator_index + 1:]:
        if line.startswith("|"):
            if table_ended:
                issues.append("WP-NATIVE-01 Acceptance evidence rows must be contiguous")
            else:
                table_lines.append(line)
        else:
            table_ended = True
    return table_lines, issues


def native_assertion_command_issues(native_validate: str) -> list[str]:
    section, issues = acceptance_evidence_lines(native_validate)
    rows_by_assertion: dict[str, list[list[str]]] = {}
    assertion_order: list[str] = []
    for line in section:
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.split("|")[1:-1]]
        if len(cells) < 3:
            continue
        if len(cells) == 5 and cells[0].startswith("AC-NATIVE-01-"):
            assertion_order.append(cells[1])
        rows_by_assertion.setdefault(cells[1], []).append(cells)
    if assertion_order != EXPECTED_NATIVE_ASSERTION_IDS:
        issues.append("WP-NATIVE-01 assertion ID set/order drifted; placeholder rows are forbidden")
    for assertion_id, expected_command in EXPECTED_NATIVE_ASSERTION_COMMANDS.items():
        rows = rows_by_assertion.get(assertion_id, [])
        if len(rows) != 1:
            issues.append(f"{assertion_id} must have exactly one validation row")
            continue
        cells = rows[0]
        if len(cells) != 5:
            issues.append(f"{assertion_id} validation row must contain exactly five cells")
            continue
        if cells[0] != EXPECTED_NATIVE_ASSERTION_AC[assertion_id]:
            issues.append(f"{assertion_id} AC mapping drifted from the exact reviewed row")
        command_cell = cells[2]
        match = re.fullmatch(r"`([^`]*)`", command_cell)
        if match is None:
            issues.append(f"{assertion_id} command cell must contain one literal command")
        elif match.group(1) != expected_command:
            issues.append(f"{assertion_id} command drifted from the exact reviewed literal")
        row_digest = hashlib.sha256("\x1f".join(cells).encode("utf-8")).hexdigest()
        if row_digest != EXPECTED_NATIVE_ASSERTION_ROW_SHA256[assertion_id]:
            issues.append(f"{assertion_id} full validation row drifted from the exact reviewed row")
    return issues


def native_runtime_evidence_issues(
    packages: dict[str, dict],
    native_contract: str,
    native_validate: str,
) -> list[str]:
    issues: list[str] = []
    native = packages.get("WP-NATIVE-01")
    if not isinstance(native, dict):
        return ["runtime evidence correction requires WP-NATIVE-01"]
    correction = native.get("runtimeEvidenceCorrection")
    if not isinstance(correction, dict):
        return ["WP-NATIVE-01 runtimeEvidenceCorrection must be an object"]

    authority = correction.get("authority")
    if not isinstance(authority, dict):
        issues.append("runtime evidence correction authority must be an object")
    else:
        exact_authority = {
            "acceptedMain": "840e0a48920e1e59c3a6ec9f3be5ae7028c98169",
            "reviewedCandidate": "39843e6d6a0e3468f61ed86f180500bdb7529c44",
            "reviewedTree": "9afbb87bb859ead2dad46f180da2911e119e62c3",
            "ownerTaskId": "019f7d18-71fa-7102-b3b4-6fa43842963e",
            "packageClaim": "retained-by-WP-NATIVE-01",
            "releasedResourceClaims": ["xcode-project", "simulator-device"],
        }
        for field, expected in exact_authority.items():
            if authority.get(field) != expected:
                issues.append(f"runtime evidence correction authority.{field} drifted")
        if authority.get("reviewDisposition") != {
            "status": "not-clear", "P0": 0, "P1": 5, "P2": 2,
        }:
            issues.append("runtime evidence correction must preserve the seven reviewed findings")
        next_correction = authority.get("nextCorrection")
        if not isinstance(next_correction, dict):
            issues.append("runtime evidence nextCorrection must be an object")
        else:
            if next_correction.get("maximumCycles") != 1:
                issues.append("runtime evidence correction must authorize exactly one cycle")
            if next_correction.get("authorizedProductPaths") != EXPECTED_NATIVE_RUNTIME_CORRECTION_PATHS:
                issues.append("runtime evidence correction must preserve the exact six-file product envelope")
            if next_correction.get("authorizedProductPathCount") != 6:
                issues.append("runtime evidence correction authorizedProductPathCount must equal six")
            if (
                next_correction.get("candidateManifestPathCount") != 20
                or next_correction.get("candidateManifestMaxFiles") != 20
                or next_correction.get("candidateManifestMaxPrimaryRoots") != 3
            ):
                issues.append("runtime evidence correction must preserve the 20-path/three-root cap")
            if next_correction.get("forbiddenExpansion") != [
                "new-product-file", "new-target", "generic-evidence-framework",
                "twenty-first-candidate-path", "new-lock", "acceptance-gate-weakening",
            ]:
                issues.append("runtime evidence correction forbidden expansion contract drifted")

    if native.get("resourceLocks") != ["xcode-project", "simulator-device"]:
        issues.append("runtime evidence correction must preserve existing package locks")
    estimate = native.get("estimate", {})
    if not isinstance(estimate, dict) or (
        estimate.get("plannedFiles"), estimate.get("maxFiles"),
        estimate.get("primaryRoots"), estimate.get("maxPrimaryRoots"),
    ) != (20, 20, 3, 3):
        issues.append("runtime evidence correction must preserve package file/root caps")

    traits = correction.get("traitEvidence")
    if not isinstance(traits, dict):
        issues.append("runtime trait evidence contract must be an object")
    else:
        if traits.get("publicGetOnlyEnvironmentValues") != EXPECTED_NATIVE_SYSTEM_TRAITS:
            issues.append("runtime system trait list drifted from the three public get-only values")
        system = traits.get("systemDerived")
        if not isinstance(system, dict) or (
            system.get("inputSource") != "system"
            or system.get("requiredObservedValues") != EXPECTED_NATIVE_SYSTEM_TRAITS
            or system.get("requestedSystemStateClaim")
            != "allowed-only-when-extension-process-observation-matches-request-and-independent-rendered-consequence-is-verified"
            or system.get("preconfiguredMismatchDisposition") != "failed-never-passed-or-skipped"
        ):
            issues.append("runtime system-derived provenance or observed-consequence gate drifted")
        fixture = traits.get("fixtureBehavior")
        if not isinstance(fixture, dict) or fixture != {
            "inputSource": "fixture",
            "systemTraitClaim": "none",
            "qualification": "behavior-only-not-system-setting-proof",
        }:
            issues.append("runtime fixture provenance must remain inputSource=fixture and systemTraitClaim=none")

    manual = correction.get("manualEvidence")
    if not isinstance(manual, dict) or manual != {
        "automatableSemanticChecks": [
            "named-discovered-system-elements",
            "installed-extension-display-names",
            "accessibility-label-value-trait-order-focus",
            "rendered-layout-and-state-consequences",
        ],
        "manualOrSystemPreconfigurationChecks": [
            "spoken-VoiceOver-outcome",
            "pointer-outcome",
            "requested-system-setting-preconfiguration",
        ],
        "selfAttestation": "forbidden",
    }:
        issues.append("runtime manual/system-preconfiguration classification must fail closed")

    records = correction.get("runtimeRecords")
    if not isinstance(records, dict):
        issues.append("runtimeRecords must be an object")
    else:
        if records.get("representativeRecordIDs") != [
            "shareextension-compact-iphone-light", "actionextension-compact-iphone-light",
        ]:
            issues.append("runtime representative Share/Action record IDs drifted")
        if records.get("fullMatrixRecordCount") != 62 or records.get("perTargetDeviceRecordCounts") != {
            "ShareExtension.compact-iphone": 15,
            "ActionExtension.compact-iphone": 15,
            "ShareExtension.regular-ipad": 16,
            "ActionExtension.regular-ipad": 16,
        }:
            issues.append("runtime full matrix must preserve exactly 62 records")
        if records.get("executionOrderAfterClearStaticReview") != EXPECTED_NATIVE_RUNTIME_ORDER:
            issues.append("runtime execution order drifted")
        if records.get("stageChain") != {
            "identity": "required-shared-attempt-chain-id",
            "requiredAttemptNumber": 1,
            "predecessorManifestDigest": "required-after-first-stage",
            "existingStageArtifactDisposition": "fail-no-overwrite-or-retry",
        }:
            issues.append("runtime stage chain/order/single-attempt contract drifted")
        if records.get("stopPolicy") != "stop-on-first-deterministic-mismatch-no-retry-based-greening":
            issues.append("runtime deterministic mismatch policy drifted")
        if records.get("observedConsequenceRequirements") != [
            "localized-rendered-value", "rtl-rendered-order",
            "plural-selected-branch-and-rendered-value", "formatted-rendered-value",
            "accessibility-rendered-semantic-or-visual-consequence",
        ]:
            issues.append("runtime observed localization/accessibility consequence requirements drifted")

    integrity = correction.get("integrity")
    if not isinstance(integrity, dict) or integrity != {
        "observerScope": "record-token-scoped",
        "observerReset": "before-each-record",
        "requiredDigests": ["exact-payload-digest", "exact-configuration-digest"],
        "requiredIdentityBindings": [
            "extension-process", "extension-executable", "extension-Info.plist",
        ],
        "fullMatrixXCResultCount": 2,
        "fullMatrixXCResults": ["pinned-iphone", "pinned-ipad"],
    }:
        issues.append("runtime observer/digest/identity/exactly-two-xcresults contract drifted")
    if correction.get("candidateBinding") != {
        "productionBoundaryCandidate": "required-nonzero-exact-40-lowercase-hex-sha",
        "missingOrZeroCandidateDisposition": "fail-before-test-execution",
    }:
        issues.append("runtime production-boundary exact candidate binding drifted")

    normalized_contract = " ".join(native_contract.split()).lower()
    for marker in (
        "inputSource=system", "inputSource=fixture", "systemTraitClaim=none",
        "get-only system preferences", "spoken VoiceOver", "pointer behavior",
        "named discovered system elements", "installed extension display names",
        "exactly 62", "exactly two xcresults", "token-scoped observers",
        "exact payload", "configuration digests", "process/executable/Info.plist",
        "stop on the first deterministic mismatch", "nonzero exact",
        "--require-correction-envelope", "attempt-chain ID",
    ):
        if marker.lower() not in normalized_contract:
            issues.append(f"runtime evidence contract prose omits {marker}")

    section, table_issues = acceptance_evidence_lines(native_validate)
    issues.extend(table_issues)
    row_order: list[str] = []
    for line in section:
        cells = [cell.strip() for cell in line.split("|")[1:-1]] if line.startswith("|") else []
        if len(cells) == 5 and cells[1] in EXPECTED_NATIVE_VALIDATION_ORDER:
            row_order.append(cells[1])
    if row_order != EXPECTED_NATIVE_VALIDATION_ORDER:
        issues.append("runtime validation rows drifted from build/representative/production/full order")
    issues.extend(native_assertion_command_issues(native_validate))
    return issues


def native_extension_host_issues(
    packages: dict[str, dict],
    native_contract: str,
    native_validate: str,
    reader_contract: str,
) -> list[str]:
    issues: list[str] = []
    if len(packages) != 24:
        issues.append("extension evidence host revision must preserve exactly 24 packages")
    native = packages.get("WP-NATIVE-01")
    if not isinstance(native, dict):
        return issues + ["extension evidence host revision requires WP-NATIVE-01"]

    host = native.get("extensionEvidenceHost")
    if not isinstance(host, dict):
        issues.append("WP-NATIVE-01 extensionEvidenceHost must be an object")
    else:
        if host.get("sourcePath") != "scripts/localization/NativeExtensionEvidenceHost.swift":
            issues.append("extension evidence host source is absent from the exact replacement path")
        if host.get("sourceTargets") != ["ShareExtension", "ActionExtension"]:
            issues.append("extension evidence host must compile only in both extension targets")
        if host.get("forbiddenSourceTargets") != ["ChapterFlow", "ChapterFlowUITests"]:
            issues.append("extension evidence host must forbid main-app and UI-test source membership")
        evidence_build = host.get("evidenceBuild")
        if not isinstance(evidence_build, dict):
            issues.append("extension evidence host evidenceBuild must be an object")
        else:
            conditions = evidence_build.get("commonCompilationConditions")
            if conditions != ["DEBUG", "CF_NATIVE_EXTENSION_EVIDENCE_BUILD"]:
                issues.append("extension evidence host requires DEBUG plus the exact evidence condition")
            if evidence_build.get("targetCompilationConditions") != {
                "ShareExtension": "CF_NATIVE_SHARE_EVIDENCE_TARGET",
                "ActionExtension": "CF_NATIVE_ACTION_EVIDENCE_TARGET",
            }:
                issues.append("extension evidence host target compilation conditions drifted")
            if evidence_build.get("sourceExclusionBuildSetting") != "EXCLUDED_SOURCE_FILE_NAMES":
                issues.append("extension evidence host source exclusion build setting drifted")
            if evidence_build.get("sourceExclusionVariable") != "CF_NATIVE_EXTENSION_EXCLUDED_SOURCES":
                issues.append("extension evidence host exclusion variable drifted")
            if evidence_build.get("ordinaryExcludedSource") != "NativeExtensionEvidenceHost.swift":
                issues.append("ordinary builds must exclude the extension evidence host")
            if evidence_build.get("excludedProductionSources") != {
                "ShareExtension": "ShareViewController.swift",
                "ActionExtension": "ActionViewController.swift",
            }:
                issues.append("evidence build must exclude both production extension controllers")
        production = host.get("productionConfigurations")
        expected_production = EXPECTED_NATIVE_EXTENSION_EVIDENCE_HOST["productionConfigurations"]
        if production != expected_production:
            issues.append("production Debug and Release must exclude the host and include controllers")
        if host.get("principalControllers") != {
            "ShareExtension": "ShareViewController",
            "ActionExtension": "ActionViewController",
        }:
            issues.append("extension evidence host principal controller names drifted")
        if host.get("readOnlyInfoPlists") != {
            "ShareExtension": "ShareExtension/Info.plist",
            "ActionExtension": "ActionExtension/Info.plist",
        }:
            issues.append("extension evidence host must preserve both production Info.plists read-only")
        invocation = host.get("invocation")
        if not isinstance(invocation, dict) or invocation.get("flow") != EXPECTED_NATIVE_EXTENSION_EVIDENCE_HOST["invocation"]["flow"]:
            issues.append("extension evidence must invoke each real appex through containing/system host UI")
        elif invocation.get("forbiddenSubstitutes") != EXPECTED_NATIVE_EXTENSION_EVIDENCE_HOST["invocation"]["forbiddenSubstitutes"]:
            issues.append("extension evidence host forbidden runtime substitutes drifted")
        fixture = host.get("fixtureEvidence")
        if not isinstance(fixture, dict) or fixture.get("stateSource") != "fixture" or fixture.get("transactionClaim") != "none":
            issues.append("extension fixture evidence must state stateSource=fixture and transactionClaim=none")
        elif fixture.get("doesNotProve") != EXPECTED_NATIVE_EXTENSION_EVIDENCE_HOST["fixtureEvidence"]["doesNotProve"]:
            issues.append("extension fixture evidence must not claim transaction, durability, dismissal, or app opening")
        if host != EXPECTED_NATIVE_EXTENSION_EVIDENCE_HOST:
            issues.append("WP-NATIVE-01 extensionEvidenceHost drifted from the exact reviewed contract")

    for package_id, expected_paths in EXPECTED_REVISED_OWNERSHIP.items():
        package = packages.get(package_id)
        if not isinstance(package, dict):
            issues.append(f"extension evidence host revision requires {package_id}")
            continue
        allowed = package.get("ownership", {}).get("allowedPaths", [])
        actual_paths = [claim.get("glob") for claim in allowed if isinstance(claim, dict)]
        if actual_paths != expected_paths:
            issues.append(f"{package_id} ownership drifted during extension evidence host reconsolidation")
        expected_graph = EXPECTED_REVISED_GRAPH[package_id]
        for field in ("blockedBy", "blocks", "resourceLocks"):
            if package.get(field) != expected_graph[field]:
                issues.append(f"{package_id} {field} drifted during extension evidence host reconsolidation")
        estimate = package.get("estimate", {})
        actual_caps = (
            estimate.get("plannedFiles"), estimate.get("maxFiles"),
            estimate.get("primaryRoots"), estimate.get("maxPrimaryRoots"),
            estimate.get("validationSupportRoots"),
        )
        if actual_caps != EXPECTED_REVISED_CAPS[package_id]:
            issues.append(f"{package_id} file/root caps drifted during extension evidence host reconsolidation")

    required_contract_markers = (
        "scripts/localization/NativeExtensionEvidenceHost.swift",
        "CF_NATIVE_EXTENSION_EVIDENCE_BUILD",
        "CF_NATIVE_SHARE_EVIDENCE_TARGET",
        "CF_NATIVE_ACTION_EVIDENCE_TARGET",
        "EXCLUDED_SOURCE_FILE_NAMES",
        "CF_NATIVE_EXTENSION_EXCLUDED_SOURCES",
        "ShareViewController.swift",
        "ActionViewController.swift",
        "ShareExtension.appex",
        "ActionExtension.appex",
        "containing/system host",
        "stateSource=fixture",
        "transactionClaim=none",
        "source scanning",
        "main app or UI-test bundle",
    )
    for marker in required_contract_markers:
        if marker.lower() not in native_contract.lower():
            issues.append(f"WP-NATIVE-01 extension host contract omits {marker}")
    if "--manifest-key localizationMatrix" not in native_validate:
        issues.append("WP-NATIVE-01 localization oracle was not moved to localizationMatrix")
    issues.extend(native_assertion_command_issues(native_validate))
    for marker in ("reader-toolbar.depth-option", "reader-toolbar.tone-option", "WP-READER-01"):
        if marker not in reader_contract:
            issues.append(f"WP-READER-01 touch-target ownership contract omits {marker}")
    return issues


def validate_native_extension_host_self_tests(packages: dict[str, dict]) -> list[dict[str, object]]:
    native_root = ROOT / "workstreams/03-native-design-accessibility-localization/WP-NATIVE-01"
    reader_root = ROOT / "workstreams/06-reader-annotations-ai/WP-READER-01"
    native_contract = "\n".join(
        (native_root / name).read_text(encoding="utf-8")
        for name in ("SPEC.md", "RUN.md", "VALIDATE.md")
    )
    native_validate = (native_root / "VALIDATE.md").read_text(encoding="utf-8")
    reader_contract = "\n".join(
        (reader_root / name).read_text(encoding="utf-8")
        for name in ("SPEC.md", "RUN.md", "VALIDATE.md")
    )

    def collect(
        mutated: dict[str, dict],
        contract: str = native_contract,
        validate: str = native_validate,
        reader_text: str = reader_contract,
    ) -> list[str]:
        native = mutated.get("WP-NATIVE-01", {})
        ownership = native.get("ownership", {}) if isinstance(native, dict) else {}
        estimate = native.get("estimate", {}) if isinstance(native, dict) else {}
        issues = root_accounting_issues(
            "WP-NATIVE-01",
            ownership.get("allowedPaths") if isinstance(ownership, dict) else None,
            estimate,
        )
        issues.extend(native_extension_host_issues(mutated, contract, validate, reader_text))
        issues.extend(native_runtime_evidence_issues(mutated, contract, validate))
        return issues

    cases: list[tuple[str, dict[str, dict], str, str, str, str]] = []

    def add(case_id: str, mutated: dict[str, dict], expected: str,
            contract: str = native_contract, validate: str = native_validate,
            reader_text: str = reader_contract) -> None:
        cases.append((case_id, mutated, expected, contract, validate, reader_text))

    def mutate_validation_cell(assertion_id: str, cell_index: int, value: str) -> str:
        row = next(
            line for line in native_validate.splitlines()
            if f"| {assertion_id} |" in line
        )
        cells = [cell.strip() for cell in row.split("|")[1:-1]]
        cells[cell_index] = value
        replacement = "| " + " | ".join(cells) + " |"
        return native_validate.replace(row, replacement, 1)

    missing_replacement = copy.deepcopy(packages)
    del missing_replacement["WP-NATIVE-01"]["estimate"]["rootAccounting"]["pathReplacement"]
    add("missing-replacement", missing_replacement, "pathReplacement")

    system_as_fixture = copy.deepcopy(packages)
    system_as_fixture["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["traitEvidence"]["systemDerived"]["inputSource"] = "fixture"
    add("runtime-system-provenance-weakened", system_as_fixture, "system-derived provenance")

    fixture_claim = copy.deepcopy(packages)
    fixture_claim["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["traitEvidence"]["fixtureBehavior"]["systemTraitClaim"] = "requested-state"
    add("runtime-fixture-system-claim", fixture_claim, "inputSource=fixture and systemTraitClaim=none")

    consequence_removed = copy.deepcopy(packages)
    consequence_removed["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["runtimeRecords"]["observedConsequenceRequirements"].pop()
    add("runtime-observed-consequence-removed", consequence_removed, "observed localization/accessibility consequence")

    six_file_removed = copy.deepcopy(packages)
    six_file_removed["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["authority"]["nextCorrection"]["authorizedProductPaths"].pop()
    add("runtime-six-file-envelope-removed", six_file_removed, "exact six-file product envelope")

    seventh_file = copy.deepcopy(packages)
    seventh_file["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["authority"]["nextCorrection"]["authorizedProductPaths"].append("scripts/visual/new-framework.py")
    add("runtime-seventh-correction-file", seventh_file, "exact six-file product envelope")

    record_count = copy.deepcopy(packages)
    record_count["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["runtimeRecords"]["fullMatrixRecordCount"] = 61
    add("runtime-record-count-weakened", record_count, "exactly 62 records")

    execution_order = copy.deepcopy(packages)
    execution_order["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["runtimeRecords"]["executionOrderAfterClearStaticReview"] = [
        "representative-share-action", "build-boundary", "production-boundary", "full-62-record-matrix",
    ]
    add("runtime-execution-order-weakened", execution_order, "execution order drifted")

    manual_attestation = copy.deepcopy(packages)
    manual_attestation["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["manualEvidence"]["selfAttestation"] = "allowed"
    add("runtime-manual-self-attestation", manual_attestation, "manual/system-preconfiguration classification")

    observer_scope = copy.deepcopy(packages)
    observer_scope["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["integrity"]["observerScope"] = "global"
    add("runtime-observer-scope-weakened", observer_scope, "observer/digest/identity/exactly-two-xcresults")

    xcresult_count = copy.deepcopy(packages)
    xcresult_count["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["integrity"]["fullMatrixXCResultCount"] = 3
    add("runtime-xcresult-count-weakened", xcresult_count, "observer/digest/identity/exactly-two-xcresults")

    candidate_binding = copy.deepcopy(packages)
    candidate_binding["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["candidateBinding"]["productionBoundaryCandidate"] = "optional"
    add("runtime-exact-candidate-binding-weakened", candidate_binding, "exact candidate binding")

    stage_chain = copy.deepcopy(packages)
    stage_chain["WP-NATIVE-01"]["runtimeEvidenceCorrection"]["runtimeRecords"]["stageChain"]["requiredAttemptNumber"] = 2
    add("runtime-stage-chain-weakened", stage_chain, "stage chain/order/single-attempt")

    missing_candidate_command = native_validate.replace(
        " --expected-head <EXACT_CANDIDATE_SHA>", "", 1,
    )
    add(
        "runtime-production-candidate-command-removed", copy.deepcopy(packages),
        "NATIVE-04-PRODUCTION-BOUNDARY-03 command drifted",
        validate=missing_candidate_command,
    )

    missing_candidate_negative = native_validate.replace(
        " --negative-candidate-case malformed", "", 1,
    )
    add(
        "runtime-production-candidate-negative-removed", copy.deepcopy(packages),
        "NATIVE-04-PRODUCTION-BOUNDARY-03 command drifted",
        validate=missing_candidate_negative,
    )

    full_matrix_coordinate_fallback = mutate_validation_cell(
        "NATIVE-04-EXTENSION-02", 2,
        "`" + NATIVE_AC04_EXTENSION_COMMAND.replace(
            "--require-named-system-elements --require-installed-extension-display-names ", "",
        ) + "`",
    )
    add(
        "runtime-full-matrix-named-selection-removed", copy.deepcopy(packages),
        "NATIVE-04-EXTENSION-02 command drifted",
        validate=full_matrix_coordinate_fallback,
    )

    representative_predecessor_removed = mutate_validation_cell(
        "NATIVE-04-REPRESENTATIVE-05", 2,
        "`" + NATIVE_AC04_REPRESENTATIVE_COMMAND.replace(
            "--require-predecessor-manifest results/native/extension-build-boundary/manifest.json ", "",
        ) + "`",
    )
    add(
        "runtime-stage-predecessor-removed", copy.deepcopy(packages),
        "NATIVE-04-REPRESENTATIVE-05 command drifted",
        validate=representative_predecessor_removed,
    )

    final_native_row = next(
        line for line in native_validate.splitlines()
        if "| NATIVE-08-A11Y-01 |" in line
    )
    placeholder_row = (
        "| AC-NATIVE-01-04 | NATIVE-04-TODO-99 | `echo TODO results/native/todo.json` "
        "| placeholder | `results/native/todo.json` |"
    )
    placeholder_validate = native_validate.replace(
        final_native_row + "\n", final_native_row + "\n" + placeholder_row + "\n", 1,
    )
    add(
        "runtime-placeholder-row-added", copy.deepcopy(packages),
        "placeholder rows are forbidden",
        validate=placeholder_validate,
    )

    path_21 = copy.deepcopy(packages)
    path_21["WP-NATIVE-01"]["estimate"]["rootAccounting"]["pathReplacement"]["afterPaths"].append(
        "scripts/localization/UnexpectedEvidenceHost.swift"
    )
    add("twenty-first-path", path_21, "exactly 20 unique paths")

    duplicate_host = copy.deepcopy(packages)
    duplicate_host["WP-NATIVE-01"]["estimate"]["rootAccounting"]["pathReplacement"]["afterPaths"].append(
        "scripts/localization/NativeExtensionEvidenceHost.swift"
    )
    add("duplicate-host-path", duplicate_host, "exactly 20 unique paths")

    missing_host = copy.deepcopy(packages)
    after = missing_host["WP-NATIVE-01"]["estimate"]["rootAccounting"]["pathReplacement"]["afterPaths"]
    after[after.index("scripts/localization/NativeExtensionEvidenceHost.swift")] = "scripts/localization/scenarios.json"
    after.sort()
    add("missing-host-path", missing_host, "afterPaths drifted")

    weakened_oracle = copy.deepcopy(packages)
    weakened_oracle["WP-NATIVE-01"]["estimate"]["rootAccounting"]["pathReplacement"]["preservedOracles"]["mergedManifestKey"] = "staticClaim"
    add("weakened-localization-oracle", weakened_oracle, "weakens or drifts")

    missing_membership = copy.deepcopy(packages)
    after = missing_membership["WP-NATIVE-01"]["estimate"]["rootAccounting"]["pathReplacement"]["afterPaths"]
    after.remove("scripts/visual/validate_upgrade_ui_test_membership.py")
    add("missing-ac07-validator", missing_membership, "afterPaths drifted")

    controller_claim = copy.deepcopy(packages)
    controller_claim["WP-NATIVE-01"]["ownership"]["allowedPaths"].append(
        {"repo": "ios", "glob": "ShareExtension/ShareViewController.swift"}
    )
    add("production-controller-ownership", controller_claim, "ownership drifted")

    plist_claim = copy.deepcopy(packages)
    plist_claim["WP-NATIVE-01"]["ownership"]["allowedPaths"].append(
        {"repo": "ios", "glob": "ActionExtension/Info.plist"}
    )
    add("production-plist-ownership", plist_claim, "ownership drifted")

    production_reachable = copy.deepcopy(packages)
    production_reachable["WP-NATIVE-01"]["extensionEvidenceHost"]["productionConfigurations"]["Debug"]["hostDisposition"] = "included"
    add("production-host-reachable", production_reachable, "Production Debug and Release".lower())

    missing_debug = copy.deepcopy(packages)
    missing_debug["WP-NATIVE-01"]["extensionEvidenceHost"]["evidenceBuild"]["commonCompilationConditions"] = ["CF_NATIVE_EXTENSION_EVIDENCE_BUILD"]
    add("missing-debug-condition", missing_debug, "requires DEBUG")

    missing_evidence = copy.deepcopy(packages)
    missing_evidence["WP-NATIVE-01"]["extensionEvidenceHost"]["evidenceBuild"]["commonCompilationConditions"] = ["DEBUG"]
    add("missing-evidence-condition", missing_evidence, "exact evidence condition")

    cross_wired_target = copy.deepcopy(packages)
    cross_wired_target["WP-NATIVE-01"]["extensionEvidenceHost"]["evidenceBuild"]["targetCompilationConditions"]["ActionExtension"] = "CF_NATIVE_SHARE_EVIDENCE_TARGET"
    add("cross-wired-target-condition", cross_wired_target, "target compilation conditions")

    missing_controller_exclusion = copy.deepcopy(packages)
    del missing_controller_exclusion["WP-NATIVE-01"]["extensionEvidenceHost"]["evidenceBuild"]["excludedProductionSources"]["ActionExtension"]
    add("missing-controller-exclusion", missing_controller_exclusion, "exclude both production")

    main_import = copy.deepcopy(packages)
    main_import["WP-NATIVE-01"]["extensionEvidenceHost"]["sourceTargets"].append("ChapterFlow")
    add("main-app-source-import", main_import, "compile only in both extension targets")

    ui_import = copy.deepcopy(packages)
    ui_import["WP-NATIVE-01"]["extensionEvidenceHost"]["sourceTargets"].append("ChapterFlowUITests")
    add("ui-test-source-import", ui_import, "compile only in both extension targets")

    static_invocation = copy.deepcopy(packages)
    static_invocation["WP-NATIVE-01"]["extensionEvidenceHost"]["invocation"]["flow"] = ["source-scan-as-runtime-evidence"]
    add("static-invocation", static_invocation, "real appex")

    transaction_claim = copy.deepcopy(packages)
    transaction_claim["WP-NATIVE-01"]["extensionEvidenceHost"]["fixtureEvidence"]["transactionClaim"] = "durable"
    add("fixture-transaction-claim", transaction_claim, "transactionClaim=none")

    changed_locks = copy.deepcopy(packages)
    changed_locks["WP-NATIVE-01"]["resourceLocks"].append("persistence-schema")
    add("changed-locks", changed_locks, "resourceLocks drifted")

    changed_dag = copy.deepcopy(packages)
    changed_dag["WP-READER-01"]["blockedBy"].remove("WP-NATIVE-01")
    add("changed-dag-direction", changed_dag, "blockedBy drifted")

    changed_count = copy.deepcopy(packages)
    changed_count.pop("WP-SOCIAL-01")
    add("changed-package-count", changed_count, "exactly 24 packages")

    changed_caps = copy.deepcopy(packages)
    changed_caps["WP-NATIVE-01"]["estimate"]["maxFiles"] = 21
    add("changed-native-cap", changed_caps, "file/root caps drifted")

    ext_broadened = copy.deepcopy(packages)
    ext_broadened["WP-EXT-01"]["ownership"]["allowedPaths"].append(
        {"repo": "ios", "glob": "ShareExtension/ShareView.swift"}
    )
    add("ext-ownership-broadened", ext_broadened, "WP-EXT-01 ownership drifted")

    reader_broadened = copy.deepcopy(packages)
    reader_broadened["WP-READER-01"]["ownership"]["allowedPaths"].append(
        {"repo": "ios", "glob": "ActionExtension/ActionView.swift"}
    )
    add("reader-ownership-broadened", reader_broadened, "WP-READER-01 ownership drifted")

    static_extension_validate = native_validate.replace(
        f"`{NATIVE_AC04_EXTENSION_COMMAND}`",
        f"`{NATIVE_AC04_UNIT_COMMAND}`",
    )
    add(
        "extension-runtime-static-substitution", copy.deepcopy(packages),
        "NATIVE-04-EXTENSION-02 command drifted",
        validate=static_extension_validate,
    )
    extension_row_in_comment = static_extension_validate.replace(
        "\n\nEvery selector requires",
        "\n<!--\n"
        "| AC-NATIVE-01-04 | NATIVE-04-EXTENSION-02 | "
        f"`{NATIVE_AC04_EXTENSION_COMMAND}` | relocated non-executable row | none |\n"
        "-->\n\nEvery selector requires",
        1,
    )
    add(
        "extension-row-relocated-into-html-comment", copy.deepcopy(packages),
        "NATIVE-04-EXTENSION-02 command drifted",
        validate=extension_row_in_comment,
    )
    relocated_ac07_validate = native_validate.replace(
        f"`{NATIVE_AC07_COMMAND}`",
        f"`{NATIVE_AC04_UNIT_COMMAND}`",
    ) + f"\n<!-- relocated but non-executable: {NATIVE_AC07_COMMAND} -->\n"
    add(
        "ac07-command-relocated", copy.deepcopy(packages),
        "NATIVE-07-PROJECT-01 command drifted",
        validate=relocated_ac07_validate,
    )
    ac07_row_in_fence = native_validate.replace(
        f"`{NATIVE_AC07_COMMAND}`",
        f"`{NATIVE_AC04_UNIT_COMMAND}`",
        1,
    ).replace(
        "\n\nEvery selector requires",
        "\n```text\n"
        "| AC-NATIVE-01-07 | NATIVE-07-PROJECT-01 | "
        f"`{NATIVE_AC07_COMMAND}` | relocated non-executable row | none |\n"
        "```\n\nEvery selector requires",
        1,
    )
    add(
        "ac07-row-relocated-into-fenced-code", copy.deepcopy(packages),
        "NATIVE-07-PROJECT-01 command drifted",
        validate=ac07_row_in_fence,
    )
    extension_live_row = next(
        line for line in native_validate.splitlines()
        if "| NATIVE-04-EXTENSION-02 |" in line
    )
    four_backtick_relocation = native_validate.replace(
        extension_live_row + "\n", "", 1,
    ).replace(
        "\n\nEvery selector requires",
        "\n````text\n```\n"
        "| AC-NATIVE-01-04 | NATIVE-04-EXTENSION-02 | "
        f"`{NATIVE_AC04_EXTENSION_COMMAND}` | falsely exposed row | none |\n"
        "\nEvery selector requires",
        1,
    )
    add(
        "extension-row-after-short-fence-close", copy.deepcopy(packages),
        "unterminated fenced block",
        validate=four_backtick_relocation,
    )
    blank_relocation = native_validate.replace(
        extension_live_row + "\n", "", 1,
    ).replace(
        "\n\nEvery selector requires",
        "\n\n| AC-NATIVE-01-04 | NATIVE-04-EXTENSION-02 | "
        f"`{NATIVE_AC04_EXTENSION_COMMAND}` | noncontiguous row | none |\n"
        "Every selector requires",
        1,
    )
    add(
        "extension-row-relocated-after-table-blank", copy.deepcopy(packages),
        "Acceptance evidence rows must be contiguous",
        validate=blank_relocation,
    )
    add(
        "unterminated-validation-html-comment", copy.deepcopy(packages),
        "unterminated HTML comment",
        validate=native_validate + "\n<!--\n",
    )
    add(
        "unterminated-validation-fenced-block", copy.deepcopy(packages),
        "unterminated fenced block",
        validate=native_validate + "\n```text\n",
    )
    add(
        "duplicate-live-acceptance-heading", copy.deepcopy(packages),
        "one live Acceptance evidence section",
        validate=native_validate + "\n## Acceptance evidence\n",
    )
    weakened_unit_validate = native_validate.replace(
        "--manifest-key localizationMatrix", "--manifest-key staticClaim", 1,
    )
    add(
        "localization-row-weakened", copy.deepcopy(packages),
        "NATIVE-04-UNIT-01 command drifted",
        validate=weakened_unit_validate,
    )
    weakened_boundary_validate = native_validate.replace(
        " --exclude-production-source ActionViewController.swift", "", 1,
    )
    add(
        "boundary-controller-exclusion-weakened", copy.deepcopy(packages),
        "NATIVE-04-PRODUCTION-BOUNDARY-03 command drifted",
        validate=weakened_boundary_validate,
    )
    build_boundary_row = next(
        line for line in native_validate.splitlines()
        if "| NATIVE-04-BUILD-BOUNDARY-04 |" in line
    )
    removed_build_boundary_validate = native_validate.replace(
        build_boundary_row + "\n", "", 1,
    )
    add(
        "extension-build-boundary-row-removed", copy.deepcopy(packages),
        "NATIVE-04-BUILD-BOUNDARY-04 must have exactly one validation row",
        validate=removed_build_boundary_validate,
    )
    targets_regression_row = next(
        line for line in native_validate.splitlines()
        if "| NATIVE-06-TARGETS-REGRESSION-02 |" in line
    )
    removed_targets_regression_validate = native_validate.replace(
        targets_regression_row + "\n", "", 1,
    )
    add(
        "touch-target-regression-row-removed", copy.deepcopy(packages),
        "NATIVE-06-TARGETS-REGRESSION-02 must have exactly one validation row",
        validate=removed_targets_regression_validate,
    )
    malformed_targets_regression_validate = native_validate.replace(
        targets_regression_row,
        targets_regression_row[:-1] + "| unexpected |",
        1,
    )
    add(
        "touch-target-regression-row-malformed", copy.deepcopy(packages),
        "NATIVE-06-TARGETS-REGRESSION-02 validation row must contain exactly five cells",
        validate=malformed_targets_regression_validate,
    )
    altered_targets_regression_validate = mutate_validation_cell(
        "NATIVE-06-TARGETS-REGRESSION-02", 2,
        "`python3 scripts/visual/touch_targets.py --self-test --allow-skips "
        "--output results/native/touch-target-scanner-regressions.json`",
    )
    add(
        "touch-target-regression-command-altered", copy.deepcopy(packages),
        "NATIVE-06-TARGETS-REGRESSION-02 command drifted",
        validate=altered_targets_regression_validate,
    )
    remapped_targets_regression_validate = mutate_validation_cell(
        "NATIVE-06-TARGETS-REGRESSION-02", 0, "AC-NATIVE-01-05",
    )
    add(
        "touch-target-regression-ac-remapped", copy.deepcopy(packages),
        "NATIVE-06-TARGETS-REGRESSION-02 AC mapping drifted",
        validate=remapped_targets_regression_validate,
    )
    weakened_build_boundary_validate = native_validate.replace(
        "--ordinary-configuration Debug --ordinary-configuration Release ",
        "--ordinary-configuration Debug ",
        1,
    )
    add(
        "extension-build-boundary-release-removed", copy.deepcopy(packages),
        "NATIVE-04-BUILD-BOUNDARY-04 command drifted",
        validate=weakened_build_boundary_validate,
    )
    weakened_build_boundary_debug_validate = native_validate.replace(
        "--ordinary-configuration Debug --ordinary-configuration Release ",
        "--ordinary-configuration Release ",
        1,
    )
    add(
        "extension-build-boundary-debug-removed", copy.deepcopy(packages),
        "NATIVE-04-BUILD-BOUNDARY-04 command drifted",
        validate=weakened_build_boundary_debug_validate,
    )
    weakened_evidence_boundary_validate = native_validate.replace(
        "--evidence-configuration Debug ", "", 1,
    )
    add(
        "extension-build-boundary-evidence-removed", copy.deepcopy(packages),
        "NATIVE-04-BUILD-BOUNDARY-04 command drifted",
        validate=weakened_evidence_boundary_validate,
    )
    weakened_project_membership_validate = native_validate.replace(
        "--require-extension-target ShareExtension --require-extension-target ActionExtension ",
        "--require-extension-target ShareExtension ",
        1,
    )
    add(
        "extension-project-membership-weakened", copy.deepcopy(packages),
        "NATIVE-07-PROJECT-01 command drifted",
        validate=weakened_project_membership_validate,
    )
    weakened_show_settings_validate = native_validate.replace(
        "--show-build-settings-project ChapterFlow.xcodeproj ", "", 1,
    )
    add(
        "extension-show-build-settings-removed", copy.deepcopy(packages),
        "NATIVE-07-PROJECT-01 command drifted",
        validate=weakened_show_settings_validate,
    )
    for assertion_id in EXPECTED_NATIVE_ASSERTION_COMMANDS:
        add(
            f"{assertion_id.lower()}-oracle-weakened", copy.deepcopy(packages),
            f"{assertion_id} full validation row drifted",
            validate=mutate_validation_cell(assertion_id, 3, "command exits zero"),
        )
    add(
        "extension-build-boundary-artifact-weakened", copy.deepcopy(packages),
        "NATIVE-04-BUILD-BOUNDARY-04 full validation row drifted",
        validate=mutate_validation_cell(
            "NATIVE-04-BUILD-BOUNDARY-04", 4, "`results/native/fake.json`",
        ),
    )
    add(
        "extension-build-boundary-ac-remapped", copy.deepcopy(packages),
        "NATIVE-04-BUILD-BOUNDARY-04 AC mapping drifted",
        validate=mutate_validation_cell(
            "NATIVE-04-BUILD-BOUNDARY-04", 0, "AC-NATIVE-01-07",
        ),
    )
    add(
        "reader-touch-ownership-removed", copy.deepcopy(packages), "touch-target ownership contract omits",
        reader_text=reader_contract.replace("reader-toolbar.depth-option", "reader-toolbar.removed-option"),
    )

    results: list[dict[str, object]] = []
    duplicate_key_issues: list[str] = []
    try:
        unique_json_object([("pathReplacement", {}), ("pathReplacement", {})])
    except DuplicateJSONKeyError as error:
        duplicate_key_issues.append(str(error))
    duplicate_key_matched = any("duplicate JSON key: pathReplacement" in issue for issue in duplicate_key_issues)
    results.append({
        "case": "duplicate-replacement-key",
        "expected": "duplicate JSON key: pathReplacement",
        "matched": duplicate_key_matched,
        "issues": duplicate_key_issues,
    })
    if not duplicate_key_matched:
        fail("extension-evidence-host self-test duplicate-replacement-key did not fail")
    escaped_correction_issues = correction_diff_issues(
        packages["WP-NATIVE-01"],
        "39843e6d6a0e3468f61ed86f180500bdb7529c44",
        ["Packages/DesignSystem/Sources/DesignSystem/NativeEvidenceAccessibility.swift"],
    )
    escaped_correction_matched = any(
        "escaped the exact six-file product envelope" in issue
        for issue in escaped_correction_issues
    )
    results.append({
        "case": "runtime-correction-diff-escaped-six-files",
        "expected": "escaped the exact six-file product envelope",
        "matched": escaped_correction_matched,
        "issues": escaped_correction_issues,
    })
    if not escaped_correction_matched:
        fail("runtime correction diff envelope self-test did not fail")
    for case_id, mutated, expected, contract, validate, reader_text in cases:
        issues = collect(mutated, contract, validate, reader_text)
        matched = any(expected.lower() in issue.lower() for issue in issues)
        results.append({"case": case_id, "expected": expected, "matched": matched, "issues": issues})
        if not matched:
            fail(f"extension-evidence-host self-test {case_id} did not fail with {expected!r}")
    return results


def validate_container_shape_self_tests(
    packages: dict[str, dict], backlog: dict,
) -> list[dict[str, object]]:
    native = packages.get("WP-NATIVE-01")
    if not isinstance(native, dict):
        fail("container-shape self-tests require WP-NATIVE-01")
        return []
    package_cases: list[tuple[str, dict, str]] = []

    estimate_list = copy.deepcopy(native)
    estimate_list["estimate"] = []
    package_cases.append(("estimate-list", estimate_list, "estimate must be an object"))

    ownership_list = copy.deepcopy(native)
    ownership_list["ownership"] = []
    package_cases.append(("ownership-list", ownership_list, "ownership must be an object"))

    allowed_paths_null = copy.deepcopy(native)
    allowed_paths_null["ownership"]["allowedPaths"] = None
    package_cases.append(("allowed-paths-null", allowed_paths_null, "allowedPaths must be a list"))

    results: list[dict[str, object]] = []
    for case_id, mutated, expected in package_cases:
        issues = package_container_issues("WP-NATIVE-01", mutated)
        matched = any(expected in issue for issue in issues)
        results.append({"case": case_id, "expected": expected, "matched": matched, "issues": issues})
        if not matched:
            fail(f"container-shape self-test {case_id} did not fail with {expected!r}")

    backlog_counts = copy.deepcopy(backlog)
    backlog_counts["counts"] = []
    issues = backlog_container_issues(backlog_counts)
    expected = "backlog counts must be an object"
    matched = expected in issues
    results.append({
        "case": "backlog-counts-list",
        "expected": expected,
        "matched": matched,
        "issues": issues,
    })
    if not matched:
        fail("container-shape self-test backlog-counts-list did not fail")
    return results


def run_git(arguments: list[str]) -> tuple[bytes | None, str | None]:
    try:
        result = subprocess.run(
            ["git", "-C", str(ROOT.parent), *arguments],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        return None, str(error)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        return None, detail or f"git exited {result.returncode}"
    return result.stdout, None


def correction_diff_issues(package: dict, base: str, actual_paths: list[str]) -> list[str]:
    issues: list[str] = []
    correction = package.get("runtimeEvidenceCorrection")
    authority = correction.get("authority") if isinstance(correction, dict) else None
    next_correction = authority.get("nextCorrection") if isinstance(authority, dict) else None
    if not isinstance(next_correction, dict):
        return ["WP-NATIVE-01 has no runtime correction envelope"]
    if base != authority.get("reviewedCandidate"):
        issues.append("WP-NATIVE-01 correction base must equal the reviewed candidate")
    allowed = next_correction.get("authorizedProductPaths")
    if not actual_paths:
        issues.append("WP-NATIVE-01 correction diff must change at least one authorized path")
    if not isinstance(allowed, list) or any(path not in allowed for path in actual_paths):
        issues.append("WP-NATIVE-01 correction diff escaped the exact six-file product envelope")
    return issues


def validate_candidate_diff(
    package: dict,
    base: str,
    head: str,
    require_binding: bool,
    require_correction_envelope: bool,
) -> None:
    package_id = package.get("id", "unknown")
    if not re.fullmatch(r"[0-9a-f]{40}", base) or not re.fullmatch(r"[0-9a-f]{40}", head):
        fail(f"{package_id} --base and --head must be full lowercase SHAs")
        return
    estimate = package.get("estimate", {})
    accounting = estimate.get("rootAccounting", {}) if isinstance(estimate, dict) else {}
    binding = accounting.get("candidateBinding") if isinstance(accounting, dict) else None
    replacement = accounting.get("pathReplacement") if isinstance(accounting, dict) else None
    if not isinstance(binding, dict):
        fail(f"{package_id} has no candidateBinding for --package-diff")
        return
    if require_binding and require_correction_envelope:
        fail("--require-candidate-binding and --require-correction-envelope are mutually exclusive")
        return
    if require_binding and (binding.get("base") != base or binding.get("head") != head):
        fail(f"{package_id} requested candidate identities drift from candidateBinding")

    ancestor_output, ancestor_error = run_git(["merge-base", "--is-ancestor", base, head])
    if ancestor_error is not None:
        fail(f"{package_id} base is not an ancestor of head: {ancestor_error}")
    elif ancestor_output not in {b"", None}:
        fail(f"{package_id} unexpected merge-base output")

    tree_output, tree_error = run_git(["rev-parse", f"{head}^{{tree}}"])
    if tree_error is not None:
        fail(f"{package_id} cannot resolve candidate tree: {tree_error}")
    else:
        actual_tree = tree_output.decode("ascii", errors="replace").strip()
        if require_binding and actual_tree != binding.get("tree"):
            fail(f"{package_id} candidate tree drift: {actual_tree}")

    paths_output, paths_error = run_git(["diff", "--name-only", "-z", base, head, "--"])
    actual_paths: list[str] = []
    if paths_error is not None:
        fail(f"{package_id} cannot read candidate paths: {paths_error}")
    else:
        actual_paths = sorted(
            value.decode("utf-8", errors="strict")
            for value in paths_output.split(b"\0")
            if value
        )
        if require_binding and actual_paths != binding.get("paths"):
            fail(f"{package_id} candidate path manifest drift")
        if require_correction_envelope:
            if package_id != "WP-NATIVE-01":
                fail(f"{package_id} has no runtime correction envelope")
            else:
                for issue in correction_diff_issues(package, base, actual_paths):
                    fail(issue)
        elif not require_binding and package_id == "WP-NATIVE-01":
            expected_after = replacement.get("afterPaths") if isinstance(replacement, dict) else None
            if actual_paths != expected_after:
                fail(f"{package_id} remediation path manifest drift from adjudicated replacement")
        for issue in candidate_path_issues(package, actual_paths):
            fail(issue)

    diff_output, diff_error = run_git(["diff", "--binary", base, head, "--"])
    if diff_error is not None:
        fail(f"{package_id} cannot read canonical binary diff: {diff_error}")
    else:
        digest = hashlib.sha256(diff_output).hexdigest()
        if require_binding and digest != binding.get("diffSha256"):
            fail(f"{package_id} canonical binary diff digest drift: {digest}")


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
        for issue in package_container_issues(package_id, package):
            fail(issue)
        ownership = package.get("ownership")
        if not isinstance(ownership, dict):
            ownership = {}
            package["ownership"] = ownership
        allowed = ownership.get("allowedPaths")
        if not isinstance(allowed, list):
            allowed = []
            ownership["allowedPaths"] = allowed
        estimate = package.get("estimate")
        if not isinstance(estimate, dict):
            estimate = {}
            package["estimate"] = estimate
        if path.parent.name != package_id:
            fail(f"directory/ID mismatch: {path.parent.name} != {package_id}")
        if path.parents[1].name != package.get("workstream"):
            fail(f"workstream mismatch for {package_id}")
        for companion in ("SPEC.md", "RUN.md", "VALIDATE.md"):
            if not (path.parent / companion).is_file():
                fail(f"{package_id} missing {companion}")

        owner = ownership.get("ownerLane")
        if not isinstance(owner, str) or not owner or owner in owners:
            fail(f"{package_id} must have a unique non-empty owner lane")
        else:
            owners.add(owner)
        if ownership.get("writableOwner") != "single":
            fail(f"{package_id} writableOwner must be single")
        if not allowed:
            fail(f"{package_id} has no allowed paths")
        for claim_index, claim in enumerate(allowed if isinstance(allowed, list) else []):
            claim_issues: list[str] = []
            identity = claim_identity(claim, f"{package_id} allowedPaths[{claim_index}]", claim_issues)
            for issue in claim_issues:
                fail(issue)
            if identity is None:
                continue
            _, glob = identity
            if glob in banned_broad_paths:
                fail(f"{package_id} has overbroad write claim: {glob}")
            if glob.startswith("upgrade/") or glob.startswith("/Users/radinsoltani/Chapterflow-IOS"):
                fail(f"{package_id} claims prohibited plan/owner path: {glob}")
        prohibited_text = json.dumps(ownership.get("prohibitedPaths", []))
        for marker in ("upgrade/**", "/Users/radinsoltani/Chapterflow-IOS/**", "#117"):
            if marker not in prohibited_text:
                fail(f"{package_id} prohibited paths omit {marker}")

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

        if package_id in REVISED_ROOT_PACKAGES:
            for issue in root_accounting_issues(package_id, allowed, estimate):
                fail(issue)

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
        live_validate_lines = live_markdown_lines(validate)
        assertion_ids: set[str] = set()
        for criterion in package_criteria:
            if criterion in criteria:
                fail(f"duplicate acceptance criterion: {criterion}")
            criteria.add(criterion)
            if criterion not in spec or criterion not in validate:
                fail(f"{package_id} criterion missing from SPEC/VALIDATE: {criterion}")
            rows = [line for line in live_validate_lines if line.startswith(f"| {criterion} |")]
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
                    if (
                        "--extension-build-boundary" not in command
                        and "--extension-representative-records" not in command
                        and "--extension-production-boundary" not in command
                    ):
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


def performance_commands(package_id: str, packages: dict[str, dict]) -> list[str]:
    package = packages.get(package_id, {})
    workstream = package.get("workstream") if isinstance(package, dict) else None
    if not isinstance(workstream, str):
        return []
    path = ROOT / "workstreams" / workstream / package_id / "VALIDATE.md"
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        fail(f"cannot read {package_id} performance contract: {error}")
        return []
    return re.findall(r"`([^`]*scripts/visual/run_paired_performance\.py[^`]*)`", text)


def command_option(tokens: list[str], option: str) -> str | None:
    values = command_options(tokens, option)
    return values[0] if len(values) == 1 else None


def command_options(tokens: list[str], option: str) -> list[str]:
    values: list[str] = []
    for index, token in enumerate(tokens):
        if token == option and index + 1 < len(tokens) and not tokens[index + 1].startswith("--"):
            values.append(tokens[index + 1])
    return values


def split_performance_command(command: str, package_id: str) -> list[str]:
    try:
        return shlex.split(command)
    except ValueError as error:
        fail(f"{package_id} paired-runner command cannot be parsed: {error}")
        return []


def performance_command_shape_issues(
    tokens: list[str],
    *,
    flags: dict[str, int],
    valued_options: dict[str, int],
) -> list[str]:
    issues: list[str] = []
    if tokens[:2] != ["python3", "scripts/visual/run_paired_performance.py"]:
        issues.append("must start with exact python3 paired-runner executable")
        return issues
    observed_flags = {option: 0 for option in flags}
    observed_values = {option: 0 for option in valued_options}
    index = 2
    while index < len(tokens):
        token = tokens[index]
        if token in flags:
            observed_flags[token] += 1
            index += 1
            continue
        if token in valued_options:
            if index + 1 >= len(tokens) or tokens[index + 1].startswith("--"):
                issues.append(f"{token} must have one value")
                index += 1
                continue
            observed_values[token] += 1
            index += 2
            continue
        issues.append(f"contains unexpected token {token!r}")
        index += 1
    for option, expected in flags.items():
        if observed_flags[option] != expected:
            issues.append(f"{option} must occur exactly {expected} time(s)")
    for option, expected in valued_options.items():
        if observed_values[option] != expected:
            issues.append(f"{option} must occur exactly {expected} time(s)")
    return issues


def validate_performance_consumer_contracts(
    packages: dict[str, dict],
    budgets_by_id: dict[str, dict],
) -> None:
    native_commands = performance_commands("WP-NATIVE-01", packages)
    if len(native_commands) != 1:
        fail("WP-NATIVE-01 must declare exactly one paired-runner self-test command")
    else:
        native_tokens = split_performance_command(native_commands[0], "WP-NATIVE-01")
        for issue in performance_command_shape_issues(
            native_tokens,
            flags={"--self-test": 1},
            valued_options={
                "--self-test-budget-id": 2,
                "--budget-manifest": 1,
                "--output": 1,
            },
        ):
            fail(f"WP-NATIVE-01 paired-runner command {issue}")
        native_allowed = {
            "--self-test", "--self-test-budget-id", "--budget-manifest", "--output",
        }
        native_options = {token for token in native_tokens if token.startswith("--")}
        if native_options != native_allowed:
            fail("WP-NATIVE-01 paired runner self-test options drift from the canonical interface")
        if "--self-test" not in native_tokens:
            fail("WP-NATIVE-01 paired runner contract must include --self-test")
        if command_option(native_tokens, "--budget-manifest") != "upgrade/program/performance-budgets.json":
            fail("WP-NATIVE-01 paired runner self-test must consume the canonical budget manifest")
        if command_options(native_tokens, "--self-test-budget-id") != [
            "PERF-READER-PAGINATION", "PERF-GRAPH-INTERACTION",
        ]:
            fail("WP-NATIVE-01 paired runner self-test must exercise Reader then Graph consumers")
        forbidden = {"--base", "--candidate", "--result-bundle-root", "--graph-policy"}
        if forbidden & set(native_tokens):
            fail("WP-NATIVE-01 paired runner contract retains an incompatible legacy option")

    consumers = {
        "WP-READER-01": {
            "budget": "PERF-READER-PAGINATION",
            "devices": ["--iphone-udid", "--ipad-udid"],
            "fixture": "reader-pagination-hermetic-v1",
            "test": "ChapterFlowUITests/ReaderPerformanceTests/testPaginationBudget",
            "derivedData": "/private/tmp/Chapterflow-DD-reader-pagination-<SHA>",
            "output": "results/reader/pagination-performance",
        },
        "WP-GRAPH-01": {
            "budget": "PERF-GRAPH-INTERACTION",
            "devices": ["--iphone-udid"],
            "fixture": "concept-graph-hermetic-v1",
            "test": "ChapterFlowUITests/GraphUpgradeEvidenceTests/testConceptGraphPerformanceBudgets",
            "derivedData": "/private/tmp/Chapterflow-DD-graph-perf-<SHA>",
            "output": "results/graph/performance",
        },
    }
    for package_id, expected in consumers.items():
        budget_id = expected["budget"]
        commands = performance_commands(package_id, packages)
        if len(commands) != 1:
            fail(f"{package_id} must declare exactly one paired-runner consumer command")
            continue
        tokens = split_performance_command(commands[0], package_id)
        required_options = {
            "--project", "--scheme", "--main-worktree", "--candidate-worktree",
            "--main-sha", "--candidate-sha", "--test", "--samples",
            "--operating-system", "--toolchain-id", "--fixture", "--derived-data-root",
            "--budget-manifest", "--budget-id", "--output",
        } | set(expected["devices"])
        allowed_options = required_options | {"--instruments-template"}
        for issue in performance_command_shape_issues(
            tokens,
            flags={},
            valued_options={
                **{option: 1 for option in required_options},
                "--instruments-template": 2,
            },
        ):
            fail(f"{package_id} paired-runner command {issue}")
        actual_options = {token for token in tokens if token.startswith("--")}
        if actual_options != allowed_options:
            fail(f"{package_id} paired-runner options drift from the canonical interface")
        missing = sorted(option for option in required_options if command_option(tokens, option) is None)
        if missing:
            fail(f"{package_id} paired-runner command omits unique valued options: {missing}")
        for option in ("--iphone-udid", "--ipad-udid"):
            present = command_option(tokens, option) is not None
            if present != (option in expected["devices"]):
                fail(f"{package_id} paired-runner device options drift from its budget")
        expected_values = {
            "--project": "ChapterFlow.xcodeproj",
            "--scheme": "ChapterFlow",
            "--main-worktree": "<CURRENT_MAIN_WORKTREE>",
            "--candidate-worktree": "<CANDIDATE_WORKTREE>",
            "--main-sha": "<CURRENT_MAIN_SHA>",
            "--candidate-sha": "<SHA>",
            "--test": expected["test"],
            "--samples": "30",
            "--operating-system": "<PINNED_OS>",
            "--toolchain-id": "<PINNED_TOOLCHAIN_ID>",
            "--fixture": expected["fixture"],
            "--derived-data-root": expected["derivedData"],
            "--budget-manifest": "upgrade/program/performance-budgets.json",
            "--budget-id": budget_id,
            "--output": expected["output"],
        }
        for option, value in expected_values.items():
            if command_option(tokens, option) != value:
                fail(f"{package_id} paired-runner {option} must be {value}")
        if command_options(tokens, "--instruments-template") != ["Hangs", "SwiftUI"]:
            fail(f"{package_id} paired-runner must retain ordered Hangs and SwiftUI traces")
        if command_option(tokens, "--iphone-udid") != "<PINNED_IPHONE_UDID>":
            fail(f"{package_id} paired-runner must pin the declared iPhone device")
        if "--ipad-udid" in expected["devices"] and command_option(
            tokens, "--ipad-udid"
        ) != "<PINNED_IPAD_UDID>":
            fail(f"{package_id} paired-runner must pin the declared iPad device")
        if command_option(tokens, "--budget-manifest") != "upgrade/program/performance-budgets.json":
            fail(f"{package_id} paired-runner command uses a noncanonical budget manifest")
        if command_option(tokens, "--budget-id") != budget_id:
            fail(f"{package_id} paired-runner command must bind {budget_id}")
        output = command_option(tokens, "--output")
        if output is None or output.endswith(".json"):
            fail(f"{package_id} paired-runner output must be an artifact directory")
        forbidden = {"--base", "--candidate", "--result-bundle-root", "--graph-policy"}
        if forbidden & set(tokens):
            fail(f"{package_id} paired-runner command retains an incompatible legacy option")
        budget = budgets_by_id.get(budget_id)
        if not isinstance(budget, dict) or not str(budget.get("operator", "")).startswith("pairedBaseline"):
            fail(f"{package_id} budget ID does not resolve to a paired budget")
            continue
        execution = budget.get("pairedExecution")
        if not isinstance(execution, dict):
            fail(f"{package_id} budget lacks structured pairedExecution")
            continue
        expected_device_classes = [
            "compact-iphone",
            *(["regular-ipad"] if "--ipad-udid" in expected["devices"] else []),
        ]
        if execution.get("order") != ["current-main", "candidate"]:
            fail(f"{package_id} budget order must be current-main then candidate")
        if execution.get("samples") != 30:
            fail(f"{package_id} budget sample count must be 30")
        if execution.get("deviceClasses") != expected_device_classes:
            fail(f"{package_id} budget device classes drift from its consumer command")
        if execution.get("instrumentTemplates") != ["Hangs", "SwiftUI"]:
            fail(f"{package_id} budget trace templates drift from its consumer command")
        if execution.get("fixture") != expected["fixture"]:
            fail(f"{package_id} budget fixture drifts from its consumer command")


def validate_performance_command_self_tests(
    packages: dict[str, dict],
) -> list[dict[str, object]]:
    native_commands = performance_commands("WP-NATIVE-01", packages)
    reader_commands = performance_commands("WP-READER-01", packages)
    if len(native_commands) != 1 or len(reader_commands) != 1:
        fail("performance-command self-tests require canonical NATIVE and READER commands")
        return []
    native_tokens = split_performance_command(native_commands[0], "WP-NATIVE-01")
    reader_tokens = split_performance_command(reader_commands[0], "WP-READER-01")
    reader_valued = {
        option: 1
        for option in (
            "--project", "--scheme", "--main-worktree", "--candidate-worktree",
            "--main-sha", "--candidate-sha", "--test", "--samples", "--iphone-udid",
            "--ipad-udid", "--operating-system", "--toolchain-id", "--fixture",
            "--derived-data-root", "--budget-manifest", "--budget-id", "--output",
        )
    }
    reader_valued["--instruments-template"] = 2
    cases = [
        (
            "echo-prefix",
            ["echo", *reader_tokens],
            {},
            reader_valued,
            "exact python3 paired-runner executable",
        ),
        (
            "extra-positional-suffix",
            [*reader_tokens, "EXTRA_POSITIONAL"],
            {},
            reader_valued,
            "unexpected token",
        ),
        (
            "duplicate-self-test-flag",
            [*native_tokens, "--self-test"],
            {"--self-test": 1},
            {"--self-test-budget-id": 2, "--budget-manifest": 1, "--output": 1},
            "--self-test must occur exactly 1 time",
        ),
    ]
    results: list[dict[str, object]] = []
    for case_id, tokens, flags, valued_options, expected in cases:
        issues = performance_command_shape_issues(
            tokens,
            flags=flags,
            valued_options=valued_options,
        )
        matched = any(expected in issue for issue in issues)
        results.append({"case": case_id, "expected": expected, "matched": matched, "issues": issues})
        if not matched:
            fail(f"performance-command self-test {case_id} did not fail with {expected!r}")
    return results


def performance_budget_issues(document: object) -> list[str]:
    issues: list[str] = []
    if not isinstance(document, dict):
        return ["performance budgets must be a JSON object"]
    if document.get("schemaVersion") != 1:
        issues.append("performance budget schemaVersion must remain 1")
    if document.get("status") != "predeclared-before-implementation":
        issues.append("performance budget status must remain predeclared-before-implementation")
    source = document.get("source")
    if not isinstance(source, dict):
        issues.append("performance budget source must be an object")
    else:
        expected_source = {
            "path": "docs/PerfBudget.md",
            "sha256AtPlanningBase": "0761280828cbf29230a6a7a2f27b63d4725748670606e4d7639098220614ca2a",
            "iosRevision": "22da44d27bc18771f4d7db7681e17c10970ccb13",
            "evidenceType": "repository budget; current final-device measurements remain pending",
        }
        if source != expected_source:
            issues.append("performance budget source metadata drift")
    if document.get("referenceDevice") != "iPhone 15 Pro":
        issues.append("performance budget reference device drift")
    if document.get("requiredDeviceClasses") != [
        "current supported compact iPhone class",
        "current supported regular-width iPad class",
    ]:
        issues.append("performance budget required device classes drift")
    expected_change_policy = (
        "Implementation lanes may tighten but never loosen or replace these budgets. "
        "A proposed relaxation is BLOCKED_OWNER_DECISION and requires a new reviewed planning "
        "revision with measured provenance before candidate work."
    )
    if document.get("changePolicy") != expected_change_policy:
        issues.append("performance budget change policy drift")

    budgets = document.get("budgets")
    if not isinstance(budgets, list):
        return issues + ["performance budgets must be a list"]
    valid_ids: list[str] = []
    budgets_by_id: dict[str, dict] = {}
    for index, budget in enumerate(budgets):
        if not isinstance(budget, dict):
            issues.append(f"performance budget entry {index} must be an object")
            continue
        budget_id = budget.get("id")
        if not isinstance(budget_id, str) or not budget_id:
            issues.append(f"performance budget entry {index} id must be a non-empty string")
            continue
        valid_ids.append(budget_id)
        if budget_id in budgets_by_id:
            issues.append(f"performance budget ID is duplicated: {budget_id}")
        else:
            budgets_by_id[budget_id] = budget
        for field in ("metric", "operator", "unit", "method", "samplePolicy"):
            if not isinstance(budget.get(field), str) or not budget.get(field):
                issues.append(f"performance budget {budget_id} {field} must be a non-empty string")
        value = budget.get("value")
        if isinstance(value, bool) or not isinstance(value, (int, float, str)) or value == "":
            issues.append(f"performance budget {budget_id} value has an invalid type")
        expected_digest = EXPECTED_PERFORMANCE_BUDGET_DIGESTS.get(budget_id)
        digest = hashlib.sha256(
            json.dumps(budget, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()
        if expected_digest is None or digest != expected_digest:
            issues.append(f"performance budget {budget_id} semantic fingerprint drift")

        numeric = NUMERIC_PERFORMANCE_CEILINGS.get(budget_id)
        if numeric is not None:
            operator, ceiling = numeric
            if budget.get("operator") != operator:
                issues.append(f"performance budget {budget_id} numeric operator drift")
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                issues.append(f"performance budget {budget_id} numeric value must be a number")
            elif operator == "equal" and value != ceiling:
                issues.append(f"performance budget {budget_id} must remain exactly {ceiling}")
            elif operator != "equal" and value > ceiling:
                issues.append(f"performance budget {budget_id} exceeds reviewed ceiling {ceiling}")

        if str(budget.get("operator", "")).startswith("pairedBaseline"):
            sample_policy = budget.get("samplePolicy")
            if not isinstance(sample_policy, str) or "current-main first" not in sample_policy:
                issues.append(f"paired budget {budget_id} lacks baseline-before-candidate policy")

    if set(valid_ids) != set(EXPECTED_PERFORMANCE_BUDGET_DIGESTS) or len(valid_ids) != len(set(valid_ids)):
        issues.append("performance budget IDs must be unique and cover every declared device metric")

    expected_paired = {
        "PERF-READER-PAGINATION": {
            "order": ["current-main", "candidate"],
            "samples": 30,
            "deviceClasses": ["compact-iphone", "regular-ipad"],
            "instrumentTemplates": ["Hangs", "SwiftUI"],
            "fixture": "reader-pagination-hermetic-v1",
        },
        "PERF-GRAPH-INTERACTION": {
            "order": ["current-main", "candidate"],
            "samples": 30,
            "deviceClasses": ["compact-iphone"],
            "instrumentTemplates": ["Hangs", "SwiftUI"],
            "fixture": "concept-graph-hermetic-v1",
        },
    }
    for budget_id, execution in expected_paired.items():
        budget = budgets_by_id.get(budget_id)
        if not isinstance(budget, dict) or budget.get("pairedExecution") != execution:
            issues.append(f"performance budget {budget_id} structured paired execution drift")
    return issues


def validate_performance_budget_self_tests(document: object) -> list[dict[str, object]]:
    if not isinstance(document, dict):
        fail("performance-budget self-tests require an object")
        return []
    cases: list[tuple[str, object, str]] = []

    graph_as_reader = copy.deepcopy(document)
    reader = next(item for item in graph_as_reader["budgets"] if item.get("id") == "PERF-READER-PAGINATION")
    graph_index = next(
        index for index, item in enumerate(graph_as_reader["budgets"])
        if item.get("id") == "PERF-GRAPH-INTERACTION"
    )
    graph_as_reader["budgets"][graph_index] = {**copy.deepcopy(reader), "id": "PERF-GRAPH-INTERACTION"}
    cases.append(("graph-replaced-with-reader-semantics", graph_as_reader, "semantic fingerprint drift"))

    relaxed = copy.deepcopy(document)
    next(item for item in relaxed["budgets"] if item.get("id") == "PERF-COLD-LAUNCH")["value"] = 1501
    cases.append(("numeric-budget-relaxation", relaxed, "exceeds reviewed ceiling"))

    reversed_order = copy.deepcopy(document)
    next(
        item for item in reversed_order["budgets"]
        if item.get("id") == "PERF-READER-PAGINATION"
    )["pairedExecution"]["order"] = ["candidate", "current-main"]
    cases.append(("candidate-first-order", reversed_order, "structured paired execution drift"))

    malformed_id = copy.deepcopy(document)
    malformed_id["budgets"][0]["id"] = {"not": "hashable"}
    cases.append(("malformed-budget-id", malformed_id, "id must be a non-empty string"))

    malformed_field = copy.deepcopy(document)
    malformed_field["budgets"][0]["metric"] = ["not", "a", "string"]
    cases.append(("malformed-budget-field", malformed_field, "metric must be a non-empty string"))

    malformed_source = copy.deepcopy(document)
    malformed_source["source"]["path"] = ["docs/PerfBudget.md"]
    cases.append(("malformed-budget-source", malformed_source, "source metadata drift"))

    malformed_devices = copy.deepcopy(document)
    malformed_devices["requiredDeviceClasses"] = ["compact", {"device": "ipad"}]
    cases.append(("malformed-device-classes", malformed_devices, "required device classes drift"))

    schema_drift = copy.deepcopy(document)
    schema_drift["schemaVersion"] = 999
    cases.append(("budget-schema-drift", schema_drift, "schemaVersion must remain 1"))

    status_drift = copy.deepcopy(document)
    status_drift["status"] = "runtime-authored"
    cases.append((
        "budget-status-drift",
        status_drift,
        "status must remain predeclared-before-implementation",
    ))

    results: list[dict[str, object]] = []
    for case_id, mutated, expected in cases:
        issues = performance_budget_issues(mutated)
        matched = any(expected in issue for issue in issues)
        results.append({"case": case_id, "expected": expected, "matched": matched, "issues": issues})
        if not matched:
            fail(f"performance-budget self-test {case_id} did not fail with {expected!r}")
    return results


def validate_performance_budgets(packages: dict[str, dict]) -> list[dict[str, object]]:
    path = ROOT / "program/performance-budgets.json"
    document = JSON.get(path, {})
    budget_issues = performance_budget_issues(document)
    for issue in budget_issues:
        fail(issue)
    if budget_issues or not isinstance(document, dict):
        return []
    source = document.get("source")
    if isinstance(source, dict) and isinstance(source.get("path"), str):
        source_path = ROOT.parent / source["path"]
        if not source_path.is_file():
            fail("performance budget source path is missing")
        else:
            digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
            if digest != source.get("sha256AtPlanningBase"):
                fail("performance budget source hash drift")
    budgets = document.get("budgets", [])
    budgets_by_id = {
        str(budget.get("id")): budget
        for budget in budgets
        if isinstance(budgets, list)
        and isinstance(budget, dict)
        and isinstance(budget.get("id"), str)
    }
    validate_performance_consumer_contracts(packages, budgets_by_id)
    return [
        *validate_performance_budget_self_tests(document),
        *validate_performance_command_self_tests(packages),
    ]


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
    if native.get("estimate", {}).get("plannedFiles") != 20 or native.get("estimate", {}).get("maxFiles") != 20:
        fail("WP-NATIVE-01 parked candidate must bind exactly 20 files inside the unchanged 20-file cap")
    if native.get("estimate", {}).get("primaryRoots") != 3 or native.get("estimate", {}).get("maxPrimaryRoots") != 3:
        fail("WP-NATIVE-01 must remain inside the unchanged three-root cap")

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
    native_validate = (native_root / "VALIDATE.md").read_text(encoding="utf-8")
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
        "ExtensionPresentationResultInput", "DEBUG/test-only",
        "testExtensionPresentationResultInputSeparatesFixtureAndLegacyProduction",
        "--output results/native/ui-test-membership.json",
        "production durability/success/dismiss/open claim",
        "--package-diff WP-NATIVE-01",
        "reader-toolbar.depth-option", "reader-toolbar.tone-option",
    ):
        if marker not in native_contract:
            fail(f"WP-NATIVE-01 presentation/inventory boundary omits {marker}")
    for marker in (
        "ExtensionPresentationResultInput", "fresh reopen/decode",
        "testShareAndActionSuccessFollowsDurableCommit",
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

    for issue in native_extension_host_issues(
        packages, native_contract, native_validate, reader_contract,
    ):
        fail(issue)
    for issue in native_runtime_evidence_issues(
        packages, native_contract, native_validate,
    ):
        fail(issue)

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
    for marker in (
        "run_paired_performance.py", "--main-worktree", "--candidate-worktree",
        "--main-sha", "--candidate-sha", "--samples 30", "--instruments-template Hangs",
        "--instruments-template SwiftUI", "--operating-system", "--toolchain-id",
        "--budget-manifest upgrade/program/performance-budgets.json",
        "--budget-id PERF-GRAPH-INTERACTION", ".xcresult",
    ):
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


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-diff", metavar="PACKAGE_ID")
    parser.add_argument("--base", metavar="FULL_SHA")
    parser.add_argument("--head", metavar="FULL_SHA")
    parser.add_argument("--require-candidate-binding", action="store_true")
    parser.add_argument("--require-correction-envelope", action="store_true")
    parser.add_argument("--show-root-accounting-negative-tests", action="store_true")
    parser.add_argument("--show-remediation-negative-tests", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    require_files()
    validate_text_integrity()
    for path in sorted(ROOT.rglob("*.json")):
        if path not in JSON:
            load_json(path)
    backlog = JSON.get(ROOT / "program/backlog.json", {})
    dag = JSON.get(ROOT / "program/dependency-dag.json", {})
    locks_doc = JSON.get(ROOT / "program/resource-locks.json", {})
    root_accounting_results: list[dict[str, object]] = []
    performance_budget_results: list[dict[str, object]] = []
    container_shape_results: list[dict[str, object]] = []
    native_extension_host_results: list[dict[str, object]] = []
    if not all(isinstance(value, dict) for value in (backlog, dag, locks_doc)):
        fail("program JSON documents must be objects")
    else:
        for issue in backlog_container_issues(backlog):
            fail(issue)
        if not isinstance(backlog.get("counts"), dict):
            backlog["counts"] = {}
        packages = validate_packages(backlog, locks_doc)
        if not ERRORS:
            root_accounting_results = validate_root_accounting_self_tests(packages)
            container_shape_results = validate_container_shape_self_tests(packages, backlog)
            native_extension_host_results = validate_native_extension_host_self_tests(packages)
        validate_graph(backlog, dag, locks_doc, packages)
        validate_evaluations(backlog)
        performance_budget_results = validate_performance_budgets(packages)
        validate_final_remediation_contracts(packages, locks_doc)
        if arguments.package_diff is not None:
            package = packages.get(arguments.package_diff)
            if package is None:
                fail(f"unknown --package-diff package: {arguments.package_diff}")
            elif arguments.base is None or arguments.head is None:
                fail("--package-diff requires --base and --head")
            else:
                validate_candidate_diff(
                    package,
                    arguments.base,
                    arguments.head,
                    arguments.require_candidate_binding,
                    arguments.require_correction_envelope,
                )
        elif arguments.base is not None or arguments.head is not None:
            fail("--base/--head require --package-diff")
        elif arguments.require_candidate_binding or arguments.require_correction_envelope:
            fail("candidate binding/envelope flags require --package-diff")
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
    if arguments.package_diff is not None:
        disposition = (
            "bound" if arguments.require_candidate_binding
            else "correction-envelope" if arguments.require_correction_envelope
            else "accounted"
        )
        print(
            f"PASS: {arguments.package_diff} candidate diff {disposition} "
            f"({arguments.base}..{arguments.head})"
        )
    if arguments.show_root_accounting_negative_tests:
        print(json.dumps(root_accounting_results, indent=2, sort_keys=True))
    if arguments.show_remediation_negative_tests:
        print(json.dumps({
            "containerShapes": container_shape_results,
            "performanceBudgets": performance_budget_results,
            "rootAccounting": root_accounting_results,
            "extensionEvidenceHost": native_extension_host_results,
        }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
