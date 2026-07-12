#!/usr/bin/env python3
"""Fail-closed, redacting ChapterFlow iOS release configuration tooling."""

from __future__ import annotations

import argparse
import base64
import binascii
import copy
import hashlib
import json
import os
import plistlib
import re
import sys
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlparse


SCHEMA_VERSION = 1
RELEASE_MANIFEST_SCHEMA_PATH = (
    Path(__file__).resolve().parents[2] / "Config" / "ReleaseManifest.schema.json"
)
APPROVED_RELEASE_IDENTITY_PATH = (
    Path(__file__).resolve().parents[2] / "Config" / "ApprovedReleaseIdentity.json"
)

SUPPORTED_SCHEMA_KEYS = {
    "$schema",
    "$id",
    "title",
    "type",
    "additionalProperties",
    "required",
    "properties",
    "const",
    "enum",
    "pattern",
    "format",
    "minItems",
    "uniqueItems",
    "items",
    "minLength",
}

REQUIRED_ENV_FIELDS = (
    "CHAPTERFLOW_ENVIRONMENT",
    "API_BASE_URL",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_CLIENT_ID",
    "COGNITO_DOMAIN",
    "PRODUCT_BUNDLE_IDENTIFIER",
    "APP_STORE_ID",
    "APP_STORE_URL",
    "SUPPORT_URL",
    "APPROVED_STOREKIT_PRODUCT_IDS",
    "SK_MONTHLY_PRODUCT_ID",
    "SK_ANNUAL_PRODUCT_ID",
    "SENTRY_POLICY",
    "BUILD_CONFIGURATION",
    "MARKETING_VERSION",
    "BUILD_NUMBER",
    "BUILD_COMMIT_SHA",
    "APPLE_TEAM_ID",
    "ASC_KEY_ID",
    "ASC_ISSUER_ID",
    "ASC_API_KEY_P8",
    "DISTRIBUTION_CERT_P12_BASE64",
    "DISTRIBUTION_CERT_PASSWORD",
    "BACKEND_DEPLOYMENT_COMMIT_SHA",
    "BACKEND_ATTESTATION_ID",
    "BACKEND_ATTESTATION_APPROVED",
    "BACKEND_APPLE_BUNDLE_ID",
    "BACKEND_APPLE_APP_ID",
    "BACKEND_VERIFICATION_PRODUCT_ALLOWLIST",
    "BACKEND_MOBILE_CONFIG_APP_STORE_URL",
    "BACKEND_APPLE_ENVIRONMENT",
    "BACKEND_SUBSCRIPTION_GROUP_ID",
    "BACKEND_PRODUCT_ALLOWLIST_ENFORCED",
    "BACKEND_APPLE_ENVIRONMENT_ENFORCED",
    "BACKEND_SUBSCRIPTION_GROUP_ENFORCED",
    "BACKEND_ACCOUNT_BINDING_ENFORCED",
)

OPTIONAL_ENV_FIELDS = (
    "SK_ANNUAL_UPFRONT_PRODUCT_ID",
    "SENTRY_DSN",
)

EXACT_PLACEHOLDER_VALUES = {
    "placeholder",
    "changeme",
    "change-me",
    "change_me",
    "replace-me",
    "replace_me",
    "unknown",
    "dummy",
    "local",
    "todo",
    "tbd",
}

PLACEHOLDER_FRAGMENTS = (
    "__required__",
    "__generated__",
    "placeholder",
    "changeme",
    "change-me",
    "change_me",
    "replace-me",
    "replace_me",
    "your-domain",
    "your_domain",
    "your_",
    "your-",
    "example.com",
    ".example.",
    "<",
    ">",
)

REGION_PATTERN = re.compile(r"^[a-z]{2}(?:-gov)?-[a-z]+-[1-9][0-9]*$")
POOL_PATTERN = re.compile(r"^[a-z0-9-]+_[A-Za-z0-9]+$")
CLIENT_PATTERN = re.compile(r"^[A-Za-z0-9]{20,128}$")
HOST_PATTERN = re.compile(
    r"^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$"
)
PRODUCT_PATTERN = re.compile(r"^[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)+$")
APP_STORE_ID_PATTERN = re.compile(r"^[1-9][0-9]{5,19}$")
VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+(?:\.[0-9]+)?$")
BUILD_PATTERN = re.compile(r"^[1-9][0-9]*$")
COMMIT_PATTERN = re.compile(r"^[0-9a-fA-F]{40}$")
TEAM_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
KEY_ID_PATTERN = re.compile(r"^[A-Z0-9]{8,32}$")
ISSUER_PATTERN = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
ATTESTATION_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{7,199}$")
SUBSCRIPTION_GROUP_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$")
DISALLOWED_PRODUCTION_HOST_SUFFIXES = (
    ".local",
    ".localhost",
    ".test",
    ".example",
    ".invalid",
)


def issue_name(field: str, suffix: str) -> str:
    return f"E_{field}_{suffix}"


def unique(issues: Iterable[str]) -> list[str]:
    return list(dict.fromkeys(issues))


def emit(issues: Iterable[str]) -> int:
    redacted = unique(issues)
    if redacted:
        for issue in redacted:
            print(issue)
        return 1
    print("OK")
    return 0


def environment_values() -> dict[str, str]:
    return {
        field: os.environ.get(field, "")
        for field in (*REQUIRED_ENV_FIELDS, *OPTIONAL_ENV_FIELDS)
    }


