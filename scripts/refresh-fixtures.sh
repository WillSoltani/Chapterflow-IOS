#!/usr/bin/env bash
# Verifies the iOS-owned native inventory and refreshes the backend-owned
# synthetic contract overlay without mutating either repository's source
# authority. No deployed service is called and no credential is accepted.

set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: scripts/refresh-fixtures.sh [--check]' \
    '' \
    'Required environment:' \
    '  CHAPTERFLOW_BACKEND_REPO       Exact local backend checkout.' \
    '  CONTRACT_SOURCE_REVISION      Full backend commit SHA.' \
    '  CONTRACT_SOURCE_REVISION_PHASE' \
    '                                committed_backend_branch or merged_backend.' \
    '  CONTRACT_TRUSTED_MAIN_REF     Explicit trusted ref, normally' \
    '                                refs/remotes/origin/main.' \
    '' \
    'The iOS-owned manifest is verified in place and is never copied from the backend.'
}

mode="refresh"
case "${1:-}" in
  "") ;;
  --check) mode="check" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
backend_repo=${CHAPTERFLOW_BACKEND_REPO:-"$(dirname "$repo_root")/ChapterFlow"}
relative_bundle="contracts/native-ios/v1/contract-bundle.json"
relative_inventory_manifest="contracts/native-ios/v1/ios-source-inventory-manifest.json"
relative_inventory_verifier="scripts/contracts/verify_ios_incremental_contract_drift.py"
backend_inventory_manifest="$backend_repo/$relative_inventory_manifest"
ios_bundle="$repo_root/$relative_bundle"
ios_inventory_manifest="$repo_root/$relative_inventory_manifest"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 69
  }
}

for command in cmp git jq npm python3 rg shasum; do
  require_command "$command"
done

if [[ ! -f "$backend_repo/package.json" ]]; then
  echo "error: backend checkout not found at $backend_repo" >&2
  exit 66
fi
if [[ ! -f "$ios_inventory_manifest" ]]; then
  echo "error: committed iOS inventory manifest is missing: $ios_inventory_manifest" >&2
  exit 66
fi
if [[ ! -f "$backend_inventory_manifest" ]]; then
  echo "error: backend copy of the iOS inventory manifest is missing: $backend_inventory_manifest" >&2
  exit 66
fi

source_revision=${CONTRACT_SOURCE_REVISION:-}
source_phase=${CONTRACT_SOURCE_REVISION_PHASE:-}
trusted_main_ref=${CONTRACT_TRUSTED_MAIN_REF:-}
if [[ -z "$source_revision" || -z "$source_phase" || -z "$trusted_main_ref" ]]; then
  echo "error: CONTRACT_SOURCE_REVISION, CONTRACT_SOURCE_REVISION_PHASE, and CONTRACT_TRUSTED_MAIN_REF are required" >&2
  exit 64
fi
if [[ ! "$source_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: CONTRACT_SOURCE_REVISION must be a full lowercase Git SHA" >&2
  exit 64
fi
case "$source_phase" in
  committed_backend_branch|merged_backend) ;;
  *)
    echo "error: unsupported CONTRACT_SOURCE_REVISION_PHASE: $source_phase" >&2
    exit 64
    ;;
esac
if [[ ! "$trusted_main_ref" =~ ^refs/(heads|remotes)/[A-Za-z0-9._/-]+$ ]]; then
  echo "error: CONTRACT_TRUSTED_MAIN_REF must be an explicit refs/heads/... or refs/remotes/... ref" >&2
  exit 64
fi

