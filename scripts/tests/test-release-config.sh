#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/scripts/release-config/release_config.py"
PROJECT="$ROOT/ChapterFlow.xcodeproj/project.pbxproj"
RELEASE_WORKFLOW="$ROOT/.github/workflows/release.yml"
PR_WORKFLOW="$ROOT/.github/workflows/pr.yml"
EXPORT_OPTIONS="$ROOT/Config/ExportOptions.plist"
STOREKIT_CATALOG_TEST="$ROOT/scripts/tests/test-storekit-catalog.py"

tests=0
failures=0
last_output=""
last_status=0

base_environment=(
  "PATH=$PATH"
  "HOME=${HOME:-/tmp}"
  "LC_ALL=C"
  "CHAPTERFLOW_ENVIRONMENT=production"
  "API_BASE_URL=https://api.release-fixture.chapterflow.ca/v1"
  "COGNITO_REGION=us-east-1"
  "COGNITO_USER_POOL_ID=us-east-1_AbCdEf123"
  "COGNITO_CLIENT_ID=1234567890abcdefghijklmnop"
  "COGNITO_DOMAIN=auth.release-fixture.chapterflow.ca"
  "PRODUCT_BUNDLE_IDENTIFIER=com.chapterflow.ios"
  "APP_STORE_ID=6787864558"
  "APP_STORE_URL=https://apps.apple.com/app/id6787864558"
  "SUPPORT_URL=https://support.release-fixture.chapterflow.ca/help"
  "APPROVED_STOREKIT_PRODUCT_IDS=com.chapterflow.pro.monthly,com.chapterflow.pro.annual"
  "SK_MONTHLY_PRODUCT_ID=com.chapterflow.pro.monthly"
  "SK_ANNUAL_PRODUCT_ID=com.chapterflow.pro.annual"
  "SK_ANNUAL_UPFRONT_PRODUCT_ID="
  "SENTRY_POLICY=disabled"
  "SENTRY_DSN="
  "BUILD_CONFIGURATION=Release"
  "MARKETING_VERSION=1.0.0"
  "BUILD_NUMBER=42"
  "BUILD_COMMIT_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  "APPLE_TEAM_ID=ZG3C9QBA8Z"
  "ASC_KEY_ID=ABCDEFGH"
  "ASC_ISSUER_ID=12345678-1234-1234-1234-1234567890ab"
  $'ASC_API_KEY_P8=-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----'
  "DISTRIBUTION_CERT_P12_BASE64=c3ludGhldGljLXAxMg=="
  "DISTRIBUTION_CERT_PASSWORD=synthetic-password"
  "BACKEND_DEPLOYMENT_COMMIT_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  "BACKEND_ATTESTATION_ID=attestation-test-0001"
  "BACKEND_ATTESTATION_APPROVED=true"
  "BACKEND_APPLE_BUNDLE_ID=com.chapterflow.ios"
  "BACKEND_APPLE_APP_ID=6787864558"
  "BACKEND_VERIFICATION_PRODUCT_ALLOWLIST=com.chapterflow.pro.monthly,com.chapterflow.pro.annual"
  "BACKEND_MOBILE_CONFIG_APP_STORE_URL=https://apps.apple.com/app/id6787864558"
  "BACKEND_APPLE_ENVIRONMENT=Production"
  "BACKEND_SUBSCRIPTION_GROUP_ID=22211821"
  "BACKEND_PRODUCT_ALLOWLIST_ENFORCED=true"
  "BACKEND_APPLE_ENVIRONMENT_ENFORCED=true"
  "BACKEND_SUBSCRIPTION_GROUP_ENFORCED=true"
  "BACKEND_ACCOUNT_BINDING_ENFORCED=true"
)

run_validate() {
  set +e
  last_output="$(env -i "${base_environment[@]}" "$@" python3 "$TOOL" validate 2>&1)"
  last_status=$?
  set -e
}

assert_redacted_output() {
  if printf '%s\n' "$last_output" | grep -Ev '^(OK|E_[A-Z0-9_]+)$' >/dev/null; then
    printf 'not ok - non-redacted validator output\n'
    failures=$((failures + 1))
    return 1
  fi
  return 0
}

expect_pass() {
  tests=$((tests + 1))
  run_validate "$@"
  if [ "$last_status" -ne 0 ] || [ "$last_output" != "OK" ]; then
    printf 'not ok %s - expected validation success\n' "$tests"
    failures=$((failures + 1))
    return
  fi
  printf 'ok %s - valid configuration\n' "$tests"
}