def load_approved_release_identity() -> dict[str, str] | None:
    try:
        with APPROVED_RELEASE_IDENTITY_PATH.open(encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(document, dict) or document.get("schemaVersion") != 1:
        return None

    scalar_fields = (
        "appAppleID",
        "bundleIdentifier",
        "appleTeamID",
        "subscriptionGroupID",
    )
    if any(
        not isinstance(document.get(field), str) or not document[field]
        for field in scalar_fields
    ):
        return None

    products = document.get("products")
    if not isinstance(products, list) or len(products) != 2:
        return None
    products_by_role: dict[str, str] = {}
    for product in products:
        if not isinstance(product, dict):
            return None
        role = product.get("role")
        product_id = product.get("productID")
        if not isinstance(role, str) or not isinstance(product_id, str):
            return None
        products_by_role[role] = product_id
    if set(products_by_role) != {"monthly", "annual"}:
        return None

    return {
        **{field: str(document[field]) for field in scalar_fields},
        "monthlyProductID": products_by_role["monthly"],
        "annualProductID": products_by_role["annual"],
    }


def placeholder_issues(field: str, value: str) -> list[str]:
    if not value:
        return []
    issues: list[str] = []
    if "$(" in value or "${" in value or "@@" in value:
        issues.append(issue_name(field, "UNEXPANDED"))
    lowered = value.lower()
    if (
        lowered in EXACT_PLACEHOLDER_VALUES
        or any(marker in lowered for marker in PLACEHOLDER_FRAGMENTS)
        or re.search(r"x{6,}", lowered)
    ):
        issues.append(issue_name(field, "PLACEHOLDER"))
    return issues


def is_https_url(value: str, expected_host: str | None = None) -> bool:
    try:
        parsed = urlparse(value)
    except ValueError:
        return False
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.query
        or parsed.fragment
    ):
        return False
    if parsed.username or parsed.password:
        return False
    if expected_host and parsed.hostname.lower() != expected_host:
        return False
    return True


def is_public_host(value: str) -> bool:
    host = value.lower()
    return bool(
        HOST_PATTERN.fullmatch(host)
        and host != "localhost"
        and not host.endswith(DISALLOWED_PRODUCTION_HOST_SUFFIXES)
    )


def is_sentry_dsn(value: str) -> bool:
    try:
        parsed = urlparse(value)
    except ValueError:
        return False
    return bool(
        parsed.scheme == "https"
        and parsed.hostname
        and is_public_host(parsed.hostname)
        and parsed.username
        and not parsed.password
        and parsed.path
        and parsed.path != "/"
        and not parsed.query
        and not parsed.fragment
    )