ios_inventory_revision=$(jq -r '.iosSourceRevision // ""' "$ios_inventory_manifest")
if [[ ! "$ios_inventory_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: iOS inventory must pin a committed 40-character iosSourceRevision" >&2
  exit 1
fi

echo "Verifying historical iOS provenance and current worktree contract semantics..."
PYTHONDONTWRITEBYTECODE=1 python3 "$repo_root/$relative_inventory_verifier" \
  --repo-root "$repo_root" \
  --manifest "$relative_inventory_manifest"

if ! cmp -s "$ios_inventory_manifest" "$backend_inventory_manifest"; then
  echo "error: backend must consume a byte-identical copy of the iOS-owned inventory manifest" >&2
  diff -u "$backend_inventory_manifest" "$ios_inventory_manifest" || true
  exit 1
fi
inventory_digest=$(shasum -a 256 "$ios_inventory_manifest" | awk '{print $1}')

backend_head=$(git -C "$backend_repo" rev-parse --verify HEAD)
if [[ "$backend_head" != "$source_revision" ]]; then
  echo "error: backend HEAD $backend_head does not match CONTRACT_SOURCE_REVISION $source_revision" >&2
  exit 1
fi

CHAPTERFLOW_BACKEND_REPO="$backend_repo" \
  CONTRACT_SOURCE_REVISION="$source_revision" \
  CONTRACT_SOURCE_REVISION_PHASE="$source_phase" \
  CONTRACT_TRUSTED_MAIN_REF="$trusted_main_ref" \
  bash "$repo_root/scripts/verify-backend-contract-provenance.sh"

echo "Verifying the backend's self-reference-safe canonical artifact..."
CONTRACT_SOURCE_REVISION='' \
  CONTRACT_SOURCE_REVISION_PHASE='' \
  CONTRACT_TRUSTED_MAIN_REF='' \
  npm --prefix "$backend_repo" run contract:native:check

tmp_first=$(mktemp "${TMPDIR:-/tmp}/chapterflow-native-contract-overlay.XXXXXX")
tmp_second=$(mktemp "${TMPDIR:-/tmp}/chapterflow-native-contract-overlay.XXXXXX")
tmp_strings=$(mktemp "${TMPDIR:-/tmp}/chapterflow-native-contract-strings.XXXXXX")
trap 'rm -f "$tmp_first" "$tmp_second" "$tmp_strings"' EXIT

generate_overlay() {
  local output=$1
  CONTRACT_SOURCE_REVISION="$source_revision" \
    CONTRACT_SOURCE_REVISION_PHASE="$source_phase" \
    CONTRACT_TRUSTED_MAIN_REF="$trusted_main_ref" \
    npm --prefix "$backend_repo" run contract:native:generate -- --output "$output"
}

echo "Generating the committed backend overlay twice from exact fenced bytes..."
generate_overlay "$tmp_first"
generate_overlay "$tmp_second"
if ! cmp -s "$tmp_first" "$tmp_second"; then
  echo "error: committed native contract overlay is not byte deterministic" >&2
  diff -u "$tmp_first" "$tmp_second" || true
  exit 1
fi
jq -e . "$tmp_first" >/dev/null
overlay_digest=$(shasum -a 256 "$tmp_first" | awk '{print $1}')

recorded_revision=$(jq -r '.provenance.sourceRevision // ""' "$tmp_first")
recorded_phase=$(jq -r '.provenance.sourceRevisionPhase // ""' "$tmp_first")
recorded_main_ref=$(jq -r '.provenance.committedInputTree.trustedMainRef // ""' "$tmp_first")
recorded_manifest_digest=$(jq -r '.inventory.iosSourceEvidence.manifestSha256 // ""' "$tmp_first")
if [[ "$recorded_revision" != "$source_revision" || "$recorded_phase" != "$source_phase" ]]; then
  echo "error: generated overlay does not record the requested backend revision and phase" >&2
  exit 1
fi
if [[ "$recorded_main_ref" != "$trusted_main_ref" ]]; then
  echo "error: generated overlay does not record the explicit trusted-main ref" >&2
  exit 1
fi
if [[ "$recorded_manifest_digest" != "$inventory_digest" ]]; then
  echo "error: generated overlay is not bound to the iOS-owned inventory manifest bytes" >&2
  exit 1
fi

unique_operations=$(jq -r '.inventory.uniqueOperationCount' "$tmp_first")
native_producers=$(jq -r '.inventory.nativeProducerCount' "$tmp_first")
matrix_rows=$(jq -r '.inventory.matrixRowCount' "$tmp_first")
relation_count=$(jq -r '.inventory.iosSourceEvidence.relationalRecordCount // 0' "$tmp_first")
if [[ "$unique_operations" != "83" || "$native_producers" != "92" || \
      "$matrix_rows" != "29" || "$relation_count" != "92" ]]; then
  echo "error: expected exact 83/92/29 inventory with 92 relational records; got $unique_operations/$native_producers/$matrix_rows/$relation_count" >&2
  exit 1
fi

# Scan JSON values, not keys. Synthetic placeholders and the public App Store
# URL are allowed; credential-shaped or private values are not.
jq -r '.. | strings' "$tmp_first" "$ios_inventory_manifest" > "$tmp_strings"
if rg -n -i \
  -e '(^|[^A-Za-z0-9])[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}([^A-Za-z0-9]|$)' \
  -e 'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}' \
  -e 'Bearer[[:space:]]+eyJ' \
  -e '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'ASIA[0-9A-Z]{16}' \
  -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
  -e 'sk-[A-Za-z0-9_-]{20,}' \
  -e 'AIza[0-9A-Za-z_-]{30,}' \
  -e 'xox[baprs]-[0-9A-Za-z-]{20,}' \
  -e 'X-Amz-(Credential|Signature|Security-Token)=' \
  "$tmp_strings"; then
  echo "error: generated contract evidence contains a secret- or PII-shaped value" >&2
  exit 1
fi
if jq -r '.. | strings | select(test("^https?://"))' "$tmp_first" \
  | rg -n -v '^https://(example\.invalid|apps\.apple\.com)(/|$)'; then
  echo "error: generated contract bundle contains a URL outside the synthetic allowlist" >&2
  exit 1
fi

if [[ "$mode" == "check" ]]; then
  if [[ ! -f "$ios_bundle" ]] || ! cmp -s "$tmp_first" "$ios_bundle"; then
    echo "error: committed iOS contract overlay has drifted from exact backend generation" >&2
    if [[ -f "$ios_bundle" ]]; then
      diff -u "$ios_bundle" "$tmp_first" || true
    fi
    exit 1
  fi
  echo "Contract evidence is current (overlay $overlay_digest; inventory $inventory_digest)."
  exit 0
fi

mkdir -p "$(dirname "$ios_bundle")"
cp "$tmp_first" "$ios_bundle"
echo "Updated $relative_bundle ($overlay_digest)."
echo "Preserved iOS-owned $relative_inventory_manifest ($inventory_digest)."