expect_fail() {
  expected="$1"
  shift
  tests=$((tests + 1))
  run_validate "$@"
  assert_redacted_output || return
  if [ "$last_status" -eq 0 ]; then
    printf 'not ok %s - expected %s\n' "$tests" "$expected"
    failures=$((failures + 1))
    return
  fi
  if ! printf '%s\n' "$last_output" | grep -qx "$expected"; then
    printf 'not ok %s - missing %s\n' "$tests" "$expected"
    failures=$((failures + 1))
    return
  fi
  printf 'ok %s - %s\n' "$tests" "$expected"
}

expect_manifest_fail() {
  expected="$1"
  manifest_path="$2"
  tests=$((tests + 1))
  set +e
  last_output="$(python3 "$TOOL" validate --manifest "$manifest_path" 2>&1)"
  last_status=$?
  set -e
  assert_redacted_output || return
  if [ "$last_status" -eq 0 ]; then
    printf 'not ok %s - expected %s\n' "$tests" "$expected"
    failures=$((failures + 1))
    return
  fi
  if ! printf '%s\n' "$last_output" | grep -qx "$expected"; then
    printf 'not ok %s - missing %s\n' "$tests" "$expected"
    failures=$((failures + 1))
    return
  fi
  printf 'ok %s - %s\n' "$tests" "$expected"
}

tests=$((tests + 1))
set +e
storekit_catalog_output="$(python3 "$STOREKIT_CATALOG_TEST" 2>&1)"
storekit_catalog_status=$?
set -e
if [ "$storekit_catalog_status" -eq 0 ] && [ "$storekit_catalog_output" = "OK" ]; then
  printf 'ok %s - StoreKit Test fixture matches approved catalog and isolated scheme\n' "$tests"
else
  printf 'not ok %s - StoreKit Test fixture consistency failed\n' "$tests"
  printf '# %s\n' "$storekit_catalog_output"
  failures=$((failures + 1))
fi

expect_pass

required_fields=(
  CHAPTERFLOW_ENVIRONMENT
  API_BASE_URL
  COGNITO_REGION
  COGNITO_USER_POOL_ID
  COGNITO_CLIENT_ID
  COGNITO_DOMAIN
  PRODUCT_BUNDLE_IDENTIFIER
  APP_STORE_ID
  APP_STORE_URL
  SUPPORT_URL
  APPROVED_STOREKIT_PRODUCT_IDS
  SK_MONTHLY_PRODUCT_ID
  SK_ANNUAL_PRODUCT_ID
  SENTRY_POLICY
  BUILD_CONFIGURATION
  MARKETING_VERSION
  BUILD_NUMBER
  BUILD_COMMIT_SHA
  APPLE_TEAM_ID
  ASC_KEY_ID
  ASC_ISSUER_ID
  ASC_API_KEY_P8
  DISTRIBUTION_CERT_P12_BASE64
  DISTRIBUTION_CERT_PASSWORD
  BACKEND_DEPLOYMENT_COMMIT_SHA
  BACKEND_ATTESTATION_ID
  BACKEND_ATTESTATION_APPROVED
  BACKEND_APPLE_BUNDLE_ID
  BACKEND_APPLE_APP_ID
  BACKEND_VERIFICATION_PRODUCT_ALLOWLIST
  BACKEND_MOBILE_CONFIG_APP_STORE_URL
  BACKEND_APPLE_ENVIRONMENT
  BACKEND_SUBSCRIPTION_GROUP_ID
  BACKEND_PRODUCT_ALLOWLIST_ENFORCED
  BACKEND_APPLE_ENVIRONMENT_ENFORCED
  BACKEND_SUBSCRIPTION_GROUP_ENFORCED
  BACKEND_ACCOUNT_BINDING_ENFORCED
)

for field in "${required_fields[@]}"; do
  expect_fail "E_${field}_MISSING" "$field="
done

for field in "${required_fields[@]}"; do
  expect_fail "E_${field}_PLACEHOLDER" "$field=PLACEHOLDER"
done

