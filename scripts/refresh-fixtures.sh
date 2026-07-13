#!/usr/bin/env bash
# Regenerates the synthetic native-iOS contract bundle from backend source.
#
# This script never calls a deployed service and never accepts an API token. The
# ChapterFlow backend owns the serializer-derived bundle; iOS commits a verbatim
# copy so Swift contract tests are hermetic.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/refresh-fixtures.sh [--check]

Environment:
  CHAPTERFLOW_BACKEND_REPO  Path to a ChapterFlow backend checkout.
                            Default: sibling directory ../ChapterFlow
  CONTRACT_SOURCE_REVISION Exact backend HEAD used to generate the iOS bundle.
                            Omit only while the backend change is uncommitted.
  CONTRACT_SOURCE_REVISION_PHASE
                            committed_backend_branch while the companion PR is
                            open, or merged_backend after that revision reaches
                            backend main. Required with CONTRACT_SOURCE_REVISION.

Options:
  --check  Regenerate and fail if the committed iOS bundle differs.
USAGE
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
backend_bundle="$backend_repo/$relative_bundle"
backend_inventory_manifest="$backend_repo/$relative_inventory_manifest"
ios_bundle="$repo_root/$relative_bundle"
ios_inventory_manifest="$repo_root/$relative_inventory_manifest"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 69
  }
}

require_command jq
require_command npm
require_command rg
require_command shasum

if [[ ! -f "$backend_repo/package.json" ]]; then
  echo "error: backend checkout not found at $backend_repo" >&2
  exit 66
fi

tmp_bundle=$(mktemp "${TMPDIR:-/tmp}/chapterflow-native-contract.XXXXXX.json")
tmp_strings=$(mktemp "${TMPDIR:-/tmp}/chapterflow-native-contract-strings.XXXXXX.txt")
tmp_source_producers=$(mktemp "${TMPDIR:-/tmp}/chapterflow-native-contract-source.XXXXXX.txt")
tmp_bundle_producers=$(mktemp "${TMPDIR:-/tmp}/chapterflow-native-contract-bundle.XXXXXX.txt")
trap 'rm -f "$tmp_bundle" "$tmp_strings" "$tmp_source_producers" "$tmp_bundle_producers"' EXIT

generate_backend_bundle() {
  npm --prefix "$backend_repo" run contract:native:generate
  if [[ ! -f "$backend_bundle" ]]; then
    echo "error: backend generator did not write $backend_bundle" >&2
    exit 65
  fi
  if [[ ! -f "$backend_inventory_manifest" ]]; then
    echo "error: backend iOS source inventory manifest is missing: $backend_inventory_manifest" >&2
    exit 65
  fi
  jq -e . "$backend_bundle" >/dev/null
  jq -e . "$backend_inventory_manifest" >/dev/null
}

echo "Generating backend-owned native contract bundle..."
generate_backend_bundle
cp "$backend_bundle" "$tmp_bundle"
first_digest=$(shasum -a 256 "$tmp_bundle" | awk '{print $1}')

echo "Regenerating to prove byte determinism..."
generate_backend_bundle
second_digest=$(shasum -a 256 "$backend_bundle" | awk '{print $1}')
if [[ "$first_digest" != "$second_digest" ]] || ! cmp -s "$tmp_bundle" "$backend_bundle"; then
  echo "error: native contract generation is not byte deterministic" >&2
  exit 1
fi

inventory_manifest_digest=$(shasum -a 256 "$backend_inventory_manifest" | awk '{print $1}')
recorded_inventory_digest=$(jq -r '.inventory.iosSourceEvidence.manifestSha256' "$backend_bundle")
if [[ "$inventory_manifest_digest" != "$recorded_inventory_digest" ]]; then
  echo "error: bundle provenance does not match the iOS source inventory manifest" >&2
  exit 1
fi