def validate_environment(values: dict[str, str]) -> list[str]:
    issues: list[str] = []
    approved_identity = load_approved_release_identity()
    if approved_identity is None:
        issues.append("E_APPROVED_RELEASE_IDENTITY_INVALID")

    for field in REQUIRED_ENV_FIELDS:
        if not values.get(field, "").strip():
            issues.append(issue_name(field, "MISSING"))

    for field in (*REQUIRED_ENV_FIELDS, *OPTIONAL_ENV_FIELDS):
        issues.extend(placeholder_issues(field, values.get(field, "")))

    environment = values.get("CHAPTERFLOW_ENVIRONMENT", "").strip()
    if environment and environment != "production":
        issues.append("E_CHAPTERFLOW_ENVIRONMENT_INVALID")

    api_url = values.get("API_BASE_URL", "").strip()
    if api_url and not is_https_url(api_url):
        issues.append("E_API_BASE_URL_HTTPS_REQUIRED")
    elif api_url:
        api_host = urlparse(api_url).hostname
        if not api_host or not is_public_host(api_host):
            issues.append("E_API_BASE_URL_DISALLOWED_HOST")

    region = values.get("COGNITO_REGION", "").strip()
    if region and not REGION_PATTERN.fullmatch(region):
        issues.append("E_COGNITO_REGION_MALFORMED")

    pool_id = values.get("COGNITO_USER_POOL_ID", "").strip()
    if pool_id and (
        not POOL_PATTERN.fullmatch(pool_id)
        or (region and not pool_id.startswith(f"{region}_"))
    ):
        issues.append("E_COGNITO_USER_POOL_ID_MALFORMED")

    client_id = values.get("COGNITO_CLIENT_ID", "").strip()
    if client_id and not CLIENT_PATTERN.fullmatch(client_id):
        issues.append("E_COGNITO_CLIENT_ID_MALFORMED")

    domain = values.get("COGNITO_DOMAIN", "").strip()
    if domain:
        domain_valid = bool(HOST_PATTERN.fullmatch(domain)) and not any(
            marker in domain for marker in ("://", "/", "?")
        )
        if domain.endswith(".amazoncognito.com") and region:
            domain_valid = domain_valid and f".auth.{region}.amazoncognito.com" in domain
        if not domain_valid:
            issues.append("E_COGNITO_DOMAIN_MALFORMED")
        elif not is_public_host(domain):
            issues.append("E_COGNITO_DOMAIN_DISALLOWED_HOST")

    bundle_id = values.get("PRODUCT_BUNDLE_IDENTIFIER", "").strip()
    if (
        bundle_id
        and approved_identity
        and bundle_id != approved_identity["bundleIdentifier"]
    ):
        issues.append("E_PRODUCT_BUNDLE_IDENTIFIER_MISMATCH")

    app_store_id = values.get("APP_STORE_ID", "").strip()
    if app_store_id and not APP_STORE_ID_PATTERN.fullmatch(app_store_id):
        issues.append("E_APP_STORE_ID_MALFORMED")
    if (
        app_store_id
        and approved_identity
        and app_store_id != approved_identity["appAppleID"]
    ):
        issues.append("E_APP_STORE_ID_APPROVED_IDENTITY_MISMATCH")

    app_store_url = values.get("APP_STORE_URL", "").strip()
    if app_store_url:
        try:
            parsed_app_store_url = urlparse(app_store_url)
            explicit_port = parsed_app_store_url.port is not None
        except ValueError:
            parsed_app_store_url = None
            explicit_port = True
        if (
            not is_https_url(app_store_url, "apps.apple.com")
            or explicit_port
            or parsed_app_store_url is None
        ):
            issues.append("E_APP_STORE_URL_INVALID")
        else:
            match = re.fullmatch(
                r".*/id([1-9][0-9]{5,19})/?",
                parsed_app_store_url.path,
            )
            if not match and re.search(r"/id[0-9]+(?:/|$)", parsed_app_store_url.path):
                issues.append("E_APP_STORE_URL_INVALID")
            elif not match:
                issues.append("E_APP_STORE_URL_ID_MISSING")
            elif app_store_id and match.group(1) != app_store_id:
                issues.append("E_APP_STORE_URL_ID_MISMATCH")

    support_url = values.get("SUPPORT_URL", "").strip()
    if support_url and not is_https_url(support_url):
        issues.append("E_SUPPORT_URL_INVALID")
    elif support_url:
        support_host = urlparse(support_url).hostname
        if not support_host or not is_public_host(support_host):
            issues.append("E_SUPPORT_URL_DISALLOWED_HOST")

    approved_raw = values.get("APPROVED_STOREKIT_PRODUCT_IDS", "")
    approved = [item.strip() for item in approved_raw.split(",") if item.strip()]
    if approved_raw.strip() and len(approved) < 2:
        issues.append("E_APPROVED_STOREKIT_PRODUCT_IDS_INCOMPLETE")
    if len(set(approved)) != len(approved):
        issues.append("E_APPROVED_STOREKIT_PRODUCT_IDS_DUPLICATE")
    if approved and any(not PRODUCT_PATTERN.fullmatch(item) for item in approved):
        issues.append("E_APPROVED_STOREKIT_PRODUCT_IDS_MALFORMED")
    approved_catalog_ids = (
        {
            approved_identity["monthlyProductID"],
            approved_identity["annualProductID"],
        }
        if approved_identity
        else set()
    )
    if approved and approved_catalog_ids and set(approved) != approved_catalog_ids:
        issues.append("E_APPROVED_STOREKIT_PRODUCT_IDS_CATALOG_MISMATCH")

    selected_fields = (
        "SK_MONTHLY_PRODUCT_ID",
        "SK_ANNUAL_PRODUCT_ID",
    )
    selected: list[str] = []
    for field in selected_fields:
        value = values.get(field, "").strip()
        if not value:
            continue
        selected.append(value)
        if not PRODUCT_PATTERN.fullmatch(value):
            issues.append(issue_name(field, "MALFORMED"))
        if approved and value not in approved:
            issues.append(issue_name(field, "NOT_APPROVED"))
        expected_role = "monthlyProductID" if field == "SK_MONTHLY_PRODUCT_ID" else "annualProductID"
        if approved_identity and value != approved_identity[expected_role]:
            issues.append(issue_name(field, "APPROVED_IDENTITY_MISMATCH"))
    if len(set(selected)) != len(selected):
        issues.append("E_STOREKIT_PRODUCT_IDS_DUPLICATE")
    if approved and len(selected) == 2 and set(approved) != set(selected):
        issues.append("E_APPROVED_STOREKIT_PRODUCT_IDS_SELECTION_MISMATCH")

    if values.get("SK_ANNUAL_UPFRONT_PRODUCT_ID", "").strip():
        issues.append("E_SK_ANNUAL_UPFRONT_PRODUCT_ID_UNSUPPORTED")

    sentry_policy = values.get("SENTRY_POLICY", "").strip()
    sentry_dsn = values.get("SENTRY_DSN", "").strip()
    if sentry_policy and sentry_policy not in {"disabled", "enabled"}:
        issues.append("E_SENTRY_POLICY_INVALID")
    if sentry_policy == "enabled":
        if not sentry_dsn:
            issues.append("E_SENTRY_DSN_MISSING")
        elif not is_sentry_dsn(sentry_dsn):
            issues.append("E_SENTRY_DSN_INVALID")

    configuration = values.get("BUILD_CONFIGURATION", "").strip()
    if configuration and configuration != "Release":
        issues.append("E_BUILD_CONFIGURATION_INVALID")

    marketing_version = values.get("MARKETING_VERSION", "").strip()
    if marketing_version and not VERSION_PATTERN.fullmatch(marketing_version):
        issues.append("E_MARKETING_VERSION_MALFORMED")

    build_number = values.get("BUILD_NUMBER", "").strip()
    if build_number and not BUILD_PATTERN.fullmatch(build_number):
        issues.append("E_BUILD_NUMBER_MALFORMED")

    commit = values.get("BUILD_COMMIT_SHA", "").strip()
    if commit and not COMMIT_PATTERN.fullmatch(commit):
        issues.append("E_BUILD_COMMIT_SHA_MALFORMED")

    team_id = values.get("APPLE_TEAM_ID", "").strip()
    if team_id and not TEAM_PATTERN.fullmatch(team_id):
        issues.append("E_APPLE_TEAM_ID_MALFORMED")
    if (
        team_id
        and approved_identity
        and team_id != approved_identity["appleTeamID"]
    ):
        issues.append("E_APPLE_TEAM_ID_APPROVED_IDENTITY_MISMATCH")

    key_id = values.get("ASC_KEY_ID", "").strip()
    if key_id and not KEY_ID_PATTERN.fullmatch(key_id):
        issues.append("E_ASC_KEY_ID_MALFORMED")

    issuer_id = values.get("ASC_ISSUER_ID", "").strip()
    if issuer_id and not ISSUER_PATTERN.fullmatch(issuer_id):
        issues.append("E_ASC_ISSUER_ID_MALFORMED")

    private_key = values.get("ASC_API_KEY_P8", "").strip()
    if private_key and not (
        ("-----BEGIN PRIVATE KEY-----" in private_key and "-----END PRIVATE KEY-----" in private_key)
        or (
            "-----BEGIN EC PRIVATE KEY-----" in private_key
            and "-----END EC PRIVATE KEY-----" in private_key
        )
    ):
        issues.append("E_ASC_API_KEY_P8_MALFORMED")

    certificate = values.get("DISTRIBUTION_CERT_P12_BASE64", "").strip()
    if certificate:
        try:
            decoded = base64.b64decode("".join(certificate.split()), validate=True)
            if len(decoded) < 8:
                issues.append("E_DISTRIBUTION_CERT_P12_BASE64_MALFORMED")
        except (binascii.Error, ValueError):
            issues.append("E_DISTRIBUTION_CERT_P12_BASE64_MALFORMED")

    backend_commit = values.get("BACKEND_DEPLOYMENT_COMMIT_SHA", "").strip()
    if backend_commit and not COMMIT_PATTERN.fullmatch(backend_commit):
        issues.append("E_BACKEND_DEPLOYMENT_COMMIT_SHA_MALFORMED")

    attestation_id = values.get("BACKEND_ATTESTATION_ID", "").strip()
    if attestation_id and not ATTESTATION_ID_PATTERN.fullmatch(attestation_id):
        issues.append("E_BACKEND_ATTESTATION_ID_MALFORMED")
    if values.get("BACKEND_ATTESTATION_APPROVED", "").strip() not in {"", "true"}:
        issues.append("E_BACKEND_ATTESTATION_NOT_APPROVED")

    backend_bundle = values.get("BACKEND_APPLE_BUNDLE_ID", "").strip()
    if backend_bundle and bundle_id and backend_bundle != bundle_id:
        issues.append("E_BACKEND_APPLE_BUNDLE_ID_MISMATCH")

    backend_app_id = values.get("BACKEND_APPLE_APP_ID", "").strip()
    if backend_app_id and not APP_STORE_ID_PATTERN.fullmatch(backend_app_id):
        issues.append("E_BACKEND_APPLE_APP_ID_MALFORMED")
    if backend_app_id and app_store_id and backend_app_id != app_store_id:
        issues.append("E_BACKEND_APPLE_APP_ID_MISMATCH")
    if (
        backend_app_id
        and approved_identity
        and backend_app_id != approved_identity["appAppleID"]
    ):
        issues.append("E_BACKEND_APPLE_APP_ID_APPROVED_IDENTITY_MISMATCH")

    backend_allowlist_raw = values.get(
        "BACKEND_VERIFICATION_PRODUCT_ALLOWLIST", ""
    )
    backend_allowlist = [
        item.strip() for item in backend_allowlist_raw.split(",") if item.strip()
    ]
    if len(set(backend_allowlist)) != len(backend_allowlist):
        issues.append("E_BACKEND_VERIFICATION_PRODUCT_ALLOWLIST_DUPLICATE")
    if backend_allowlist and any(
        not PRODUCT_PATTERN.fullmatch(item) for item in backend_allowlist
    ):
        issues.append("E_BACKEND_VERIFICATION_PRODUCT_ALLOWLIST_MALFORMED")
    if backend_allowlist and approved and set(backend_allowlist) != set(approved):
        issues.append("E_BACKEND_VERIFICATION_PRODUCT_ALLOWLIST_MISMATCH")
    if (
        backend_allowlist
        and approved_catalog_ids
        and set(backend_allowlist) != approved_catalog_ids
    ):
        issues.append("E_BACKEND_VERIFICATION_PRODUCT_ALLOWLIST_CATALOG_MISMATCH")

    backend_config_url = values.get(
        "BACKEND_MOBILE_CONFIG_APP_STORE_URL", ""
    ).strip()
    if backend_config_url and app_store_url and backend_config_url != app_store_url:
        issues.append("E_BACKEND_MOBILE_CONFIG_APP_STORE_URL_MISMATCH")

    backend_environment = values.get("BACKEND_APPLE_ENVIRONMENT", "").strip()
    if backend_environment and backend_environment != "Production":
        issues.append("E_BACKEND_APPLE_ENVIRONMENT_INVALID")

    subscription_group = values.get("BACKEND_SUBSCRIPTION_GROUP_ID", "").strip()
    if subscription_group and not SUBSCRIPTION_GROUP_PATTERN.fullmatch(
        subscription_group
    ):
        issues.append("E_BACKEND_SUBSCRIPTION_GROUP_ID_MALFORMED")
    if (
        subscription_group
        and approved_identity
        and subscription_group != approved_identity["subscriptionGroupID"]
    ):
        issues.append("E_BACKEND_SUBSCRIPTION_GROUP_ID_APPROVED_IDENTITY_MISMATCH")

    backend_controls = (
        "BACKEND_PRODUCT_ALLOWLIST_ENFORCED",
        "BACKEND_APPLE_ENVIRONMENT_ENFORCED",
        "BACKEND_SUBSCRIPTION_GROUP_ENFORCED",
        "BACKEND_ACCOUNT_BINDING_ENFORCED",
    )
    for field in backend_controls:
        if values.get(field, "").strip() not in {"", "true"}:
            issues.append(issue_name(field, "NOT_ENFORCED"))

    return unique(issues)