expect_fail E_API_BASE_URL_UNEXPANDED 'API_BASE_URL=$(API_BASE_URL)'
expect_fail E_API_BASE_URL_UNEXPANDED API_BASE_URL=https://@@.chapterflow.ca/v1
expect_fail E_API_BASE_URL_HTTPS_REQUIRED API_BASE_URL=http://api.release-fixture.chapterflow.ca/v1
expect_fail E_API_BASE_URL_DISALLOWED_HOST API_BASE_URL=https://api.chapterflow.invalid/v1
expect_fail E_COGNITO_REGION_MALFORMED COGNITO_REGION=not-a-region
expect_fail E_COGNITO_USER_POOL_ID_MALFORMED COGNITO_USER_POOL_ID=us-west-2_AbCdEf123
expect_fail E_COGNITO_CLIENT_ID_MALFORMED COGNITO_CLIENT_ID=short
expect_fail E_COGNITO_DOMAIN_MALFORMED COGNITO_DOMAIN=https://auth.release-fixture.chapterflow.ca/path
expect_fail E_COGNITO_DOMAIN_DISALLOWED_HOST COGNITO_DOMAIN=auth.chapterflow.invalid
expect_fail E_PRODUCT_BUNDLE_IDENTIFIER_MISMATCH PRODUCT_BUNDLE_IDENTIFIER=com.example.wrong
expect_fail E_APP_STORE_ID_MALFORMED APP_STORE_ID=abc123
expect_fail E_APP_STORE_ID_MALFORMED APP_STORE_ID=123456789012345678901
expect_fail E_APP_STORE_ID_APPROVED_IDENTITY_MISMATCH APP_STORE_ID=1234567890
expect_fail E_APP_STORE_URL_INVALID APP_STORE_URL=https://support.test.chapterflow.invalid/id1234567890
expect_fail E_APP_STORE_URL_INVALID APP_STORE_URL=https://apps.apple.com:443/us/app/chapterflow-test/id6787864558
expect_fail E_APP_STORE_URL_INVALID APP_STORE_URL=https://apps.apple.com/us/app/chapterflow-test/id6787864558/reviews
expect_fail E_APP_STORE_URL_ID_MISSING APP_STORE_URL=https://apps.apple.com/us/app/chapterflow-test
expect_fail E_APP_STORE_URL_ID_MISMATCH APP_STORE_URL=https://apps.apple.com/us/app/chapterflow-test/id1234567891
expect_fail E_SUPPORT_URL_INVALID SUPPORT_URL=http://support.release-fixture.chapterflow.ca/help
expect_fail E_SUPPORT_URL_DISALLOWED_HOST SUPPORT_URL=https://support.chapterflow.invalid/help
expect_fail E_SUPPORT_URL_PLACEHOLDER SUPPORT_URL=https://support.chapterflow.ca/replace-me
expect_fail E_APPROVED_STOREKIT_PRODUCT_IDS_INCOMPLETE APPROVED_STOREKIT_PRODUCT_IDS=com.chapterflow.test.pro.monthly
expect_fail E_APPROVED_STOREKIT_PRODUCT_IDS_DUPLICATE APPROVED_STOREKIT_PRODUCT_IDS=com.chapterflow.test.pro.monthly,com.chapterflow.test.pro.monthly
expect_fail E_APPROVED_STOREKIT_PRODUCT_IDS_MALFORMED APPROVED_STOREKIT_PRODUCT_IDS=com.chapterflow.test.pro.monthly,bad/product
expect_fail E_APPROVED_STOREKIT_PRODUCT_IDS_SELECTION_MISMATCH APPROVED_STOREKIT_PRODUCT_IDS=com.chapterflow.test.pro.monthly,com.chapterflow.test.pro.annual,com.chapterflow.test.pro.hidden
expect_fail E_APPROVED_STOREKIT_PRODUCT_IDS_CATALOG_MISMATCH APPROVED_STOREKIT_PRODUCT_IDS=com.chapterflow.other.monthly,com.chapterflow.other.annual
expect_fail E_SK_MONTHLY_PRODUCT_ID_MALFORMED SK_MONTHLY_PRODUCT_ID=bad/product
expect_fail E_SK_MONTHLY_PRODUCT_ID_PLACEHOLDER SK_MONTHLY_PRODUCT_ID=com.chapterflow.replace-me.monthly
expect_fail E_SK_MONTHLY_PRODUCT_ID_NOT_APPROVED SK_MONTHLY_PRODUCT_ID=com.chapterflow.test.pro.unapproved
expect_fail E_SK_MONTHLY_PRODUCT_ID_APPROVED_IDENTITY_MISMATCH SK_MONTHLY_PRODUCT_ID=com.chapterflow.pro.other-monthly
expect_fail E_SK_ANNUAL_PRODUCT_ID_APPROVED_IDENTITY_MISMATCH SK_ANNUAL_PRODUCT_ID=com.chapterflow.pro.other-annual
expect_fail E_STOREKIT_PRODUCT_IDS_DUPLICATE SK_ANNUAL_PRODUCT_ID=com.chapterflow.pro.monthly
expect_fail E_SK_ANNUAL_UPFRONT_PRODUCT_ID_PLACEHOLDER SK_ANNUAL_UPFRONT_PRODUCT_ID=PLACEHOLDER
expect_fail E_SK_ANNUAL_UPFRONT_PRODUCT_ID_UNSUPPORTED SK_ANNUAL_UPFRONT_PRODUCT_ID=com.chapterflow.test.pro.upfront
expect_fail E_SENTRY_POLICY_INVALID SENTRY_POLICY=unspecified
expect_fail E_SENTRY_DSN_PLACEHOLDER SENTRY_POLICY=enabled SENTRY_DSN=PLACEHOLDER
expect_fail E_SENTRY_DSN_MISSING SENTRY_POLICY=enabled SENTRY_DSN=
expect_fail E_SENTRY_DSN_INVALID SENTRY_POLICY=enabled SENTRY_DSN=https://ingest.sentry.io/no-key
expect_fail E_SENTRY_DSN_INVALID SENTRY_POLICY=enabled SENTRY_DSN=https://publickey@o1.ingest.sentry.invalid/1
expect_pass SENTRY_POLICY=enabled SENTRY_DSN=https://publickey@o1.ingest.sentry.io/1
expect_fail E_BUILD_CONFIGURATION_INVALID BUILD_CONFIGURATION=Debug
expect_fail E_MARKETING_VERSION_MALFORMED MARKETING_VERSION=v1
expect_fail E_BUILD_NUMBER_MALFORMED BUILD_NUMBER=0
expect_fail E_BUILD_COMMIT_SHA_MALFORMED BUILD_COMMIT_SHA=deadbeef
expect_fail E_APPLE_TEAM_ID_MALFORMED APPLE_TEAM_ID=short
expect_fail E_APPLE_TEAM_ID_APPROVED_IDENTITY_MISMATCH APPLE_TEAM_ID=ABCDEFGHIJ
expect_fail E_ASC_KEY_ID_MALFORMED ASC_KEY_ID=bad-key
expect_fail E_ASC_ISSUER_ID_MALFORMED ASC_ISSUER_ID=not-a-uuid
expect_fail E_ASC_API_KEY_P8_MALFORMED ASC_API_KEY_P8=not-a-private-key
expect_fail E_DISTRIBUTION_CERT_P12_BASE64_MALFORMED DISTRIBUTION_CERT_P12_BASE64=not-base64
expect_fail E_BACKEND_DEPLOYMENT_COMMIT_SHA_MALFORMED BACKEND_DEPLOYMENT_COMMIT_SHA=deadbeef
expect_fail E_BACKEND_ATTESTATION_ID_MALFORMED BACKEND_ATTESTATION_ID=short
expect_fail E_BACKEND_ATTESTATION_NOT_APPROVED BACKEND_ATTESTATION_APPROVED=false
expect_fail E_BACKEND_APPLE_BUNDLE_ID_MISMATCH BACKEND_APPLE_BUNDLE_ID=com.chapterflow.test.wrong
expect_fail E_BACKEND_APPLE_APP_ID_MALFORMED BACKEND_APPLE_APP_ID=abc123
expect_fail E_BACKEND_APPLE_APP_ID_MISMATCH BACKEND_APPLE_APP_ID=1234567890
expect_fail E_BACKEND_APPLE_APP_ID_APPROVED_IDENTITY_MISMATCH \
  APP_STORE_ID=1234567890 \
  APP_STORE_URL=https://apps.apple.com/app/id1234567890 \
  BACKEND_APPLE_APP_ID=1234567890
