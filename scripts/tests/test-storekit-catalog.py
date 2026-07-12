#!/usr/bin/env python3
"""Verify the approved fixture and its isolated StoreKit automation wiring.

The dedicated test plan activates the catalog, then a retained
``SKTestSession`` binds it after a bounded install launch and before the tested
relaunch. CI requires the exact Xcode 26.6 and iOS 26.6 simulator pairing because
the tested older hosted runtime acknowledges the save without persisting
``Configuration.storekit``. A provenance-bound, expiring waiver may acknowledge
the exact affected hosted image only after a separately reviewed App Store
Connect sandbox evidence packet is certified on the recovery pull request.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.parse import urlparse
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
APPROVED_PATH = ROOT / "Config" / "ApprovedReleaseIdentity.json"
STOREKIT_PATH = ROOT / "Config" / "ChapterFlow.storekit"
WAIVER_PATH = ROOT / "Config" / "StoreKitSimulatorWaiver.json"
ATTESTATION_DIRECTORY = (
    ROOT / "docs" / "ios" / "release-evidence" / "storekit" / "pr-117"
)
ATTESTATION_PATH = ATTESTATION_DIRECTORY / "attestation.v1.json"
EVIDENCE_FILENAMES = (
    "catalog.png",
    "backend-unavailable.png",
    "sandbox-purchase-history.png",
    "restore-success.png",
    "relaunch-pro.png",
)
ATTESTATION_RELATIVE_PATH = (
    "docs/ios/release-evidence/storekit/pr-117/attestation.v1.json"
)
EVIDENCE_RELATIVE_PATHS = (
    ATTESTATION_RELATIVE_PATH,
    *(f"docs/ios/release-evidence/storekit/pr-117/{name}" for name in EVIDENCE_FILENAMES),
)
NORMAL_TEST_PLAN_PATH = ROOT / "ChapterFlow.xctestplan"
STOREKIT_TEST_PLAN_PATH = ROOT / "ChapterFlow-StoreKitTest.xctestplan"
OLD_APP_STOREKIT_PATH = ROOT / "ChapterFlow" / "Config" / "ChapterFlow.storekit"
PROJECT_PATH = ROOT / "ChapterFlow.xcodeproj" / "project.pbxproj"
PR_WORKFLOW_PATH = ROOT / ".github" / "workflows" / "pr.yml"
STUB_ROUTES_PATH = ROOT / "ChapterFlow" / "TestSupport" / "CFStubRoutes.swift"
UITEST_ENVIRONMENT_PATH = ROOT / "ChapterFlowUITests" / "ChapterFlowUITests.swift"
PURCHASE_FLOW_PATH = ROOT / "ChapterFlowUITests" / "Flows" / "PurchaseFlowTests.swift"
UITEST_ENTITLEMENTS_PATH = ROOT / "ChapterFlowUITests" / "ChapterFlowUITests.entitlements"
NORMAL_SCHEME_PATH = (
    ROOT / "ChapterFlow.xcodeproj" / "xcshareddata" / "xcschemes" / "ChapterFlow.xcscheme"
)
TEST_SCHEME_PATH = (
    ROOT
    / "ChapterFlow.xcodeproj"
    / "xcshareddata"
    / "xcschemes"
    / "ChapterFlow-StoreKitTest.xcscheme"
)
EXPECTED_SCHEME_REFERENCE = "../../Config/ChapterFlow.storekit"
EXPECTED_WAIVER = {
    "schemaVersion": 1,
    "id": "CF-SKTESTSESSION-2026-07",
    "status": "active",
    "owner": "WillSoltani",
    "approvedBy": "WillSoltani",
    "approvedAt": "2026-07-12T00:00:00Z",
    "expiresAt": "2026-07-27T23:59:59Z",
    "reasonCode": "APPLE_SKTESTSESSION_CONFIGURATION_CODE_3",
    "scope": {
        "workflow": ".github/workflows/pr.yml",
        "job": "storekit",
        "runner": "macos-26",
        "githubHostedOnly": True,
        "recoveryOriginPullRequest": 117,
        "recoveryOriginHeadRef": "codex/wp-rel-01",
        "verifiedBaseSha": "03747305819eccc8bb3c738a21e79d78a82d587d",
        "inheritableWithEvidence": True,
        "firstMainIntroductionMergeStrategy": "merge-commit-only",
        "baselineEvidenceImmutable": True,
        "inheritedChangeScope": "documentation-non-runtime-only",
        "xcodePath": "/Applications/Xcode_26.6.app/Contents/Developer",
        "xcodeVersion": "26.6",
        "xcodeBuild": "17F113",
        "minimumFixedRuntimeVersion": "26.6",
        "knownAffectedRuntimeIdentifier": (
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        ),
        "testIdentifier": (
            "ChapterFlowUITests/PurchaseFlowTests/"
            "testStoreKitCatalogPurchaseRelaunchAndRestoreCompletes"
        ),
    },
    "attestation": {
        "originPullRequestLabel": "storekit-sandbox-attested",
        "packetPath": (
            "docs/ios/release-evidence/storekit/pr-117/attestation.v1.json"
        ),
        "evidencePaths": [
            f"docs/ios/release-evidence/storekit/pr-117/{filename}"
            for filename in EVIDENCE_FILENAMES
        ],
        "requiredEvidence": (
            "A signed App Store Connect sandbox purchase and restore was captured "
            "by the operator and reviewed by an independent reviewer."
        ),
        "independentReviewerRequired": True,
    },
    "upstreamReferences": [
        {
            "kind": "apple-forum",
            "value": "https://developer.apple.com/forums/thread/830493",
        },
        {
            "kind": "external-feedback-report",
            "value": "FB22836426",
            "ownership": "reported-by-third-party",
        },
    ],
    "evidence": [
        "https://github.com/WillSoltani/Chapterflow-IOS/actions/runs/29208587346",
        "https://github.com/WillSoltani/Chapterflow-IOS/actions/runs/29209801667",
        "https://github.com/WillSoltani/Chapterflow-IOS/actions/runs/29210743005",
        (
            "https://github.com/WillSoltani/Chapterflow-IOS/pull/117"
            "#issuecomment-4953047208"
        ),
    ],
    "replacementEvidence": {
        "verifiedSha": "8b69f4f7eb860dc4da72a10510ca61f88d5fb6a1",
        "verifiedRun": (
            "https://github.com/WillSoltani/Chapterflow-IOS/actions/runs/29201120404"
        ),
        "requiredStaticChecker": "scripts/tests/test-storekit-catalog.py",
    },
    "releaseImpact": (
        "The simulator waiver is source-merge-only and does not satisfy the "
        "remaining release stop conditions."
    ),
}


def fail(code: str) -> None:
    raise SystemExit(code)


def load_json(path: Path) -> dict[str, object]:
    try:
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError):
        fail(f"E_STOREKIT_CATALOG_UNREADABLE:{path.name}")
    if not isinstance(value, dict):
        fail(f"E_STOREKIT_CATALOG_ROOT:{path.name}")
    return value


def parse_scheme(path: Path) -> ET.Element:
    try:
        return ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        fail(f"E_STOREKIT_SCHEME_UNREADABLE:{path.name}")


def command_output(command: list[str], error_code: str) -> str:
    try:
        completed = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        fail(error_code)
    return completed.stdout.strip()


def require_keys(value: object, expected: set[str], error_code: str) -> dict[str, object]:
    if not isinstance(value, dict) or set(value) != expected:
        fail(error_code)
    return value


def parse_utc_timestamp(value: object, error_code: str) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        fail(error_code)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        fail(error_code)
    if parsed.tzinfo is None:
        fail(error_code)
    return parsed.astimezone(timezone.utc)


def validate_url(value: object, expected: str, error_code: str) -> None:
    if value != expected:
        fail(error_code)
    parsed = urlparse(str(value))
    if (
        parsed.scheme != "https"
        or not parsed.netloc
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        fail(error_code)


def load_attestation() -> dict[str, object]:
    if not ATTESTATION_PATH.is_file():
        fail("E_STOREKIT_ATTESTATION_MISSING")
    expected_files = {"attestation.v1.json", *EVIDENCE_FILENAMES}
    try:
        actual_files = {
            path.name
            for path in ATTESTATION_DIRECTORY.iterdir()
            if path.is_file()
        }
    except OSError:
        fail("E_STOREKIT_ATTESTATION_UNREADABLE")
    if actual_files != expected_files:
        fail("E_STOREKIT_ATTESTATION_FILE_SET")
    try:
        with ATTESTATION_PATH.open(encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError):
        fail("E_STOREKIT_ATTESTATION_UNREADABLE")
    return require_keys(
        value,
        {
            "schemaVersion",
            "attestationId",
            "identity",
            "source",
            "urls",
            "backend",
            "build",
            "device",
            "actors",
            "window",
            "products",
            "outcomes",
            "evidence",
            "releaseAuthorization",
        },
        "E_STOREKIT_ATTESTATION_SCHEMA",
    )


def runtime_version(identifier: object) -> tuple[int, int] | None:
    if not isinstance(identifier, str):
        return None
    match = re.fullmatch(
        r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)-(\d+)",
        identifier,
    )
    if match is None:
        return None
    return tuple(int(value) for value in match.groups())


def storekit_critical_path(path: str) -> bool:
    critical_prefixes = (
        ".github/workflows/",
        "Config/",
        "ChapterFlow/",
        "ChapterFlow.xcodeproj/",
        "ChapterFlowUITests/",
        "docs/ios/release-evidence/storekit/pr-117/",
        "Packages/",
        "scripts/",
    )
    root_critical = (
        "/" not in path
        and (
            path.endswith(".xctestplan")
            or path.endswith(".xcconfig")
            or path in {
                ".swiftlint.yml",
                "Package.swift",
                "Package.resolved",
                "Secrets.example.xcconfig",
            }
        )
    )
    return root_critical or path.startswith(critical_prefixes)


def git_object_exists(specification: str) -> bool:
    try:
        subprocess.run(
            ["git", "cat-file", "-e", specification],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return False
    return True


def require_ancestor(ancestor: str, descendant: str, error_code: str) -> None:
    try:
        subprocess.run(
            ["git", "merge-base", "--is-ancestor", ancestor, descendant],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        fail(error_code)


def changed_paths_between(ancestor: str, descendant: str) -> set[str]:
    output = command_output(
        ["git", "diff", "--name-only", "--no-renames", ancestor, descendant],
        "E_STOREKIT_ATTESTATION_DIFF",
    )
    return set(output.splitlines())


def require_evidence_in_commit(commit_sha: str, error_code: str) -> None:
    if any(
        not git_object_exists(f"{commit_sha}:{path}")
        for path in EVIDENCE_RELATIVE_PATHS
    ):
        fail(error_code)


def require_evidence_identical(left_sha: str, right_sha: str, error_code: str) -> None:
    try:
        subprocess.run(
            [
                "git",
                "diff",
                "--quiet",
                left_sha,
                right_sha,
                "--",
                *EVIDENCE_RELATIVE_PATHS,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        fail(error_code)


def require_no_critical_drift(
    tested_source_sha: str,
    target_sha: str,
    require_evidence_additions: bool,
) -> None:
    changed_paths = changed_paths_between(tested_source_sha, target_sha)
    evidence_paths = set(EVIDENCE_RELATIVE_PATHS)
    if require_evidence_additions and not evidence_paths.issubset(changed_paths):
        fail("E_STOREKIT_ATTESTATION_EVIDENCE_NOT_BOUND")
    disallowed_changes = sorted(
        path
        for path in changed_paths - evidence_paths
        if storekit_critical_path(path)
    )
    if disallowed_changes:
        fail(f"E_STOREKIT_ATTESTATION_CRITICAL_DRIFT:{disallowed_changes[0]}")


def validate_attestation_packet(
    current_sha: str,
    baseline_sha: str,
    origin_run: bool,
    event_name: str,
    require_fresh_evidence: bool,
) -> None:
    packet = load_attestation()
    if packet["schemaVersion"] != 1 or packet["attestationId"] != "CF-STOREKIT-PR117-V1":
        fail("E_STOREKIT_ATTESTATION_IDENTITY")
    if packet["releaseAuthorization"] is not False:
        fail("E_STOREKIT_ATTESTATION_RELEASE_AUTHORIZATION")

    identity = require_keys(
        packet["identity"],
        {"appAppleID", "bundleIdentifier", "appleTeamID", "subscriptionGroupID"},
        "E_STOREKIT_ATTESTATION_IDENTITY",
    )
    expected_identity = {
        "appAppleID": "6787864558",
        "bundleIdentifier": "com.chapterflow.ios",
        "appleTeamID": "ZG3C9QBA8Z",
        "subscriptionGroupID": "22211821",
    }
    if identity != expected_identity:
        fail("E_STOREKIT_ATTESTATION_IDENTITY")

    source = require_keys(
        packet["source"],
        {"testedSourceSha"},
        "E_STOREKIT_ATTESTATION_SOURCE",
    )
    tested_source_sha = source["testedSourceSha"]
    sha_pattern = re.compile(r"[0-9a-f]{40}")
    if (
        not isinstance(tested_source_sha, str)
        or sha_pattern.fullmatch(tested_source_sha) is None
        or sha_pattern.fullmatch(current_sha) is None
    ):
        fail("E_STOREKIT_ATTESTATION_SOURCE")

    urls = require_keys(
        packet["urls"],
        {"pullRequest", "appStoreConnect"},
        "E_STOREKIT_ATTESTATION_URLS",
    )
    validate_url(
        urls["pullRequest"],
        "https://github.com/WillSoltani/Chapterflow-IOS/pull/117",
        "E_STOREKIT_ATTESTATION_URLS",
    )
    validate_url(
        urls["appStoreConnect"],
        "https://appstoreconnect.apple.com/apps/6787864558/distribution/subscription-groups/22211821",
        "E_STOREKIT_ATTESTATION_URLS",
    )

    backend = require_keys(
        packet["backend"],
        {"environment", "baseURL", "deployedSha", "deploymentRunURL", "healthReportedSha"},
        "E_STOREKIT_ATTESTATION_BACKEND",
    )
    deployed_sha = backend["deployedSha"]
    health_sha = backend["healthReportedSha"]
    if (
        backend["environment"] not in {"staging", "production"}
        or not isinstance(deployed_sha, str)
        or sha_pattern.fullmatch(deployed_sha) is None
        or deployed_sha != health_sha
    ):
        fail("E_STOREKIT_ATTESTATION_BACKEND")
    for key in ("baseURL", "deploymentRunURL"):
        value = backend[key]
        if not isinstance(value, str):
            fail("E_STOREKIT_ATTESTATION_BACKEND")
        parsed = urlparse(value)
        if (
            parsed.scheme != "https"
            or not parsed.netloc
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.fragment
        ):
            fail("E_STOREKIT_ATTESTATION_BACKEND")
    if re.fullmatch(
        r"https://github\.com/WillSoltani/ChapterFlow/actions/runs/[1-9][0-9]*",
        str(backend["deploymentRunURL"]),
    ) is None:
        fail("E_STOREKIT_ATTESTATION_BACKEND")

    build = require_keys(
        packet["build"],
        {
            "distribution",
            "version",
            "build",
            "bundleIdentifier",
            "appAppleID",
            "teamID",
            "artifactSha256",
        },
        "E_STOREKIT_ATTESTATION_BUILD",
    )
    if (
        build["distribution"] not in {"development-signed-sandbox", "testflight"}
        or not isinstance(build["version"], str)
        or re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", build["version"]) is None
        or not isinstance(build["build"], str)
        or re.fullmatch(r"[1-9][0-9]*", build["build"]) is None
        or build["bundleIdentifier"] != "com.chapterflow.ios"
        or build["appAppleID"] != "6787864558"
        or build["teamID"] != "ZG3C9QBA8Z"
        or not isinstance(build["artifactSha256"], str)
        or re.fullmatch(r"[0-9a-f]{64}", build["artifactSha256"]) is None
    ):
        fail("E_STOREKIT_ATTESTATION_BUILD")
    expected_backend_environment = (
        "staging"
        if build["distribution"] == "development-signed-sandbox"
        else "production"
    )
    if backend["environment"] != expected_backend_environment:
        fail("E_STOREKIT_ATTESTATION_BACKEND_DISTRIBUTION")

    device = require_keys(
        packet["device"],
        {"model", "osVersion", "locale", "region", "storefront"},
        "E_STOREKIT_ATTESTATION_DEVICE",
    )
    if (
        not isinstance(device["model"], str)
        or not device["model"].strip()
        or not isinstance(device["osVersion"], str)
        or re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", device["osVersion"]) is None
        or not isinstance(device["locale"], str)
        or re.fullmatch(r"[a-z]{2}[-_][A-Z]{2}", device["locale"]) is None
        or not isinstance(device["region"], str)
        or re.fullmatch(r"[A-Z]{2}", device["region"]) is None
        or not isinstance(device["storefront"], str)
        or re.fullmatch(r"[A-Z]{3}", device["storefront"]) is None
    ):
        fail("E_STOREKIT_ATTESTATION_DEVICE")

    actors = require_keys(
        packet["actors"],
        {"operator", "reviewer"},
        "E_STOREKIT_ATTESTATION_ACTORS",
    )
    operator = actors["operator"]
    reviewer = actors["reviewer"]
    if (
        not isinstance(operator, str)
        or not operator.strip()
        or not isinstance(reviewer, str)
        or not reviewer.strip()
        or operator.strip().casefold() == reviewer.strip().casefold()
    ):
        fail("E_STOREKIT_ATTESTATION_ACTORS")

    window = require_keys(
        packet["window"],
        {"testedAt", "expiresAt"},
        "E_STOREKIT_ATTESTATION_WINDOW",
    )
    tested_at = parse_utc_timestamp(window["testedAt"], "E_STOREKIT_ATTESTATION_WINDOW")
    packet_expiry = parse_utc_timestamp(window["expiresAt"], "E_STOREKIT_ATTESTATION_WINDOW")
    waiver_expiry = parse_utc_timestamp(EXPECTED_WAIVER["expiresAt"], "E_STOREKIT_WAIVER_EXPIRY")
    now = datetime.now(timezone.utc)
    if (
        tested_at > now
        or packet_expiry <= tested_at
        or packet_expiry - tested_at > timedelta(days=7)
        or (
            require_fresh_evidence
            and (now >= packet_expiry or now >= waiver_expiry)
        )
    ):
        fail("E_STOREKIT_ATTESTATION_WINDOW")

    products = require_keys(
        packet["products"],
        {"configuredProductIDs", "loadedProductIDs", "monthly"},
        "E_STOREKIT_ATTESTATION_PRODUCTS",
    )
    expected_products = {"com.chapterflow.pro.monthly", "com.chapterflow.pro.annual"}
    for key in ("configuredProductIDs", "loadedProductIDs"):
        product_ids = products[key]
        if (
            not isinstance(product_ids, list)
            or len(product_ids) != 2
            or any(not isinstance(product_id, str) for product_id in product_ids)
            or set(product_ids) != expected_products
        ):
            fail("E_STOREKIT_ATTESTATION_PRODUCTS")
    monthly = require_keys(
        products["monthly"],
        {"productID", "displayPrice", "subscriptionPeriod"},
        "E_STOREKIT_ATTESTATION_PRODUCTS",
    )
    if monthly != {
        "productID": "com.chapterflow.pro.monthly",
        "displayPrice": "$7.99",
        "subscriptionPeriod": "P1M",
    }:
        fail("E_STOREKIT_ATTESTATION_PRODUCTS")

    outcomes = require_keys(
        packet["outcomes"],
        {
            "sequence",
            "appleSandboxPurchase",
            "backendFailure",
            "restore",
            "successUI",
            "relaunchEntitlement",
        },
        "E_STOREKIT_ATTESTATION_OUTCOMES",
    )
    expected_sequence = [
        "apple-sandbox-purchase-completed",
        "backend-verification-unavailable-fail-closed",
        "explicit-restore-authoritative-ack",
        "success-ui-displayed",
        "relaunch-pro",
    ]
    if (
        outcomes["sequence"] != expected_sequence
        or outcomes["appleSandboxPurchase"] != "completed"
        or outcomes["successUI"] != "displayed"
    ):
        fail("E_STOREKIT_ATTESTATION_OUTCOMES")
    backend_failure = require_keys(
        outcomes["backendFailure"],
        {"verification", "proGranted", "transactionFinished"},
        "E_STOREKIT_ATTESTATION_OUTCOMES",
    )
    if backend_failure != {
        "verification": "unavailable",
        "proGranted": False,
        "transactionFinished": False,
    }:
        fail("E_STOREKIT_ATTESTATION_OUTCOMES")
    restore = require_keys(
        outcomes["restore"],
        {"kind", "acknowledgement", "transactionFinishedAfterAcknowledgement"},
        "E_STOREKIT_ATTESTATION_OUTCOMES",
    )
    acknowledgement = require_keys(
        restore["acknowledgement"],
        {"ok", "processed", "transactionState"},
        "E_STOREKIT_ATTESTATION_OUTCOMES",
    )
    if (
        restore["kind"] != "explicit"
        or restore["transactionFinishedAfterAcknowledgement"] is not True
        or acknowledgement != {"ok": True, "processed": True, "transactionState": "active"}
    ):
        fail("E_STOREKIT_ATTESTATION_OUTCOMES")
    relaunch = require_keys(
        outcomes["relaunchEntitlement"],
        {"plan", "proStatus", "proSource"},
        "E_STOREKIT_ATTESTATION_OUTCOMES",
    )
    if relaunch != {"plan": "PRO", "proStatus": "active", "proSource": "apple"}:
        fail("E_STOREKIT_ATTESTATION_OUTCOMES")

    evidence = require_keys(
        packet["evidence"],
        set(EVIDENCE_FILENAMES),
        "E_STOREKIT_ATTESTATION_EVIDENCE",
    )
    for filename in EVIDENCE_FILENAMES:
        evidence_entry = require_keys(
            evidence[filename],
            {"sha256", "redacted"},
            "E_STOREKIT_ATTESTATION_EVIDENCE",
        )
        expected_hash = evidence_entry["sha256"]
        if (
            evidence_entry["redacted"] is not True
            or not isinstance(expected_hash, str)
            or re.fullmatch(r"[0-9a-f]{64}", expected_hash) is None
        ):
            fail("E_STOREKIT_ATTESTATION_EVIDENCE")
        evidence_path = ATTESTATION_DIRECTORY / filename
        try:
            data = evidence_path.read_bytes()
        except OSError:
            fail("E_STOREKIT_ATTESTATION_EVIDENCE_MISSING")
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            fail("E_STOREKIT_ATTESTATION_EVIDENCE_FORMAT")
        if hashlib.sha256(data).hexdigest() != expected_hash:
            fail("E_STOREKIT_ATTESTATION_EVIDENCE_HASH")

    if not git_object_exists(f"{tested_source_sha}^{{commit}}"):
        fail("E_STOREKIT_ATTESTATION_SOURCE_MISSING")
    if sha_pattern.fullmatch(baseline_sha) is None or not git_object_exists(
        f"{baseline_sha}^{{commit}}"
    ):
        fail("E_STOREKIT_ATTESTATION_BASELINE")
    checked_out_sha = command_output(
        ["git", "rev-parse", "HEAD"],
        "E_STOREKIT_ATTESTATION_CURRENT_SOURCE",
    )
    if checked_out_sha != current_sha:
        fail("E_STOREKIT_ATTESTATION_CURRENT_SOURCE")
    require_ancestor(
        tested_source_sha,
        current_sha,
        "E_STOREKIT_ATTESTATION_NOT_ANCESTOR",
    )

    baseline_presence = [
        git_object_exists(f"{baseline_sha}:{path}")
        for path in EVIDENCE_RELATIVE_PATHS
    ]
    if any(baseline_presence) and not all(baseline_presence):
        fail("E_STOREKIT_ATTESTATION_BASELINE_PARTIAL")

    if all(baseline_presence):
        require_evidence_identical(
            baseline_sha,
            current_sha,
            "E_STOREKIT_ATTESTATION_REPLACED",
        )
        require_no_critical_drift(
            tested_source_sha,
            current_sha,
            require_evidence_additions=True,
        )
        return

    if origin_run:
        if event_name != "pull_request":
            fail("E_STOREKIT_ATTESTATION_ORIGIN_EVENT")
        require_no_critical_drift(
            tested_source_sha,
            current_sha,
            require_evidence_additions=True,
        )
        return

    if event_name != "push":
        fail("E_STOREKIT_ATTESTATION_FIRST_INTRODUCTION_EVENT")
    parent_line = command_output(
        ["git", "rev-list", "--parents", "-n", "1", current_sha],
        "E_STOREKIT_ATTESTATION_MERGE_TOPOLOGY",
    ).split()
    if len(parent_line) != 3 or parent_line[1] != baseline_sha:
        fail("E_STOREKIT_ATTESTATION_MERGE_TOPOLOGY")
    second_parent = parent_line[2]
    require_evidence_in_commit(
        second_parent,
        "E_STOREKIT_ATTESTATION_SECOND_PARENT_EVIDENCE",
    )
    require_evidence_identical(
        second_parent,
        current_sha,
        "E_STOREKIT_ATTESTATION_MERGE_REPLACED",
    )
    require_ancestor(
        tested_source_sha,
        second_parent,
        "E_STOREKIT_ATTESTATION_SECOND_PARENT_SOURCE",
    )
    require_no_critical_drift(
        tested_source_sha,
        second_parent,
        require_evidence_additions=True,
    )
    require_no_critical_drift(
        tested_source_sha,
        current_sha,
        require_evidence_additions=True,
    )


def validate_waiver_environment(
    waiver: dict[str, object],
    require_platform_waiver: bool,
) -> None:
    expected_environment = {
        "GITHUB_ACTIONS": "true",
        "RUNNER_ENVIRONMENT": "github-hosted",
        "RUNNER_OS": "macOS",
        "ImageOS": "macos26",
        "DEVELOPER_DIR": "/Applications/Xcode_26.6.app/Contents/Developer",
    }
    if any(os.environ.get(key) != value for key, value in expected_environment.items()):
        fail("E_STOREKIT_WAIVER_ENVIRONMENT")
    baseline_sha = os.environ.get("BASELINE_SHA", "")
    current_sha = os.environ.get("CURRENT_SHA", "")
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    storekit_only = os.environ.get("STOREKIT_ONLY") == "true"
    platform_waived = os.environ.get("PLATFORM_WAIVED") == "true"
    selected_runtime = os.environ.get("SELECTED_RUNTIME_ID", "")
    if storekit_only and (
        event_name != "pull_request"
        or os.environ.get("STOREKIT_SANDBOX_ATTESTED") != "true"
        or os.environ.get("PR_NUMBER") != "117"
        or os.environ.get("PR_HEAD_REF") != "codex/wp-rel-01"
        or os.environ.get("PR_BASE_SHA") != "03747305819eccc8bb3c738a21e79d78a82d587d"
        or baseline_sha != os.environ.get("PR_BASE_SHA")
    ):
        fail("E_STOREKIT_WAIVER_ORIGIN")
    if not storekit_only and event_name not in {"pull_request", "push"}:
        fail("E_STOREKIT_WAIVER_EVENT")

    xcode_version = command_output(
        ["xcodebuild", "-version"],
        "E_STOREKIT_WAIVER_XCODE_UNREADABLE",
    )
    if xcode_version != "Xcode 26.6\nBuild version 17F113":
        fail("E_STOREKIT_WAIVER_XCODE_DRIFT")
    runtime_output = command_output(
        ["xcrun", "simctl", "list", "runtimes", "available", "-j"],
        "E_STOREKIT_WAIVER_RUNTIME_UNREADABLE",
    )
    try:
        runtimes = json.loads(runtime_output).get("runtimes", [])
    except (AttributeError, json.JSONDecodeError):
        fail("E_STOREKIT_WAIVER_RUNTIME_UNREADABLE")
    available_runtime_ids = {
        runtime.get("identifier")
        for runtime in runtimes
        if isinstance(runtime, dict) and runtime.get("isAvailable", True)
    }
    fixed_runtime_ids = {
        identifier
        for identifier in available_runtime_ids
        if runtime_version(identifier) is not None and runtime_version(identifier) >= (26, 6)
    }
    if require_platform_waiver and not platform_waived:
        fail("E_STOREKIT_WAIVER_DISPOSITION")
    if not require_platform_waiver and platform_waived:
        fail("E_STOREKIT_ATTESTATION_DISPOSITION")
    if platform_waived:
        if selected_runtime or fixed_runtime_ids:
            fail("E_STOREKIT_WAIVER_FIXED_RUNTIME_AVAILABLE")
        if "com.apple.CoreSimulator.SimRuntime.iOS-26-5" not in available_runtime_ids:
            fail("E_STOREKIT_WAIVER_AFFECTED_RUNTIME_MISSING")
    elif selected_runtime not in fixed_runtime_ids:
        fail("E_STOREKIT_WAIVER_RUNTIME_SELECTION")

    validate_attestation_packet(
        current_sha,
        baseline_sha,
        origin_run=storekit_only,
        event_name=event_name,
        require_fresh_evidence=require_platform_waiver or storekit_only,
    )


def main(
    validate_platform_waiver: bool,
    validate_sandbox_attestation: bool,
) -> None:
    approved = load_json(APPROVED_PATH)
    fixture = load_json(STOREKIT_PATH)
    waiver = load_json(WAIVER_PATH)
    normal_test_plan = load_json(NORMAL_TEST_PLAN_PATH)
    storekit_test_plan = load_json(STOREKIT_TEST_PLAN_PATH)
    if waiver != EXPECTED_WAIVER:
        fail("E_STOREKIT_WAIVER_METADATA")
    if OLD_APP_STOREKIT_PATH.exists():
        fail("E_STOREKIT_FIXTURE_INSIDE_APP_TARGET")

    normal_options = normal_test_plan.get("defaultOptions")
    if not isinstance(normal_options, dict) or any(
        key.startswith("storeKitConfiguration") for key in normal_options
    ):
        fail("E_STOREKIT_NORMAL_TEST_PLAN_REFERENCE")

    storekit_options = storekit_test_plan.get("defaultOptions")
    if (
        not isinstance(storekit_options, dict)
        or storekit_options.get("storeKitConfiguration")
        != "Config/ChapterFlow.storekit"
        or "storeKitConfigurationFileReference" in storekit_options
    ):
        fail("E_STOREKIT_TEST_PLAN_REFERENCE")
    storekit_targets = storekit_test_plan.get("testTargets")
    expected_selected_tests = [
        "PurchaseFlowTests/testStoreKitCatalogPurchaseRelaunchAndRestoreCompletes()"
    ]
    if (
        not isinstance(storekit_targets, list)
        or len(storekit_targets) != 1
        or not isinstance(storekit_targets[0], dict)
        or storekit_targets[0].get("selectedTests") != expected_selected_tests
    ):
        fail("E_STOREKIT_TEST_PLAN_SELECTION")

    fixture_settings = fixture.get("settings")
    if (
        not isinstance(fixture_settings, dict)
        or fixture_settings.get("_disableDialogs") is not True
    ):
        fail("E_STOREKIT_AUTOMATION_DIALOGS_ENABLED")

    if approved.get("schemaVersion") != 1:
        fail("E_STOREKIT_APPROVED_SCHEMA")
    expected_identity = {
        "appAppleID": "6787864558",
        "bundleIdentifier": "com.chapterflow.ios",
        "appleTeamID": "ZG3C9QBA8Z",
        "subscriptionGroupID": "22211821",
    }
    if any(approved.get(key) != value for key, value in expected_identity.items()):
        fail("E_APPROVED_RELEASE_IDENTITY_MISMATCH")

    approved_products_value = approved.get("products")
    if not isinstance(approved_products_value, list) or len(approved_products_value) != 2:
        fail("E_STOREKIT_APPROVED_PRODUCTS")

    approved_products: dict[str, dict[str, object]] = {}
    for product in approved_products_value:
        if not isinstance(product, dict) or not isinstance(product.get("role"), str):
            fail("E_STOREKIT_APPROVED_PRODUCT_SHAPE")
        approved_products[product["role"]] = product
    if set(approved_products) != {"monthly", "annual"}:
        fail("E_STOREKIT_APPROVED_PRODUCT_ROLES")

    groups = fixture.get("subscriptionGroups")
    if not isinstance(groups, list) or len(groups) != 1 or not isinstance(groups[0], dict):
        fail("E_STOREKIT_FIXTURE_GROUP_COUNT")
    group = groups[0]
    if group.get("id") != approved.get("subscriptionGroupID"):
        fail("E_STOREKIT_FIXTURE_GROUP_MISMATCH")

    subscriptions = group.get("subscriptions")
    if not isinstance(subscriptions, list) or len(subscriptions) != 2:
        fail("E_STOREKIT_FIXTURE_PRODUCT_COUNT")

    fixture_by_id: dict[str, dict[str, object]] = {}
    for subscription in subscriptions:
        if not isinstance(subscription, dict) or not isinstance(subscription.get("productID"), str):
            fail("E_STOREKIT_FIXTURE_PRODUCT_SHAPE")
        fixture_by_id[subscription["productID"]] = subscription

    expected_ids = {str(product["productID"]) for product in approved_products.values()}
    if set(fixture_by_id) != expected_ids:
        fail("E_STOREKIT_FIXTURE_PRODUCT_IDS_MISMATCH")

    for product in approved_products.values():
        fixture_product = fixture_by_id[str(product["productID"])]
        if fixture_product.get("recurringSubscriptionPeriod") != product.get("subscriptionPeriod"):
            fail("E_STOREKIT_FIXTURE_PERIOD_MISMATCH")
        if fixture_product.get("groupNumber") != product.get("subscriptionLevel"):
            fail("E_STOREKIT_FIXTURE_SUBSCRIPTION_LEVEL_MISMATCH")
        if fixture_product.get("displayPrice") != product.get("storeKitTestDisplayPrice"):
            fail("E_STOREKIT_FIXTURE_TEST_PRICE_MISMATCH")
        if fixture_product.get("familyShareable") is not False:
            fail("E_STOREKIT_FIXTURE_FAMILY_SHARING")
    if {product.get("groupNumber") for product in fixture_by_id.values()} != {1}:
        fail("E_STOREKIT_FIXTURE_SUBSCRIPTION_LEVELS_DIVERGE")

    normal_scheme = parse_scheme(NORMAL_SCHEME_PATH)
    if normal_scheme.findall(".//StoreKitConfigurationFileReference"):
        fail("E_STOREKIT_NORMAL_SCHEME_REFERENCES_FIXTURE")

    test_scheme = parse_scheme(TEST_SCHEME_PATH)
    test_plan_references = test_scheme.findall("./TestAction/TestPlans/TestPlanReference")
    if [reference.get("reference") for reference in test_plan_references] != [
        "container:ChapterFlow-StoreKitTest.xctestplan"
    ]:
        fail("E_STOREKIT_TEST_SCHEME_PLAN_REFERENCE")
    launch_references = test_scheme.findall(
        "./LaunchAction/StoreKitConfigurationFileReference"
    )
    launch_identifiers = [reference.get("identifier") for reference in launch_references]
    if launch_identifiers != [EXPECTED_SCHEME_REFERENCE]:
        fail("E_STOREKIT_TEST_SCHEME_LAUNCH_REFERENCE")

    test_references = test_scheme.findall(
        "./TestAction/StoreKitConfigurationFileReference"
    )
    if test_references:
        fail("E_STOREKIT_TEST_SCHEME_PSEUDO_REFERENCE")

    try:
        project = PROJECT_PATH.read_text(encoding="utf-8")
    except OSError:
        fail("E_STOREKIT_PROJECT_UNREADABLE")
    if "ChapterFlow.storekit in Resources" not in project:
        fail("E_STOREKIT_UI_TEST_RESOURCE_MISSING")
    app_resources = project.split(
        "15E7517B2FF4A90000FA8025 /* Resources */ = {",
        maxsplit=1,
    )[1].split("};", maxsplit=1)[0]
    if "ChapterFlow.storekit" in app_resources:
        fail("E_STOREKIT_APP_RESOURCE_MEMBERSHIP")
    if project.count(
        "CODE_SIGN_ENTITLEMENTS = ChapterFlowUITests/ChapterFlowUITests.entitlements;"
    ) != 2:
        fail("E_STOREKIT_UI_TEST_APP_GROUP_ENTITLEMENTS")

    try:
        with UITEST_ENTITLEMENTS_PATH.open("rb") as handle:
            uitest_entitlements = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException):
        fail("E_STOREKIT_UI_TEST_ENTITLEMENTS_UNREADABLE")
    if uitest_entitlements.get("com.apple.security.application-groups") != [
        "group.com.chapterflow"
    ]:
        fail("E_STOREKIT_UI_TEST_APP_GROUP_MISMATCH")

    try:
        workflow = PR_WORKFLOW_PATH.read_text(encoding="utf-8")
    except OSError:
        fail("E_STOREKIT_WORKFLOW_UNREADABLE")
    required_workflow_fragments = [
        "types: [opened, reopened, synchronize, labeled, unlabeled]",
        "/Applications/Xcode_26.6.app/Contents/Developer",
        'export DEVELOPER_DIR="$storekit_xcode"',
        "Build version 17F113",
        "runs-on: macos-26",
        "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
        "version >= (26, 6)",
        "A:Config/StoreKitSimulatorWaiver.json",
        "A:docs/ios/release-evidence/storekit/pr-117/attestation.v1.json",
        "A:docs/ios/release-evidence/storekit/pr-117/catalog.png",
        "A:docs/ios/release-evidence/storekit/pr-117/backend-unavailable.png",
        "A:docs/ios/release-evidence/storekit/pr-117/sandbox-purchase-history.png",
        "A:docs/ios/release-evidence/storekit/pr-117/restore-success.png",
        "A:docs/ios/release-evidence/storekit/pr-117/relaunch-pro.png",
        "storekit-sandbox-attested",
        "STOREKIT_SANDBOX_ATTESTED",
        "STOREKIT_ONLY: ${{ needs.scope.outputs.storekit_only }}",
        "BASELINE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}",
        "CURRENT_SHA: ${{ github.event.pull_request.head.sha || github.sha }}",
        "fetch-depth: 0",
        "python3 scripts/tests/test-storekit-catalog.py --validate-platform-waiver",
        "python3 scripts/tests/test-storekit-catalog.py --validate-sandbox-attestation",
        'echo "waived=true" >> "$GITHUB_OUTPUT"',
        "platform_waived: ${{ steps.storekit_platform.outputs.waived }}",
        "selected_runtime_id: ${{ steps.storekit_platform.outputs.runtime_id }}",
        "Controlled StoreKit simulator waiver",
        "2026-07-27T23:59:59Z",
        "name: Hermetic XCUITest Flows",
        "name: StoreKit Purchase Contract",
        "name: XCUITest Flows",
        "HERMETIC_RESULT",
        "STOREKIT_RESULT",
        "ci-storekit-only",
        "03747305819eccc8bb3c738a21e79d78a82d587d",
        "8b69f4f7eb860dc4da72a10510ca61f88d5fb6a1",
        'git diff --name-status --no-renames "$verified_sha" "$PR_HEAD_SHA"',
        "A:ChapterFlow-StoreKitTest.xctestplan",
        "-testPlan ChapterFlow-StoreKitTest",
        "-test-timeouts-enabled YES",
        "-maximum-test-execution-time-allowance 300",
        '-destination "platform=iOS Simulator,id=$storekit_sim_id"',
        "-only-testing:ChapterFlowUITests/PurchaseFlowTests/"
        "testStoreKitCatalogPurchaseRelaunchAndRestoreCompletes",
    ]
    if any(fragment not in workflow for fragment in required_workflow_fragments):
        fail("E_STOREKIT_WORKFLOW_RUNTIME_PIN")
    storekit_job_index = workflow.index("  storekit:\n")
    storekit_checkout_index = workflow.index(
        "- uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5",
        storekit_job_index,
    )
    full_history_index = workflow.index("fetch-depth: 0", storekit_checkout_index)
    current_ref_index = workflow.index(
        "ref: ${{ github.event.pull_request.head.sha || github.sha }}",
        full_history_index,
    )
    platform_resolver_index = workflow.index(
        "- name: Resolve StoreKit simulator platform", storekit_job_index
    )
    runtime_selection_index = workflow.index(
        'selected_runtime_id="$(xcrun simctl list runtimes available -j',
        platform_resolver_index,
    )
    waived_output_index = workflow.index(
        'echo "waived=true" >> "$GITHUB_OUTPUT"', runtime_selection_index
    )
    storekit_test_step_index = workflow.index(
        "- name: Run StoreKit Test purchase and restore contract",
        waived_output_index,
    )
    test_condition_index = workflow.index(
        "if: steps.storekit_platform.outputs.waived != 'true'",
        storekit_test_step_index,
    )
    simulator_create_index = workflow.index(
        'storekit_sim_id="$(xcrun simctl create', test_condition_index
    )
    storekit_test_index = workflow.index(
        "NSUnbufferedIO=YES xcodebuild test", simulator_create_index
    )
    disposition_step_index = workflow.index(
        "- name: Validate StoreKit evidence disposition", storekit_test_index
    )
    baseline_env_index = workflow.index(
        "BASELINE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}",
        disposition_step_index,
    )
    current_env_index = workflow.index(
        "CURRENT_SHA: ${{ github.event.pull_request.head.sha || github.sha }}",
        baseline_env_index,
    )
    attestation_guard_index = workflow.index(
        'if [[ "$STOREKIT_ONLY" == "true"', current_env_index
    )
    waiver_validation_index = workflow.index(
        "python3 scripts/tests/test-storekit-catalog.py --validate-platform-waiver",
        attestation_guard_index,
    )
    sandbox_validation_index = workflow.index(
        "python3 scripts/tests/test-storekit-catalog.py --validate-sandbox-attestation",
        waiver_validation_index,
    )
    if not (
        storekit_job_index
        < storekit_checkout_index
        < full_history_index
        < current_ref_index
        < platform_resolver_index
        < runtime_selection_index
        < waived_output_index
        < storekit_test_step_index
        < test_condition_index
        < simulator_create_index
        < storekit_test_index
        < disposition_step_index
        < baseline_env_index
        < current_env_index
        < attestation_guard_index
        < waiver_validation_index
        < sandbox_validation_index
    ):
        fail("E_STOREKIT_RUNTIME_GATE_ORDER")
    uitest_job_index = workflow.index("\n  uitest:\n", storekit_test_index)
    storekit_job_source = workflow[storekit_job_index:uitest_job_index]
    exact_test_filter = (
        "-only-testing:ChapterFlowUITests/PurchaseFlowTests/"
        "testStoreKitCatalogPurchaseRelaunchAndRestoreCompletes"
    )
    if (
        "continue-on-error" in storekit_job_source
        or storekit_job_source.count("NSUnbufferedIO=YES xcodebuild test") != 1
        or storekit_job_source.count(exact_test_filter) != 1
    ):
        fail("E_STOREKIT_WAIVER_WEAKENS_TEST")
    if workflow.count("if: ${{ always() }}") != 4:
        fail("E_STOREKIT_WORKFLOW_REQUIRED_CHECK_SCOPE")
    try:
        checker_source = Path(__file__).read_text(encoding="utf-8")
    except OSError:
        fail("E_STOREKIT_CHECKER_UNREADABLE")
    merge_inheritance_fragments = [
        'baseline_sha = os.environ.get("BASELINE_SHA", "")',
        '["git", "rev-list", "--parents", "-n", "1", current_sha]',
        "len(parent_line) != 3 or parent_line[1] != baseline_sha",
        "require_evidence_identical(",
        "E_STOREKIT_ATTESTATION_REPLACED",
        '".github/workflows/",',
        '"ChapterFlow/",',
        '"Packages/",',
        '"scripts/",',
    ]
    if any(fragment not in checker_source for fragment in merge_inheritance_fragments):
        fail("E_STOREKIT_ATTESTATION_INHERITANCE_WIRING")

    app_test_support = (ROOT / "ChapterFlow" / "TestSupport" / "CFAppLaunchSupport.swift")
    try:
        app_test_support_source = app_test_support.read_text(encoding="utf-8")
    except OSError:
        fail("E_STOREKIT_APP_TEST_SUPPORT_UNREADABLE")
    if "StoreKitTest" in app_test_support_source or "SKTestSession" in app_test_support_source:
        fail("E_STOREKIT_TEST_FRAMEWORK_IN_APP_PROCESS")

    try:
        stub_routes_source = STUB_ROUTES_PATH.read_text(encoding="utf-8")
        uitest_environment_source = UITEST_ENVIRONMENT_PATH.read_text(encoding="utf-8")
        purchase_flow_source = PURCHASE_FLOW_PATH.read_text(encoding="utf-8")
    except OSError:
        fail("E_STOREKIT_RESTORE_SEAM_UNREADABLE")

    required_session_fragments = [
        "import StoreKitTest",
        "private var storeKitSession: SKTestSession?",
        "override func prepareForAppLaunch() throws",
        "override func setUpWithError() throws",
        "try super.setUpWithError()",
        'ProcessInfo.processInfo.environment["XCODE_SCHEME_NAME"]',
        '== "ChapterFlow-StoreKitTest"',
        "app.terminate()",
        "app.wait(for: .notRunning, timeout: 10)",
        'SKTestSession(configurationFileNamed: "ChapterFlow")',
        "session.resetToDefaultState()",
        "session.disableDialogs = true",
        "session.clearTransactions()",
        "storeKitSession = session",
        "guard storeKitSession != nil else",
        "storeKitSession?.allTransactions().contains",
        '$0.productIdentifier == "com.chapterflow.pro.monthly"',
    ]
    if any(fragment not in purchase_flow_source for fragment in required_session_fragments):
        fail("E_STOREKIT_SESSION_SETUP")
    if "buyProduct(" in purchase_flow_source:
        fail("E_STOREKIT_RUNNER_PURCHASE_SUBSTITUTION")
    exact_test_index = purchase_flow_source.index(
        "func testStoreKitCatalogPurchaseRelaunchAndRestoreCompletes()"
    )
    exact_test_end = purchase_flow_source.index("\n    private func", exact_test_index)
    if "XCTSkip" in purchase_flow_source[exact_test_index:exact_test_end]:
        fail("E_STOREKIT_EXACT_TEST_SKIP")
    storekit_setup_index = purchase_flow_source.index("override func setUpWithError() throws")
    super_setup_index = purchase_flow_source.index(
        "try super.setUpWithError()", storekit_setup_index
    )
    terminate_index = purchase_flow_source.index("app.terminate()", super_setup_index)
    stopped_index = purchase_flow_source.index(
        "app.wait(for: .notRunning, timeout: 10)", terminate_index
    )
    session_index = purchase_flow_source.index(
        'SKTestSession(configurationFileNamed: "ChapterFlow")', stopped_index
    )
    teardown_index = purchase_flow_source.index(
        "override func tearDownWithError() throws", session_index
    )
    bound_launch_index = purchase_flow_source.index("app.launch()", session_index)
    if not (
        storekit_setup_index
        < super_setup_index
        < terminate_index
        < stopped_index
        < session_index
        < bound_launch_index
        < teardown_index
    ):
        fail("E_STOREKIT_INSTALL_ORDER")
    required_prelaunch_fragments = [
        "func prepareForAppLaunch() throws {}",
        "override func setUpWithError() throws",
        "app = XCUIApplication()",
        "try prepareForAppLaunch()",
        "app.launch()",
    ]
    if any(fragment not in uitest_environment_source for fragment in required_prelaunch_fragments):
        fail("E_STOREKIT_PRELAUNCH_HOOK")
    app_index = uitest_environment_source.index("app = XCUIApplication()")
    prepare_index = uitest_environment_source.index("try prepareForAppLaunch()")
    launch_index = uitest_environment_source.index("app.launch()", prepare_index)
    if not app_index < prepare_index < launch_index:
        fail("E_STOREKIT_PRELAUNCH_ORDER")

    restore_environment_key = "CF_UITEST_DEFER_APPLE_VERIFY_UNTIL_RESTORE"
    restore_signal_file = ".chapterflow-uitest-restore-began"
    if restore_environment_key not in stub_routes_source:
        fail("E_STOREKIT_RESTORE_SEAM_STUB_FLAG")
    if restore_environment_key not in uitest_environment_source:
        fail("E_STOREKIT_RESTORE_SEAM_TEST_FLAG")
    if restore_signal_file not in stub_routes_source or restore_signal_file not in purchase_flow_source:
        fail("E_STOREKIT_RESTORE_SEAM_SIGNAL_MISMATCH")
    if "appleVerificationAttempts" in stub_routes_source:
        fail("E_STOREKIT_RESTORE_SEAM_ATTEMPT_COUNT")
    required_stub_fragments = [
        "FileManager.default.fileExists(atPath:",
        "if defersUntilExplicitRestore && !explicitRestoreStarted",
        "return appleVerificationDeferred",
        "state.applePurchaseVerified = true",
    ]
    if any(fragment not in stub_routes_source for fragment in required_stub_fragments):
        fail("E_STOREKIT_RESTORE_SEAM_NOT_FAIL_CLOSED")
    required_flow_fragments = [
        "app.launchEnvironment[TestEnv.deferAppleVerificationUntilRestore] = \"1\"",
        "guard signalExplicitRestoreStarted() else",
        "try Data().write(to: signalURL, options: .atomic)",
    ]
    if any(fragment not in purchase_flow_source for fragment in required_flow_fragments):
        fail("E_STOREKIT_RESTORE_SEAM_FLOW_WIRING")
    signal_index = purchase_flow_source.index("guard signalExplicitRestoreStarted() else")
    restore_tap_index = purchase_flow_source.index("restoreButton.tap()", signal_index)
    if signal_index >= restore_tap_index:
        fail("E_STOREKIT_RESTORE_SEAM_SIGNAL_ORDER")

    if validate_platform_waiver:
        validate_waiver_environment(waiver, require_platform_waiver=True)
    if validate_sandbox_attestation:
        validate_waiver_environment(waiver, require_platform_waiver=False)

    print("OK")


if __name__ == "__main__":
    try:
        parser = argparse.ArgumentParser()
        parser.add_argument("--validate-platform-waiver", action="store_true")
        parser.add_argument("--validate-sandbox-attestation", action="store_true")
        arguments = parser.parse_args()
        if arguments.validate_platform_waiver and arguments.validate_sandbox_attestation:
            fail("E_STOREKIT_VALIDATION_MODE")
        main(
            arguments.validate_platform_waiver,
            arguments.validate_sandbox_attestation,
        )
    except KeyError:
        fail("E_STOREKIT_APPROVED_PRODUCT_FIELDS")
    except BrokenPipeError:
        sys.exit(1)