def manifest_without_fingerprint(manifest: dict[str, Any]) -> dict[str, Any]:
    payload = copy.deepcopy(manifest)
    payload.pop("provenanceFingerprint", None)
    return payload


def fingerprint(manifest: dict[str, Any]) -> str:
    payload = json.dumps(
        manifest_without_fingerprint(manifest),
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def build_manifest(values: dict[str, str]) -> dict[str, Any]:
    approved = [
        item.strip()
        for item in values["APPROVED_STOREKIT_PRODUCT_IDS"].split(",")
        if item.strip()
    ]
    manifest: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "environment": values["CHAPTERFLOW_ENVIRONMENT"].strip(),
        "apiBaseURL": values["API_BASE_URL"].strip(),
        "cognito": {
            "region": values["COGNITO_REGION"].strip(),
            "userPoolID": values["COGNITO_USER_POOL_ID"].strip(),
            "clientID": values["COGNITO_CLIENT_ID"].strip(),
            "domain": values["COGNITO_DOMAIN"].strip(),
        },
        "bundleIdentifier": values["PRODUCT_BUNDLE_IDENTIFIER"].strip(),
        "appStore": {
            "id": values["APP_STORE_ID"].strip(),
            "url": values["APP_STORE_URL"].strip(),
        },
        "supportURL": values["SUPPORT_URL"].strip(),
        "storeKit": {
            "approvedProductIDs": approved,
            "monthlyProductID": values["SK_MONTHLY_PRODUCT_ID"].strip(),
            "annualProductID": values["SK_ANNUAL_PRODUCT_ID"].strip(),
            "annualUpfrontProductID": values.get(
                "SK_ANNUAL_UPFRONT_PRODUCT_ID", ""
            ).strip(),
        },
        "sentry": {
            "policy": values["SENTRY_POLICY"].strip(),
            "dsnConfigured": bool(values.get("SENTRY_DSN", "").strip()),
        },
        "build": {
            "configuration": values["BUILD_CONFIGURATION"].strip(),
            "marketingVersion": values["MARKETING_VERSION"].strip(),
            "number": values["BUILD_NUMBER"].strip(),
            "commitSHA": values["BUILD_COMMIT_SHA"].strip().lower(),
        },
        "signing": {
            "teamID": values["APPLE_TEAM_ID"].strip(),
            "inputsValidated": True,
        },
        "backendAttestation": {
            "deploymentCommitSHA": values["BACKEND_DEPLOYMENT_COMMIT_SHA"].strip().lower(),
            "attestationID": values["BACKEND_ATTESTATION_ID"].strip(),
            "approved": values["BACKEND_ATTESTATION_APPROVED"].strip() == "true",
            "appleBundleIdentifier": values["BACKEND_APPLE_BUNDLE_ID"].strip(),
            "appleAppID": values["BACKEND_APPLE_APP_ID"].strip(),
            "verificationProductAllowlist": [
                item.strip()
                for item in values["BACKEND_VERIFICATION_PRODUCT_ALLOWLIST"].split(",")
                if item.strip()
            ],
            "mobileConfigAppStoreURL": values[
                "BACKEND_MOBILE_CONFIG_APP_STORE_URL"
            ].strip(),
            "appleEnvironment": values["BACKEND_APPLE_ENVIRONMENT"].strip(),
            "subscriptionGroupID": values["BACKEND_SUBSCRIPTION_GROUP_ID"].strip(),
            "controls": {
                "productAllowlistEnforced": values[
                    "BACKEND_PRODUCT_ALLOWLIST_ENFORCED"
                ].strip()
                == "true",
                "appleEnvironmentEnforced": values[
                    "BACKEND_APPLE_ENVIRONMENT_ENFORCED"
                ].strip()
                == "true",
                "subscriptionGroupEnforced": values[
                    "BACKEND_SUBSCRIPTION_GROUP_ENFORCED"
                ].strip()
                == "true",
                "accountBindingEnforced": values[
                    "BACKEND_ACCOUNT_BINDING_ENFORCED"
                ].strip()
                == "true",
            },
        },
    }
    manifest["provenanceFingerprint"] = fingerprint(manifest)
    return manifest