expect_fail E_BACKEND_VERIFICATION_PRODUCT_ALLOWLIST_DUPLICATE BACKEND_VERIFICATION_PRODUCT_ALLOWLIST=com.chapterflow.test.pro.monthly,com.chapterflow.test.pro.monthly
expect_fail E_BACKEND_VERIFICATION_PRODUCT_ALLOWLIST_MALFORMED BACKEND_VERIFICATION_PRODUCT_ALLOWLIST=com.chapterflow.test.pro.monthly,bad/product
expect_fail E_BACKEND_VERIFICATION_PRODUCT_ALLOWLIST_MISMATCH BACKEND_VERIFICATION_PRODUCT_ALLOWLIST=com.chapterflow.test.pro.monthly,com.chapterflow.test.pro.different
expect_fail E_BACKEND_VERIFICATION_PRODUCT_ALLOWLIST_CATALOG_MISMATCH BACKEND_VERIFICATION_PRODUCT_ALLOWLIST=com.chapterflow.other.monthly,com.chapterflow.other.annual
expect_fail E_BACKEND_MOBILE_CONFIG_APP_STORE_URL_MISMATCH BACKEND_MOBILE_CONFIG_APP_STORE_URL=https://apps.apple.com/us/app/chapterflow-test/id1234567891
expect_fail E_BACKEND_APPLE_ENVIRONMENT_INVALID BACKEND_APPLE_ENVIRONMENT=Sandbox
expect_fail E_BACKEND_SUBSCRIPTION_GROUP_ID_MALFORMED BACKEND_SUBSCRIPTION_GROUP_ID=bad/group
expect_fail E_BACKEND_SUBSCRIPTION_GROUP_ID_APPROVED_IDENTITY_MISMATCH BACKEND_SUBSCRIPTION_GROUP_ID=other.subscription.group
expect_fail E_BACKEND_PRODUCT_ALLOWLIST_ENFORCED_NOT_ENFORCED BACKEND_PRODUCT_ALLOWLIST_ENFORCED=false
expect_fail E_BACKEND_APPLE_ENVIRONMENT_ENFORCED_NOT_ENFORCED BACKEND_APPLE_ENVIRONMENT_ENFORCED=false
expect_fail E_BACKEND_SUBSCRIPTION_GROUP_ENFORCED_NOT_ENFORCED BACKEND_SUBSCRIPTION_GROUP_ENFORCED=false
expect_fail E_BACKEND_ACCOUNT_BINDING_ENFORCED_NOT_ENFORCED BACKEND_ACCOUNT_BINDING_ENFORCED=false

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
manifest="$tmp/manifest.json"
xcconfig="$tmp/Secrets.xcconfig"