recorded_revision=$(jq -r '.provenance.sourceRevision // ""' "$backend_bundle")
recorded_phase=$(jq -r '.provenance.sourceRevisionPhase' "$backend_bundle")
requested_revision=${CONTRACT_SOURCE_REVISION:-}
requested_phase=${CONTRACT_SOURCE_REVISION_PHASE:-}
if [[ -n "$requested_revision" || -n "$requested_phase" ]]; then
  if [[ -z "$requested_revision" || -z "$requested_phase" ]]; then
    echo "error: CONTRACT_SOURCE_REVISION and CONTRACT_SOURCE_REVISION_PHASE must be provided together" >&2
    exit 1
  fi
  if [[ ! "$requested_revision" =~ ^[0-9a-f]{40}$ ]]; then
    echo "error: CONTRACT_SOURCE_REVISION must be a full lowercase Git SHA" >&2
    exit 1
  fi
  case "$requested_phase" in
    committed_backend_branch|merged_backend) ;;
    *)
      echo "error: unsupported CONTRACT_SOURCE_REVISION_PHASE: $requested_phase" >&2
      exit 1
      ;;
  esac
  backend_head=$(git -C "$backend_repo" rev-parse HEAD)
  if [[ "$backend_head" != "$requested_revision" ]]; then
    echo "error: backend HEAD $backend_head does not match CONTRACT_SOURCE_REVISION $requested_revision" >&2
    exit 1
  fi
  if [[ "$recorded_revision" != "$requested_revision" || "$recorded_phase" != "$requested_phase" ]]; then
    echo "error: generated provenance does not record the requested revision and phase" >&2
    exit 1
  fi
elif [[ -n "$recorded_revision" || "$recorded_phase" != "uncommitted_backend" ]]; then
  echo "error: draft generation without CONTRACT_SOURCE_REVISION must remain uncommitted_backend" >&2
  exit 1
fi
if [[ "$mode" == "check" && -z "$requested_revision" ]]; then
  echo "error: --check requires committed backend revision provenance" >&2
  exit 1
fi

unique_operations=$(jq -r '.inventory.uniqueOperationCount' "$backend_bundle")
native_producers=$(jq -r '.inventory.nativeProducerCount' "$backend_bundle")
matrix_rows=$(jq -r '.inventory.matrixRowCount' "$backend_bundle")
if [[ "$unique_operations" != "83" || "$matrix_rows" != "29" ]]; then
  echo "error: expected 83 native operations and the exact 29-row matrix; got $unique_operations/$matrix_rows" >&2
  exit 1
fi

# Count every production route producer from current Swift source. Factories are
# keyed by definition (so the two submitQuiz overloads remain distinct); the
# test-only getSession factory is explicitly excluded. Direct Endpoint builders
# and the CoreKit analytics path producers are counted separately.
factory_count=$(
  rg -n '^\s*(public\s+)?static func ' \
    "$repo_root/Packages" \
    --glob '**/Sources/**/Endpoint*.swift' \
    --glob '**/Sources/**/BillingEndpoints.swift' \
    | rg -v 'getSession\(' \
    | wc -l \
    | tr -d ' '
)
direct_endpoint_count=$(
  rg -n '\bEndpoint\(' "$repo_root/Packages" \
    --glob '**/Sources/**/*.swift' \
    --glob '!**/Endpoint*.swift' \
    --glob '!**/Endpoints*.swift' \
    --glob '!**/BillingEndpoints.swift' \
    | wc -l \
    | tr -d ' '
)
analytics_count=$(
  rg -n 'static let (track|beacon) = "/book/me/analytics/' \
    "$repo_root/Packages/CoreKit/Sources/CoreKit/Analytics/AnalyticsClient.swift" \
    | wc -l \
    | tr -d ' '
)
discovered_producers=$((factory_count + direct_endpoint_count + analytics_count))
if [[ "$native_producers" != "$discovered_producers" ]]; then
  echo "error: bundle declares $native_producers native producers; Swift source has $discovered_producers" >&2
  echo "       factories=$factory_count direct-endpoints=$direct_endpoint_count analytics=$analytics_count" >&2
  exit 1
fi