def manifest_to_environment(manifest: dict[str, Any]) -> dict[str, str]:
    cognito = manifest["cognito"]
    app_store = manifest["appStore"]
    store_kit = manifest["storeKit"]
    sentry = manifest["sentry"]
    build = manifest["build"]
    signing = manifest["signing"]
    backend = manifest["backendAttestation"]
    controls = backend["controls"]
    enabled_sentry = sentry["policy"] == "enabled"
    return {
        "CHAPTERFLOW_ENVIRONMENT": str(manifest["environment"]),
        "API_BASE_URL": str(manifest["apiBaseURL"]),
        "COGNITO_REGION": str(cognito["region"]),
        "COGNITO_USER_POOL_ID": str(cognito["userPoolID"]),
        "COGNITO_CLIENT_ID": str(cognito["clientID"]),
        "COGNITO_DOMAIN": str(cognito["domain"]),
        "PRODUCT_BUNDLE_IDENTIFIER": str(manifest["bundleIdentifier"]),
        "APP_STORE_ID": str(app_store["id"]),
        "APP_STORE_URL": str(app_store["url"]),
        "SUPPORT_URL": str(manifest["supportURL"]),
        "APPROVED_STOREKIT_PRODUCT_IDS": ",".join(store_kit["approvedProductIDs"]),
        "SK_MONTHLY_PRODUCT_ID": str(store_kit["monthlyProductID"]),
        "SK_ANNUAL_PRODUCT_ID": str(store_kit["annualProductID"]),
        "SK_ANNUAL_UPFRONT_PRODUCT_ID": str(store_kit["annualUpfrontProductID"]),
        "SENTRY_POLICY": str(sentry["policy"]),
        "SENTRY_DSN": "https://key@o1.ingest.sentry.io/1" if enabled_sentry else "",
        "BUILD_CONFIGURATION": str(build["configuration"]),
        "MARKETING_VERSION": str(build["marketingVersion"]),
        "BUILD_NUMBER": str(build["number"]),
        "BUILD_COMMIT_SHA": str(build["commitSHA"]),
        "APPLE_TEAM_ID": str(signing["teamID"]),
        "ASC_KEY_ID": "ABCDEFGH",
        "ASC_ISSUER_ID": "00000000-0000-0000-0000-000000000000",
        "ASC_API_KEY_P8": "-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----",
        "DISTRIBUTION_CERT_P12_BASE64": "c3ludGhldGljLXAxMg==",
        "DISTRIBUTION_CERT_PASSWORD": "synthetic-password",
        "BACKEND_DEPLOYMENT_COMMIT_SHA": str(backend["deploymentCommitSHA"]),
        "BACKEND_ATTESTATION_ID": str(backend["attestationID"]),
        "BACKEND_ATTESTATION_APPROVED": "true" if backend["approved"] else "false",
        "BACKEND_APPLE_BUNDLE_ID": str(backend["appleBundleIdentifier"]),
        "BACKEND_APPLE_APP_ID": str(backend["appleAppID"]),
        "BACKEND_VERIFICATION_PRODUCT_ALLOWLIST": ",".join(
            backend["verificationProductAllowlist"]
        ),
        "BACKEND_MOBILE_CONFIG_APP_STORE_URL": str(
            backend["mobileConfigAppStoreURL"]
        ),
        "BACKEND_APPLE_ENVIRONMENT": str(backend["appleEnvironment"]),
        "BACKEND_SUBSCRIPTION_GROUP_ID": str(backend["subscriptionGroupID"]),
        "BACKEND_PRODUCT_ALLOWLIST_ENFORCED": (
            "true" if controls["productAllowlistEnforced"] else "false"
        ),
        "BACKEND_APPLE_ENVIRONMENT_ENFORCED": (
            "true" if controls["appleEnvironmentEnforced"] else "false"
        ),
        "BACKEND_SUBSCRIPTION_GROUP_ENFORCED": (
            "true" if controls["subscriptionGroupEnforced"] else "false"
        ),
        "BACKEND_ACCOUNT_BINDING_ENFORCED": (
            "true" if controls["accountBindingEnforced"] else "false"
        ),
    }


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        document = json.load(handle)
    if not isinstance(document, dict):
        raise ValueError("manifest")
    return document