tamper_manifest() {
  mode="$1"
  source_manifest="$2"
  destination_manifest="$3"
  python3 - "$mode" "$source_manifest" "$destination_manifest" <<'PY'
import hashlib
import json
import sys

mode, source_path, destination_path = sys.argv[1:]
with open(source_path, encoding="utf-8") as handle:
    manifest = json.load(handle)

recompute_fingerprint = True
if mode == "root-extra":
    manifest["unexpected"] = "safe-test-value"
elif mode == "nested-extra":
    manifest["backendAttestation"]["controls"]["unexpected"] = True
elif mode == "control-string":
    manifest["backendAttestation"]["controls"]["productAllowlistEnforced"] = "true"
elif mode == "missing-required":
    del manifest["supportURL"]
elif mode == "boolean-schema-version":
    manifest["schemaVersion"] = True
elif mode == "upfront-product":
    manifest["storeKit"]["annualUpfrontProductID"] = "com.chapterflow.test.pro.upfront"
elif mode == "backend-apple-app-id":
    manifest["backendAttestation"]["appleAppID"] = "1234567890"
elif mode == "backend-apple-app-id-unfingerprinted":
    manifest["backendAttestation"]["appleAppID"] = "1234567890"
    recompute_fingerprint = False
else:
    raise SystemExit("unknown tamper mode")

if recompute_fingerprint:
    payload = dict(manifest)
    payload.pop("provenanceFingerprint", None)
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    manifest["provenanceFingerprint"] = hashlib.sha256(canonical).hexdigest()
with open(destination_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

tests=$((tests + 1))
generate_output="$(env -i "${base_environment[@]}" python3 "$TOOL" generate \
  --xcconfig "$xcconfig" --manifest "$manifest" 2>&1)" || {
  printf 'not ok %s - generator failed\n' "$tests"
  failures=$((failures + 1))
  generate_output=""
}
if [ "$generate_output" = "OK" ] && [ -s "$xcconfig" ] && [ -s "$manifest" ]; then
  printf 'ok %s - generated xcconfig and manifest\n' "$tests"
else
  printf 'not ok %s - generated output missing\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
xcconfig_mode="$(python3 - "$xcconfig" <<'PY'
import os
import stat
import sys

print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))
PY
)"
if [ "$xcconfig_mode" = "0o600" ]; then
  printf 'ok %s - generated xcconfig is owner-readable only\n' "$tests"
else
  printf 'not ok %s - generated xcconfig mode is not 0600\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
if [ "$(python3 "$TOOL" validate --manifest "$manifest")" = "OK" ]; then
  printf 'ok %s - generated manifest validates\n' "$tests"
else
  printf 'not ok %s - generated manifest validation failed\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
backend_app_id_binding="$(python3 - "$manifest" \
  "$ROOT/Config/ApprovedReleaseIdentity.json" <<'PY'
import copy
import hashlib
import json
import sys

manifest_path, identity_path = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)
with open(identity_path, encoding="utf-8") as handle:
    identity = json.load(handle)

