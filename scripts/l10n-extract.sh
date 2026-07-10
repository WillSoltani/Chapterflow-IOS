#!/usr/bin/env bash
#
# scripts/l10n-extract.sh — P10.11 Localization
#
# Reproducible String Catalog extraction for ChapterFlow. This script is the
# SOURCE OF TRUTH for the app's localizable strings — re-run it whenever UI text
# changes and commit the resulting *.xcstrings diffs.
#
# WHY A SCRIPT (and not the "Use Compiler to Extract Swift Strings" build
# setting): the app links ~16 local SwiftPM packages. A plain `Text("…")` inside
# a package resolves its LocalizedStringKey against `Bundle.main` (the app), but
# Xcode's in-build extraction only scans a target's OWN sources — it never walks
# linked-package sources. Enabling the build setting would also MUTATE the
# committed .xcstrings during every build (dirty CI trees, noisy diffs) and mark
# every package string "stale". Instead this script compiles the whole app with
# `SWIFT_EMIT_LOC_STRINGS=YES` (the same compiler extraction Xcode uses — so
# interpolations get correct %lld/%@ specifiers, not lightweight-parse %arg) and
# `xcstringstool sync`s the per-file .stringsdata into the right catalog.
#
# Routing:
#   • our local packages + the app target  → ChapterFlow/Localizable.xcstrings
#   • each app-extension target             → <Extension>/Localizable.xcstrings
#   • third-party packages                  → excluded (allowlist)
#   • previews / galleries / debug / diagnostics / fixtures → excluded (denylist)
#
# Usage:
#   scripts/l10n-extract.sh              # full: build + extract
#   SKIP_BUILD=1 scripts/l10n-extract.sh # reuse an existing .l10n-derived build
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

DERIVED="${L10N_DERIVED:-$REPO/.l10n-derived}"
SKIP_BUILD="${SKIP_BUILD:-0}"

# Our local SwiftPM packages (top-level "<Name>.build" dirs in DerivedData).
# Fixtures is intentionally omitted — it is sample/preview data, not shipping UI.
LOCAL_PACKAGES=(
  AIFeature AppFeature AuthKit CoreKit DesignSystem EngagementFeature
  LibraryFeature Models Networking NotificationsFeature OnboardingFeature
  PaywallFeature Persistence QuizFeature ReaderFeature SettingsFeature
  SocialFeature SyncEngine
)

# App-extension targets that render user-facing literals → own catalog.
# (NotificationService renders none, so it is intentionally absent.)
EXTENSION_TARGETS=(ChapterflowWidgets NotificationContent ShareExtension ActionExtension)

# Per-file .stringsdata basenames whose strings are developer-only and must never
# reach translators: SwiftUI previews, the design-system gallery, debug menus,
# diagnostics screens, and sample-data fixtures.
DENY_REGEX='(\+Previews|Gallery|PreviewSupport|DebugMenu|Diagnostics|Fixtures)[^/]*\.stringsdata$'

INT="$DERIVED/Build/Intermediates.noindex"
APP_CATALOG="$REPO/ChapterFlow/Localizable.xcstrings"

echo "▸ ChapterFlow localization extraction"

# ── 1. Compiler extraction build ──────────────────────────────────────────────
if [[ "$SKIP_BUILD" != "1" ]]; then
  [[ -f Secrets.xcconfig ]] || cp Secrets.example.xcconfig Secrets.xcconfig
  echo "▸ Building with SWIFT_EMIT_LOC_STRINGS=YES (this is slow) …"
  xcodebuild build \
    -project ChapterFlow.xcodeproj \
    -scheme ChapterFlow \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    SWIFT_EMIT_LOC_STRINGS=YES \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -skipPackagePluginValidation -skipMacroValidation \
    >/tmp/l10n-extract-build.log 2>&1 \
    || { echo "✗ build failed — see /tmp/l10n-extract-build.log"; tail -20 /tmp/l10n-extract-build.log; exit 1; }
  echo "✓ build complete"
fi

[[ -d "$INT" ]] || { echo "✗ no build products at $INT (run without SKIP_BUILD)"; exit 1; }

# Collect arm64 .stringsdata for one or more build-dir globs, minus the denylist.
# Emits one path per line (nothing when empty). Uses a single find|grep pipeline
# (no per-line printf loop) to stay robust against EINTR under signal load.
collect() {
  local glob
  for glob in "$@"; do
    find $glob -path '*/Objects-normal/arm64/*.stringsdata' 2>/dev/null
  done | grep -Ev "$DENY_REGEX" || true
}

# Reset a catalog to the empty template. We regenerate deterministically from an
# empty file every run: `xcstringstool sync` DELETES untranslated (empty) entries
# that are absent from the given .stringsdata, so re-syncing an already-populated
# catalog against a partial .stringsdata set silently drops keys. Starting empty
# avoids that feedback loop. Translator comments are re-applied afterward from the
# committed sidecar (see step 5), so they survive regeneration.
reset_catalog() {
  printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}\n' > "$1"
}

sync_catalog() {
  local catalog="$1"; shift
  reset_catalog "$catalog"
  if [[ "$#" -eq 0 ]]; then
    echo "  (no strings extracted) — leaving $catalog empty"
    return
  fi
  xcstringstool sync "$catalog" --stringsdata "$@"
  echo "  synced $(xcrun xcstringstool print "$catalog" 2>/dev/null | grep -c . || true) keys → ${catalog#"$REPO"/}"
}

# ── 2. App catalog: local packages + app target ──────────────────────────────
echo "▸ App catalog"
app_globs=("$INT/ChapterFlow.build/Debug-iphonesimulator/ChapterFlow.build")
for pkg in "${LOCAL_PACKAGES[@]}"; do
  app_globs+=("$INT/$pkg.build/Debug-iphonesimulator")
done
APP_DATA=()
while IFS= read -r line; do APP_DATA+=("$line"); done < <(collect "${app_globs[@]}")
sync_catalog "$APP_CATALOG" ${APP_DATA[@]+"${APP_DATA[@]}"}

# ── 3. Extension catalogs ────────────────────────────────────────────────────
for ext in "${EXTENSION_TARGETS[@]}"; do
  echo "▸ $ext catalog"
  EXT_DATA=()
  while IFS= read -r line; do EXT_DATA+=("$line"); done < <(collect "$INT/ChapterFlow.build/Debug-iphonesimulator/$ext.build")
  sync_catalog "$REPO/$ext/Localizable.xcstrings" ${EXT_DATA[@]+"${EXT_DATA[@]}"}
done

# ── 4. Strip #Preview-only demo strings ──────────────────────────────────────
# Compiler extraction also captures literal Text() inside #Preview blocks (demo
# text that must never reach translators). Remove any key that appears ONLY in
# previews (conservative — anything used by shipping code is kept).
echo "▸ Filtering #Preview-only keys"
python3 "$REPO/scripts/l10n-filter-previews.py" \
  --catalog "$APP_CATALOG" \
  $(for ext in "${EXTENSION_TARGETS[@]}"; do echo --catalog "$REPO/$ext/Localizable.xcstrings"; done) \
  --source "$REPO/Packages" \
  --source "$REPO/ChapterFlow" \
  $(for ext in "${EXTENSION_TARGETS[@]}"; do echo --source "$REPO/$ext"; done) \
  --comments "$REPO/scripts/l10n-comments.json"

echo "✓ done. Review the .xcstrings diffs, then commit."