def load_manifest_schema() -> dict[str, Any]:
    with RELEASE_MANIFEST_SCHEMA_PATH.open("r", encoding="utf-8") as handle:
        schema = json.load(handle)
    if not isinstance(schema, dict):
        raise ValueError("manifest schema")
    return schema


def same_json_value(value: Any, expected: Any) -> bool:
    if isinstance(value, bool) or isinstance(expected, bool):
        return type(value) is type(expected) and value == expected
    return value == expected


def matches_schema_type(value: Any, expected_type: str) -> bool:
    type_checks = {
        "object": lambda candidate: isinstance(candidate, dict),
        "array": lambda candidate: isinstance(candidate, list),
        "string": lambda candidate: isinstance(candidate, str),
        "boolean": lambda candidate: isinstance(candidate, bool),
        "integer": lambda candidate: type(candidate) is int,
        "number": lambda candidate: (
            isinstance(candidate, (int, float)) and not isinstance(candidate, bool)
        ),
        "null": lambda candidate: candidate is None,
    }
    checker = type_checks.get(expected_type)
    return checker(value) if checker else False


def is_schema_uri(value: str) -> bool:
    try:
        parsed = urlparse(value)
    except ValueError:
        return False
    return bool(parsed.scheme and parsed.hostname)


def unique_json_items(items: list[Any]) -> bool:
    try:
        normalized = [
            json.dumps(item, sort_keys=True, separators=(",", ":"), allow_nan=False)
            for item in items
        ]
    except (TypeError, ValueError):
        return False
    return len(normalized) == len(set(normalized))


