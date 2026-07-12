#!/usr/bin/env python3
"""Verify the approved fixture and its isolated StoreKit automation wiring.

The dedicated scheme is the automation authority. CI pins this lane to the iOS
26.2 simulator because later simulator runtimes currently break StoreKitTest.
"""

from __future__ import annotations

import json
from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
APPROVED_PATH = ROOT / "Config" / "ApprovedReleaseIdentity.json"
STOREKIT_PATH = ROOT / "Config" / "ChapterFlow.storekit"
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


def main() -> None:
    approved = load_json(APPROVED_PATH)
    fixture = load_json(STOREKIT_PATH)

    if OLD_APP_STOREKIT_PATH.exists():
        fail("E_STOREKIT_FIXTURE_INSIDE_APP_TARGET")

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
    launch_references = test_scheme.findall(
        "./LaunchAction/StoreKitConfigurationFileReference"
    )
    launch_identifiers = [reference.get("identifier") for reference in launch_references]
    if launch_identifiers != [EXPECTED_SCHEME_REFERENCE]:
        fail("E_STOREKIT_TEST_SCHEME_LAUNCH_REFERENCE")

    test_references = test_scheme.findall(
        "./TestAction/StoreKitConfigurationFileReference"
    )
    test_identifiers = [reference.get("identifier") for reference in test_references]
    if test_identifiers != [EXPECTED_SCHEME_REFERENCE]:
        fail("E_STOREKIT_TEST_SCHEME_TEST_REFERENCE")

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
        "/Applications/Xcode_26.2.app/Contents/Developer",
        "export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer",
        "xcodebuild -downloadPlatform iOS -buildVersion 26.2",
        "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
        "StoreKit runtime unavailable",
        "Do not run this contract against live App Store Connect or weaken the exact test.",
        '-destination "platform=iOS Simulator,id=$storekit_sim_id"',
        "-only-testing:ChapterFlowUITests/PurchaseFlowTests/"
        "testStoreKitCatalogPurchaseRelaunchAndRestoreCompletes",
    ]
    if any(fragment not in workflow for fragment in required_workflow_fragments):
        fail("E_STOREKIT_WORKFLOW_RUNTIME_PIN")

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

    print("OK")


if __name__ == "__main__":
    try:
        main()
    except KeyError:
        fail("E_STOREKIT_APPROVED_PRODUCT_FIELDS")
    except BrokenPipeError:
        sys.exit(1)