backend_app_id = manifest["backendAttestation"]["appleAppID"]
exact = backend_app_id == manifest["appStore"]["id"] == identity["appAppleID"]
changed = copy.deepcopy(manifest)
changed.pop("provenanceFingerprint", None)
changed["backendAttestation"]["appleAppID"] = "1234567890"
canonical = json.dumps(changed, sort_keys=True, separators=(",", ":")).encode()
changed_fingerprint = hashlib.sha256(canonical).hexdigest()
print(str(exact and changed_fingerprint != manifest["provenanceFingerprint"]).lower())
PY
)"
if [ "$backend_app_id_binding" = "true" ]; then
  printf 'ok %s - backend Apple App ID is exact and fingerprint-bound\n' "$tests"
else
  printf 'not ok %s - backend Apple App ID attestation is incomplete\n' "$tests"
  failures=$((failures + 1))
fi

tampered_manifest="$tmp/manifest-tampered.json"
tamper_manifest root-extra "$manifest" "$tampered_manifest"
expect_manifest_fail E_MANIFEST_SCHEMA_INVALID "$tampered_manifest"

tamper_manifest nested-extra "$manifest" "$tampered_manifest"
expect_manifest_fail E_MANIFEST_SCHEMA_INVALID "$tampered_manifest"

tamper_manifest control-string "$manifest" "$tampered_manifest"
expect_manifest_fail E_MANIFEST_SCHEMA_INVALID "$tampered_manifest"

tamper_manifest missing-required "$manifest" "$tampered_manifest"
expect_manifest_fail E_MANIFEST_SCHEMA_INVALID "$tampered_manifest"

tamper_manifest boolean-schema-version "$manifest" "$tampered_manifest"
expect_manifest_fail E_MANIFEST_SCHEMA_VERSION "$tampered_manifest"

tamper_manifest upfront-product "$manifest" "$tampered_manifest"
expect_manifest_fail E_MANIFEST_SCHEMA_INVALID "$tampered_manifest"

tamper_manifest backend-apple-app-id "$manifest" "$tampered_manifest"
expect_manifest_fail E_BACKEND_APPLE_APP_ID_MISMATCH "$tampered_manifest"

tamper_manifest backend-apple-app-id-unfingerprinted "$manifest" "$tampered_manifest"
expect_manifest_fail E_MANIFEST_FINGERPRINT_MISMATCH "$tampered_manifest"

tests=$((tests + 1))
if grep -Eq 'ASC_API_KEY|DISTRIBUTION_CERT|PRIVATE KEY|synthetic-password|SENTRY_DSN' "$manifest"; then
  printf 'not ok %s - generated manifest contains protected material\n' "$tests"
  failures=$((failures + 1))
else
  printf 'ok %s - generated manifest is nonsecret\n' "$tests"
fi

archive="$tmp/ChapterFlow.xcarchive"
mkdir -p "$archive/Products/Applications/ChapterFlow.app"
python3 - "$manifest" "$archive/Products/Applications/ChapterFlow.app/Info.plist" <<'PY'
import json
import plistlib
import sys

manifest_path, plist_path = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)
build = manifest["build"]
store = manifest["storeKit"]
info = {
    "APIBaseURL": manifest["apiBaseURL"],
    "ChapterFlowEnvironment": manifest["environment"],
    "BundleIdentifier": manifest["bundleIdentifier"],
    "AppStoreID": manifest["appStore"]["id"],
    "AppStoreURL": manifest["appStore"]["url"],
    "SupportURL": manifest["supportURL"],
    "SentryPolicy": manifest["sentry"]["policy"],
    "SentryDSN": "",
    "BuildConfiguration": build["configuration"],
    "BuildCommitSHA": build["commitSHA"],
    "BackendDeploymentCommitSHA": manifest["backendAttestation"]["deploymentCommitSHA"],
    "BackendAttestationID": manifest["backendAttestation"]["attestationID"],
    "MarketingVersion": build["marketingVersion"],
    "BuildNumber": build["number"],
    "ReleaseManifestFingerprint": manifest["provenanceFingerprint"],
    "CognitoRegion": manifest["cognito"]["region"],
    "CognitoUserPoolID": manifest["cognito"]["userPoolID"],
    "CognitoClientID": manifest["cognito"]["clientID"],
    "CognitoDomain": manifest["cognito"]["domain"],
    "SKMonthlyProductID": store["monthlyProductID"],
    "SKAnnualProductID": store["annualProductID"],
    "SKAnnualUpfrontProductID": store["annualUpfrontProductID"],
    "CFBundleIdentifier": manifest["bundleIdentifier"],
    "CFBundleShortVersionString": build["marketingVersion"],
    "CFBundleVersion": build["number"],
}
with open(plist_path, "wb") as handle:
    plistlib.dump(info, handle)
PY

tests=$((tests + 1))
if [ "$(python3 "$TOOL" inspect-archive --archive "$archive" --manifest "$manifest")" = "OK" ]; then
  printf 'ok %s - archive provenance inspection succeeds\n' "$tests"