# Compare the exact producer symbol and source path recorded in the bundle
# against current production Swift. Line numbers remain human evidence tied to
# the pinned iOS source revision; ignoring them here permits non-contractual line
# movement while still preventing count-preserving add/remove/rename drift. The two submitQuiz
# producers share a Swift function name, so their source paths define the
# stable online/sync variant suffixes used by the bundle.
{
  while IFS=: read -r path line source; do
    relative_path=${path#"$repo_root/"}
    if [[ "$source" =~ static[[:space:]]+func[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
      symbol=${BASH_REMATCH[1]}
    else
      echo "error: could not parse endpoint factory at $relative_path:$line" >&2
      exit 1
    fi
    [[ "$symbol" == "getSession" ]] && continue
    if [[ "$symbol" == "submitQuiz" ]]; then
      case "$relative_path" in
        Packages/QuizFeature/*) symbol="submitQuiz.online" ;;
        */Endpoint+Sync.swift) symbol="submitQuiz.sync" ;;
        *)
          echo "error: unclassified submitQuiz producer at $relative_path:$line" >&2
          exit 1
          ;;
      esac
    fi
    printf '%s@%s\n' "$symbol" "$relative_path"
  done < <(
    rg -n -H '^\s*(public\s+)?static func ' \
      "$repo_root/Packages" \
      --glob '**/Sources/**/Endpoint*.swift' \
      --glob '**/Sources/**/BillingEndpoints.swift'
  )

  while IFS=: read -r path line _; do
    relative_path=${path#"$repo_root/"}
    case "$relative_path" in
      Packages/PaywallFeature/Sources/PaywallFeature/LiveEntitlementRepository.swift)
        symbol="LiveEntitlementRepository.directEndpoint"
        ;;
      Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/ScenarioRepository.swift)
        symbol="ScenarioRepository.replayDirectEndpoint"
        ;;
      *)
        echo "error: unclassified direct Endpoint producer at $relative_path:$line" >&2
        exit 1
        ;;
    esac
    printf '%s@%s\n' "$symbol" "$relative_path"
  done < <(
    rg -n -H '\bEndpoint\(' "$repo_root/Packages" \
      --glob '**/Sources/**/*.swift' \
      --glob '!**/Endpoint*.swift' \
      --glob '!**/Endpoints*.swift' \
      --glob '!**/BillingEndpoints.swift'
  )

  while IFS=: read -r path line source; do
    relative_path=${path#"$repo_root/"}
    if [[ "$source" =~ static[[:space:]]+let[[:space:]]+(track|beacon) ]]; then
      symbol="URLSessionAnalyticsTransport.Path.${BASH_REMATCH[1]}"
    else
      echo "error: could not parse analytics route producer at $relative_path:$line" >&2
      exit 1
    fi
    printf '%s@%s\n' "$symbol" "$relative_path"
  done < <(
    rg -n -H 'static let (track|beacon) = "/book/me/analytics/' \
      "$repo_root/Packages/CoreKit/Sources/CoreKit/Analytics/AnalyticsClient.swift"
  )
} | LC_ALL=C sort > "$tmp_source_producers"

jq -r '.operations[].nativeRequestFixtures[].producerEvidence[]' \
  "$backend_bundle" | sed -E 's/:[0-9]+$//' | LC_ALL=C sort > "$tmp_bundle_producers"

if [[ "$(wc -l < "$tmp_source_producers" | tr -d ' ')" != "$native_producers" ]]; then
  echo "error: exact source producer inventory does not contain $native_producers entries" >&2
  exit 1
fi
if ! cmp -s "$tmp_source_producers" "$tmp_bundle_producers"; then
  echo "error: bundle producer evidence has drifted from production Swift source" >&2
  diff -u "$tmp_bundle_producers" "$tmp_source_producers" || true
  exit 1
fi

# Scan JSON string values, not field names. The canonical credential placeholder
# is allowed; credential-shaped values and private data are not.
jq -r '.. | strings' "$backend_bundle" > "$tmp_strings"
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
  echo "error: generated contract bundle contains a secret- or PII-shaped value" >&2
  exit 1
fi

if jq -r '.. | strings | select(test("^https?://"))' "$backend_bundle" \
  | rg -n -v '^https://(example\.invalid|apps\.apple\.com)(/|$)'; then
  echo "error: generated contract bundle contains a URL outside the synthetic allowlist" >&2
  exit 1
fi

if [[ "$mode" == "check" ]]; then
  if [[ ! -f "$ios_bundle" ]]; then
    echo "error: committed iOS bundle is missing: $ios_bundle" >&2
    exit 1
  fi
  if ! cmp -s "$backend_bundle" "$ios_bundle"; then
    echo "error: committed iOS contract bundle has drifted from backend generation" >&2
    diff -u "$ios_bundle" "$backend_bundle" || true
    exit 1
  fi
  if [[ ! -f "$ios_inventory_manifest" ]] || ! cmp -s "$backend_inventory_manifest" "$ios_inventory_manifest"; then
    echo "error: committed iOS source inventory manifest has drifted from backend ownership" >&2
    if [[ -f "$ios_inventory_manifest" ]]; then
      diff -u "$ios_inventory_manifest" "$backend_inventory_manifest" || true
    fi
    exit 1
  fi
  echo "Contract bundle is current ($second_digest; inventory $inventory_manifest_digest)."
  exit 0
fi

mkdir -p "$(dirname "$ios_bundle")"
cp "$backend_bundle" "$ios_bundle"
cp "$backend_inventory_manifest" "$ios_inventory_manifest"
echo "Updated $relative_bundle ($second_digest)."
echo "Updated $relative_inventory_manifest ($inventory_manifest_digest)."
