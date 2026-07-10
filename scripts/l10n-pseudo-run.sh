#!/usr/bin/env bash
#
# scripts/l10n-pseudo-run.sh — P10.11 Localization QA
#
# Builds, installs, and launches ChapterFlow in an iOS Simulator under an OS
# pseudolanguage so you can eyeball two things across every screen:
#   • MISSING KEYS  — any text that renders in plain (un-accented) English is a
#     hardcoded literal that never made it into a String Catalog.
#   • TRUNCATION    — pseudolanguages are longer than English; clipped or
#     overflowing text reveals fragile fixed-width layout.
#
# Pseudolanguages:
#   en-XA  accented + ~40% longer   (default) — width / missing-key sweep
#   ar-XB  bidi, double-length, RTL           — right-to-left mirroring sweep
#
# It launches with the UI-test stub server + auth bypass so the app is navigable
# without real credentials or network (same hooks the XCUITests use).
#
# Usage:
#   scripts/l10n-pseudo-run.sh            # en-XA
#   scripts/l10n-pseudo-run.sh ar-XB      # RTL
#   DEVICE="iPhone 16 Pro" scripts/l10n-pseudo-run.sh
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

PSEUDO="${1:-en-XA}"
DEVICE="${DEVICE:-iPhone 16 Pro}"
BUNDLE_ID="com.chapterflow.ios"
DERIVED="$REPO/.l10n-pseudo-derived"

[[ -f Secrets.xcconfig ]] || cp Secrets.example.xcconfig Secrets.xcconfig

echo "▸ Booting simulator: $DEVICE"
SIM_ID="$(xcrun simctl list devices available -j | python3 -c "
import sys, json
d = json.load(sys.stdin)
for rt, devs in sorted(d['devices'].items(), reverse=True):
    for dev in devs:
        if dev.get('isAvailable') and dev['name'] == '$DEVICE':
            print(dev['udid']); raise SystemExit(0)
raise SystemExit('device not found: $DEVICE')
")"
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_ID" -b

echo "▸ Building app for the simulator…"
xcodebuild build \
  -project ChapterFlow.xcodeproj -scheme ChapterFlow \
  -configuration Debug -destination "id=$SIM_ID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation -skipMacroValidation | tail -3

APP="$(find "$DERIVED/Build/Products" -name 'ChapterFlow.app' -maxdepth 3 | head -1)"
[[ -n "$APP" ]] || { echo "✗ ChapterFlow.app not found"; exit 1; }

echo "▸ Installing + launching under pseudolanguage: $PSEUDO"
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch --console-pty \
  --terminate-running-process "$SIM_ID" "$BUNDLE_ID" \
  -AppleLanguages "($PSEUDO)" \
  -AppleLocale "$PSEUDO" \
  -CF_STUB_SERVER 1 \
  -CF_UITEST_BYPASS_AUTH 1 &

sleep 6
SHOT="$REPO/.l10n-pseudo-$PSEUDO.png"
xcrun simctl io "$SIM_ID" screenshot "$SHOT" && echo "▸ Screenshot: $SHOT"
echo "▸ App is running under $PSEUDO — navigate every tab and check for plain-English text (missing keys) and clipped text (truncation)."