else
  printf 'not ok %s - archive provenance inspection failed\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
app="$archive/Products/Applications/ChapterFlow.app"
if [ "$(python3 "$TOOL" inspect-app --app "$app" --manifest "$manifest")" = "OK" ]; then
  printf 'ok %s - exported app provenance inspection succeeds\n' "$tests"
else
  printf 'not ok %s - exported app provenance inspection failed\n' "$tests"
  failures=$((failures + 1))
fi

python3 - "$archive/Products/Applications/ChapterFlow.app/Info.plist" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as handle:
    info = plistlib.load(handle)
info["BuildCommitSHA"] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
with open(path, "wb") as handle:
    plistlib.dump(info, handle)
PY

tests=$((tests + 1))
set +e
archive_output="$(python3 "$TOOL" inspect-archive --archive "$archive" --manifest "$manifest")"
archive_status=$?
set -e
if [ "$archive_status" -ne 0 ] && printf '%s\n' "$archive_output" | grep -qx E_ARCHIVE_BUILDCOMMITSHA_MISMATCH; then
  printf 'ok %s - archive mismatch is fail-closed\n' "$tests"
else
  printf 'not ok %s - archive mismatch was not detected\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
if python3 -m json.tool "$ROOT/Config/ReleaseManifest.schema.json" >/dev/null \
  && python3 -m json.tool "$ROOT/Config/ReleaseManifest.template.json" >/dev/null; then
  printf 'ok %s - manifest schema and template parse\n' "$tests"
else
  printf 'not ok %s - manifest schema/template invalid JSON\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
debug_refs="$(grep -c 'baseConfigurationReference = CFA100000000000000000002' "$PROJECT" || true)"
release_refs="$(grep -c 'baseConfigurationReference = CFA100000000000000000004' "$PROJECT" || true)"
staging_refs="$(grep -c 'baseConfigurationReference = CFA100000000000000000003' "$PROJECT" || true)"
secret_refs="$(grep -c 'baseConfigurationReference.*Secrets.xcconfig' "$PROJECT" || true)"
environment_refs="$(grep -c 'baseConfigurationReference = CFA10000000000000000000[234]' "$PROJECT" || true)"
staging_configs="$(grep -c 'name = Staging;' "$PROJECT" || true)"
if [ "$debug_refs" = "1" ] && [ "$staging_refs" = "1" ] && [ "$release_refs" = "1" ] \
  && [ "$environment_refs" = "3" ] && [ "$staging_configs" = "8" ] \
  && [ "$secret_refs" = "0" ]; then
  printf 'ok %s - only app Debug/Staging/Release use environment xcconfigs\n' "$tests"
else
  printf 'not ok %s - xcconfig project ownership is incorrect\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
export_policy="$(python3 - "$EXPORT_OPTIONS" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    options = plistlib.load(handle)
print(
    f"{options.get('method', '')}|{options.get('destination', '')}|"
    f"{str(options.get('uploadSymbols', True)).lower()}"
)
PY
)"
if [ "$export_policy" = "app-store-connect|export|false" ]; then
  printf 'ok %s - export options use current archive-only policy\n' "$tests"
else
  printf 'not ok %s - export options are deprecated or permit upload\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
cleanup_line="$(grep -n 'Remove signing material before artifact publication' \
  "$RELEASE_WORKFLOW" | cut -d: -f1)"
artifact_line="$(grep -n 'uses: actions/upload-artifact@' \
  "$RELEASE_WORKFLOW" | cut -d: -f1)"