def matches_manifest_schema(value: Any, schema: dict[str, Any]) -> bool:
    if not isinstance(schema, dict) or not set(schema).issubset(SUPPORTED_SCHEMA_KEYS):
        return False

    expected_type = schema.get("type")
    if expected_type is not None:
        if not isinstance(expected_type, str) or not matches_schema_type(value, expected_type):
            return False

    if "const" in schema and not same_json_value(value, schema["const"]):
        return False

    if "enum" in schema:
        allowed = schema["enum"]
        if not isinstance(allowed, list) or not any(
            same_json_value(value, candidate) for candidate in allowed
        ):
            return False

    if isinstance(value, dict):
        required = schema.get("required", [])
        properties = schema.get("properties", {})
        if not isinstance(required, list) or not all(
            isinstance(key, str) for key in required
        ):
            return False
        if not isinstance(properties, dict) or not all(
            isinstance(key, str) and isinstance(child, dict)
            for key, child in properties.items()
        ):
            return False
        if not set(required).issubset(value):
            return False
        if schema.get("additionalProperties") is False and not set(value).issubset(
            properties
        ):
            return False
        for key, child_schema in properties.items():
            if key in value and not matches_manifest_schema(value[key], child_schema):
                return False

    if isinstance(value, list):
        min_items = schema.get("minItems")
        if min_items is not None and (
            type(min_items) is not int or min_items < 0 or len(value) < min_items
        ):
            return False
        if schema.get("uniqueItems") is True and not unique_json_items(value):
            return False
        item_schema = schema.get("items")
        if item_schema is not None:
            if not isinstance(item_schema, dict):
                return False
            if any(not matches_manifest_schema(item, item_schema) for item in value):
                return False

    if isinstance(value, str):
        min_length = schema.get("minLength")
        if min_length is not None and (
            type(min_length) is not int or min_length < 0 or len(value) < min_length
        ):
            return False
        pattern = schema.get("pattern")
        if pattern is not None:
            if not isinstance(pattern, str):
                return False
            try:
                if re.search(pattern, value) is None:
                    return False
            except re.error:
                return False
        format_name = schema.get("format")
        if format_name is not None:
            if format_name != "uri" or not is_schema_uri(value):
                return False

    return True


def manifest_matches_declared_schema(manifest: dict[str, Any]) -> bool:
    try:
        return matches_manifest_schema(manifest, load_manifest_schema())
    except (OSError, ValueError, json.JSONDecodeError):
        return False


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    try:
        if type(manifest.get("schemaVersion")) is not int or (
            manifest.get("schemaVersion") != SCHEMA_VERSION
        ):
            return ["E_MANIFEST_SCHEMA_VERSION"]
        if not manifest_matches_declared_schema(manifest):
            return ["E_MANIFEST_SCHEMA_INVALID"]
        values = manifest_to_environment(manifest)
        issues = validate_environment(values)
        sentry = manifest["sentry"]
        signing = manifest["signing"]
        backend = manifest["backendAttestation"]
        if sentry["policy"] == "enabled" and not sentry["dsnConfigured"]:
            issues.append("E_MANIFEST_SENTRY_DSN_NOT_CONFIGURED")
        if sentry["policy"] == "disabled" and sentry["dsnConfigured"]:
            issues.append("E_MANIFEST_SENTRY_POLICY_MISMATCH")
        if signing["inputsValidated"] is not True:
            issues.append("E_MANIFEST_SIGNING_NOT_VALIDATED")
        if backend["approved"] is not True:
            issues.append("E_MANIFEST_BACKEND_ATTESTATION_NOT_APPROVED")
        expected_fingerprint = manifest.get("provenanceFingerprint", "")
        if not re.fullmatch(r"[0-9a-f]{64}", str(expected_fingerprint)):
            issues.append("E_MANIFEST_FINGERPRINT_MALFORMED")
        elif expected_fingerprint != fingerprint(manifest):
            issues.append("E_MANIFEST_FINGERPRINT_MISMATCH")
        return unique(issues)
    except (KeyError, TypeError, ValueError):
        return ["E_MANIFEST_INVALID"]


def xcconfig_escape(value: str) -> str:
    if "\n" in value or "\r" in value:
        raise ValueError("multiline")
    return value.replace("://", ":/$()/")


def write_outputs(
    values: dict[str, str], manifest: dict[str, Any], xcconfig: Path, output: Path
) -> None:
    lines = [
        "// Generated by release_config.py after fail-closed validation.",
        "// Gitignored. Do not commit or upload this file as an artifact.",
        f"CHAPTERFLOW_ENVIRONMENT = {xcconfig_escape(values['CHAPTERFLOW_ENVIRONMENT'].strip())}",
        "BUILD_CONFIGURATION = Release",
        f"BUILD_COMMIT_SHA = {xcconfig_escape(values['BUILD_COMMIT_SHA'].strip().lower())}",
        "BACKEND_DEPLOYMENT_COMMIT_SHA = "
        + xcconfig_escape(values["BACKEND_DEPLOYMENT_COMMIT_SHA"].strip().lower()),
        "BACKEND_ATTESTATION_ID = "
        + xcconfig_escape(values["BACKEND_ATTESTATION_ID"].strip()),
        f"RELEASE_MANIFEST_FINGERPRINT = {manifest['provenanceFingerprint']}",
        f"API_BASE_URL = {xcconfig_escape(values['API_BASE_URL'].strip())}",
        f"COGNITO_REGION = {xcconfig_escape(values['COGNITO_REGION'].strip())}",
        f"COGNITO_USER_POOL_ID = {xcconfig_escape(values['COGNITO_USER_POOL_ID'].strip())}",
        f"COGNITO_CLIENT_ID = {xcconfig_escape(values['COGNITO_CLIENT_ID'].strip())}",
        f"COGNITO_DOMAIN = {xcconfig_escape(values['COGNITO_DOMAIN'].strip())}",
        f"APP_STORE_ID = {xcconfig_escape(values['APP_STORE_ID'].strip())}",
        f"APP_STORE_URL = {xcconfig_escape(values['APP_STORE_URL'].strip())}",
        f"SUPPORT_URL = {xcconfig_escape(values['SUPPORT_URL'].strip())}",
        f"SENTRY_POLICY = {xcconfig_escape(values['SENTRY_POLICY'].strip())}",
        f"SENTRY_DSN = {xcconfig_escape(values.get('SENTRY_DSN', '').strip())}",
        "APPROVED_STOREKIT_PRODUCT_IDS = "
        + xcconfig_escape(values["APPROVED_STOREKIT_PRODUCT_IDS"].strip()),
        "SK_MONTHLY_PRODUCT_ID = "
        + xcconfig_escape(values["SK_MONTHLY_PRODUCT_ID"].strip()),
        "SK_ANNUAL_PRODUCT_ID = "
        + xcconfig_escape(values["SK_ANNUAL_PRODUCT_ID"].strip()),
        "SK_ANNUAL_UPFRONT_PRODUCT_ID = "
        + xcconfig_escape(values.get("SK_ANNUAL_UPFRONT_PRODUCT_ID", "").strip()),
        "",
    ]

    xcconfig.parent.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    xcconfig.write_text("\n".join(lines), encoding="utf-8")
    os.chmod(xcconfig, 0o600)
    output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def recursive_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from recursive_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from recursive_strings(child)


