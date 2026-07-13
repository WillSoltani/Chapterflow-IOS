#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_path="$repo_root/Packages/CoreKit"
scratch_path="${COREKIT_RELEASE_SCRATCH_PATH:-$package_path/.build}"
probe_directory="$(mktemp -d "${TMPDIR:-/tmp}/chapterflow-wp-dev-01.XXXXXX")"
trap 'rm -rf "$probe_directory"' EXIT

swift build \
  --package-path "$package_path" \
  --configuration release \
  --scratch-path "$scratch_path"

binary_path="$(
  swift build \
    --package-path "$package_path" \
    --configuration release \
    --scratch-path "$scratch_path" \
    --show-bin-path
)"

cat > "$probe_directory/approved-record.swift" <<'SWIFT'
import CoreKit

func makeApprovedRecord() -> AppConfigurationDiagnosticRecord {
    AppConfigurationDiagnosticRecord(
        status: .valid,
        buildConfiguration: .nonDebug,
        issues: [],
        liveServicesConstructed: true
    )
}
SWIFT

xcrun swiftc -typecheck \
  -I "$binary_path/Modules" \
  -F "$binary_path" \
  "$probe_directory/approved-record.swift"

cat > "$probe_directory/overlay-consumer.swift" <<'SWIFT'
import CoreKit

func applyOverlay(_ source: AppConfig, requiredServices: AppConfig) {
    _ = source.applyingHermeticServiceOverlay(requiredServices)
}
SWIFT

cat > "$probe_directory/custom-support-code-consumer.swift" <<'SWIFT'
import CoreKit

func makeCustomSupportRecord() {
    _ = AppConfigurationDiagnosticRecord(
        status: .invalid,
        buildConfiguration: .nonDebug,
        issues: [],
        liveServicesConstructed: false,
        supportCode: "private-caller-controlled-value"
    )
}
SWIFT

failures=0

expect_unavailable() {
  local label="$1"
  local source="$2"
  local expected_diagnostic="$3"
  local output="$probe_directory/$label.log"

  if xcrun swiftc -typecheck \
    -I "$binary_path/Modules" \
    -F "$binary_path" \
    "$source" > "$output" 2>&1; then
    echo "ERROR: $label unexpectedly compiled in a non-Debug consumer"
    failures=$((failures + 1))
  elif grep -Fq "$expected_diagnostic" "$output"; then
    echo "PASS: $label is unavailable to a non-Debug consumer"
  else
    echo "ERROR: $label failed for an unexpected reason"
    sed -n '1,120p' "$output"
    failures=$((failures + 1))
  fi
}

expect_unavailable \
  "hermetic overlay" \
  "$probe_directory/overlay-consumer.swift" \
  "has no member 'applyingHermeticServiceOverlay'"

expect_unavailable \
  "caller-controlled support code" \
  "$probe_directory/custom-support-code-consumer.swift" \
  "extra argument 'supportCode' in call"

if (( failures > 0 )); then
  exit 1
fi

echo "PASS: WP-DEV-01 non-Debug compile boundaries are enforced"