if grep -Fq 'checked_out_commit="$(git rev-parse '\''HEAD^{commit}'\'')"' "$RELEASE_WORKFLOW" \
  && grep -Fq 'main_commit="$(git rev-parse '\''origin/main^{commit}'\'')"' "$RELEASE_WORKFLOW" \
  && grep -Fq 'if [ "$checked_out_commit" != "$main_commit" ]; then' "$RELEASE_WORKFLOW" \
  && grep -Fq 'commit_sha="$(git rev-parse '\''HEAD^{commit}'\'')"' "$RELEASE_WORKFLOW" \
  && grep -Fq 'E_RELEASE_COMMIT_NOT_MAIN_TIP' "$RELEASE_WORKFLOW" \
  && grep -Fq 'E_TESTFLIGHT_UPLOAD_NOT_AUTHORIZED' "$RELEASE_WORKFLOW" \
  && grep -Fq 'BACKEND_APPLE_APP_ID: ${{ vars.BACKEND_APPLE_APP_ID }}' \
    "$RELEASE_WORKFLOW" \
  && grep -Fq 'ChapterFlow.ipa.sha256' "$RELEASE_WORKFLOW" \
  && grep -Fq 'release_config.py inspect-app' "$RELEASE_WORKFLOW" \
  && grep -Fq 'E_IPA_SIGNING_TEAM_MISMATCH' "$RELEASE_WORKFLOW" \
  && grep -Fq 'E_IPA_PROVISIONING_IDENTITY_MISMATCH' "$RELEASE_WORKFLOW" \
  && grep -Fq 'path: ${{ runner.temp }}/validated-release' "$RELEASE_WORKFLOW" \
  && [ -n "$cleanup_line" ] && [ -n "$artifact_line" ] \
  && [ "$cleanup_line" -lt "$artifact_line" ] \
  && ! grep -Eq 'uses: actions/(checkout|cache|upload-artifact)@v[0-9]' \
    "$RELEASE_WORKFLOW" "$PR_WORKFLOW" \
  && ! grep -Eiq -- '--upload-app|--upload-package|upload_to_testflight|pilot upload|iTMSTransporter|notarytool submit' \
    "$RELEASE_WORKFLOW" \
  && ! grep -Fq 'upload-testflight:' "$RELEASE_WORKFLOW" \
  && ! grep -Fq 'xcrun altool --upload-app' "$RELEASE_WORKFLOW"; then
  printf 'ok %s - workflow is pinned, post-export inspected, cleaned, and archive-only\n' "$tests"
else
  printf 'not ok %s - workflow upload or provenance guard is unsafe\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
pr_snapshot_policy="$(python3 - "$PR_WORKFLOW" <<'PY'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    workflow = handle.read()


def job_body(name: str) -> str:
    match = re.search(
        rf"^  {re.escape(name)}:\n(?P<body>.*?)(?=^  [a-z][a-z0-9-]*:\n|\Z)",
        workflow,
        flags=re.MULTILINE | re.DOTALL,
    )
    return match.group("body") if match else ""


build = job_body("build-and-test")
snapshots = job_body("macos-release-snapshots")
uitest = job_body("uitest")

checks = (
    'if [[ "$pkg" == "AppFeature" || "$pkg" == "PaywallFeature" ]]; then' in build,
    build.count("test_command+=(--skip ReleaseVisualSnapshotTests)") == 1,
    "for pkg in AppFeature PaywallFeature; do" in snapshots,
    '--filter "${pkg}Tests.ReleaseVisualSnapshotTests"' in snapshots,
    'grep -Ec "^${pkg}Tests\\\\.ReleaseVisualSnapshotTests/"' in snapshots,
    "if [[ \"$selected\" -ne 2 ]]; then" in snapshots,
    "if: failure()" in snapshots,
    "*-macos.png" in snapshots,
    "*-macos-FAIL.png" in snapshots,
    re.search(r"^    needs: build-and-test$", snapshots, re.MULTILINE) is not None,
    re.search(r"^    needs: build-and-test$", uitest, re.MULTILINE) is not None,
    "macos-release-snapshots" not in uitest,
)
print("true" if all(checks) else "false")
PY
)"
if [ "$pr_snapshot_policy" = "true" ]; then
  printf 'ok %s - PR workflow isolates, counts, gates, and retains macOS snapshots\n' "$tests"
else
  printf 'not ok %s - PR workflow macOS snapshot policy is incomplete\n' "$tests"
  failures=$((failures + 1))
fi

tests=$((tests + 1))
checksum_dir="$tmp/checksum"
mkdir "$checksum_dir"
printf 'synthetic IPA bytes' > "$checksum_dir/ChapterFlow.ipa"
(
  cd "$checksum_dir"
  shasum -a 256 ChapterFlow.ipa > ChapterFlow.ipa.sha256
)
checksum_valid=false
if (
  cd "$checksum_dir"
  shasum -a 256 -c ChapterFlow.ipa.sha256 >/dev/null
); then
  checksum_valid=true
fi
printf 'tampered' >> "$checksum_dir/ChapterFlow.ipa"
set +e
(
  cd "$checksum_dir"
  shasum -a 256 -c ChapterFlow.ipa.sha256 >/dev/null 2>&1
)
tampered_status=$?
set -e
if [ "$checksum_valid" = true ] && [ "$tampered_status" -ne 0 ]; then
  printf 'ok %s - retained IPA digest detects artifact mutation\n' "$tests"
else
  printf 'not ok %s - retained IPA digest did not fail closed\n' "$tests"
  failures=$((failures + 1))
fi

printf '1..%s\n' "$tests"
if [ "$failures" -ne 0 ]; then
  printf '%s release-config tests failed\n' "$failures"
  exit 1
fi
printf 'all release-config tests passed\n'