def inspect_app(app: Path, manifest: dict[str, Any]) -> list[str]:
    issues = validate_manifest(manifest)
    info_path = app / "Info.plist"
    try:
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException):
        return unique([*issues, "E_ARCHIVE_INFO_PLIST_UNREADABLE"])

    cognito = manifest["cognito"]
    app_store = manifest["appStore"]
    store_kit = manifest["storeKit"]
    build = manifest["build"]
    backend = manifest["backendAttestation"]
    expected = {
        "APIBaseURL": manifest["apiBaseURL"],
        "ChapterFlowEnvironment": manifest["environment"],
        "BundleIdentifier": manifest["bundleIdentifier"],
        "AppStoreID": app_store["id"],
        "AppStoreURL": app_store["url"],
        "SupportURL": manifest["supportURL"],
        "SentryPolicy": manifest["sentry"]["policy"],
        "BuildConfiguration": build["configuration"],
        "BuildCommitSHA": build["commitSHA"],
        "BackendDeploymentCommitSHA": backend["deploymentCommitSHA"],
        "BackendAttestationID": backend["attestationID"],
        "MarketingVersion": build["marketingVersion"],
        "BuildNumber": build["number"],
        "ReleaseManifestFingerprint": manifest["provenanceFingerprint"],
        "CognitoRegion": cognito["region"],
        "CognitoUserPoolID": cognito["userPoolID"],
        "CognitoClientID": cognito["clientID"],
        "CognitoDomain": cognito["domain"],
        "SKMonthlyProductID": store_kit["monthlyProductID"],
        "SKAnnualProductID": store_kit["annualProductID"],
        "SKAnnualUpfrontProductID": store_kit["annualUpfrontProductID"],
        "CFBundleIdentifier": manifest["bundleIdentifier"],
        "CFBundleShortVersionString": build["marketingVersion"],
        "CFBundleVersion": build["number"],
    }
    for key, expected_value in expected.items():
        if str(info.get(key, "")) != str(expected_value):
            issues.append(issue_name(f"ARCHIVE_{key.upper()}", "MISMATCH"))

    sentry_dsn = str(info.get("SentryDSN", ""))
    if manifest["sentry"]["policy"] == "enabled" and not is_sentry_dsn(sentry_dsn):
        issues.append("E_ARCHIVE_SENTRY_DSN_INVALID")
    if manifest["sentry"]["policy"] == "disabled" and sentry_dsn:
        issues.append("E_ARCHIVE_SENTRY_POLICY_MISMATCH")

    for value in recursive_strings(info):
        if placeholder_issues("ARCHIVE", value):
            issues.append("E_ARCHIVE_PLACEHOLDER_OR_UNEXPANDED")
            break
    return unique(issues)


def inspect_archive(archive: Path, manifest: dict[str, Any]) -> list[str]:
    app = archive / "Products" / "Applications" / "ChapterFlow.app"
    return inspect_app(app, manifest)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--manifest", type=Path)

    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("--xcconfig", type=Path, required=True)
    generate_parser.add_argument("--manifest", type=Path, required=True)

    inspect_parser = subparsers.add_parser("inspect-archive")
    inspect_parser.add_argument("--archive", type=Path, required=True)
    inspect_parser.add_argument("--manifest", type=Path, required=True)

    inspect_app_parser = subparsers.add_parser("inspect-app")
    inspect_app_parser.add_argument("--app", type=Path, required=True)
    inspect_app_parser.add_argument("--manifest", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        if args.command == "validate":
            if args.manifest:
                return emit(validate_manifest(load_manifest(args.manifest)))
            return emit(validate_environment(environment_values()))

        if args.command == "generate":
            values = environment_values()
            issues = validate_environment(values)
            if issues:
                return emit(issues)
            manifest = build_manifest(values)
            write_outputs(values, manifest, args.xcconfig, args.manifest)
            return emit(validate_manifest(manifest))

        if args.command == "inspect-archive":
            manifest = load_manifest(args.manifest)
            return emit(inspect_archive(args.archive, manifest))

        if args.command == "inspect-app":
            manifest = load_manifest(args.manifest)
            return emit(inspect_app(args.app, manifest))
    except (OSError, ValueError, json.JSONDecodeError):
        return emit(["E_RELEASE_CONFIG_TOOL_INPUT"])
    except Exception:  # Keep unexpected failures redacted; never print inputs.
        return emit(["E_RELEASE_CONFIG_TOOL_INTERNAL"])
    return emit(["E_RELEASE_CONFIG_TOOL_COMMAND"])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
