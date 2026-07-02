#!/usr/bin/env bash
# scripts/refresh-fixtures.sh
#
# Fetches fresh JSON responses from the live ChapterFlow API and writes them
# into the fixture resource directories consumed by the RF2 evolution tests.
#
# Required environment variables:
#   CF_CI_TOKEN   — valid Cognito id_token for the CI test account
#   API_BASE_URL  — ChapterFlow API base URL (e.g. https://api.chapterflow.com)
#                   Falls back to the value embedded in Secrets.xcconfig.
#
# Run locally:
#   CF_CI_TOKEN=<token> API_BASE_URL=<url> bash scripts/refresh-fixtures.sh
#
# Edit the FIXTURES array when new fixture files are added.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

# Resolve API base URL: env var → xcconfig → hard-coded fallback.
if [ -z "${API_BASE_URL:-}" ]; then
  if [ -f Secrets.xcconfig ]; then
    raw=$(grep '^API_BASE_URL' Secrets.xcconfig | cut -d'=' -f2 | tr -d ' ')
    # xcconfig escapes // as $()/; undo that.
    API_BASE_URL="${raw/\$()\/\//\/\/}"
  fi
fi
API_BASE_URL="${API_BASE_URL%/}"   # strip trailing slash

if [ -z "${API_BASE_URL:-}" ] || [ -z "${CF_CI_TOKEN:-}" ]; then
  echo "❌  CF_CI_TOKEN and API_BASE_URL must both be set." >&2
  exit 1
fi

AUTH_HEADER="Authorization: Bearer $CF_CI_TOKEN"

# Fixture resource directories.
FIXTURES_DIR="Packages/Fixtures/Sources/Fixtures/Resources"
MODELS_TEST_DIR="Packages/Models/Tests/ModelsTests/Resources"

# ── Helpers ───────────────────────────────────────────────────────────────────

fetch() {
  local url="$1" dest="$2"
  echo "  → GET $url"
  http_code=$(curl -sf -w "%{http_code}" -H "$AUTH_HEADER" \
    -H "Accept: application/json" \
    -o "$dest.tmp" "$url" || true)

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    # Pretty-print JSON for diff-friendliness.
    python3 -m json.tool "$dest.tmp" > "$dest" 2>/dev/null || mv "$dest.tmp" "$dest"
    rm -f "$dest.tmp"
    echo "     ✓ saved to $dest (HTTP $http_code)"
  else
    echo "     ⚠ skipped — HTTP $http_code (endpoint may not be seeded for test account)"
    rm -f "$dest.tmp"
  fi
}

# ── Fixture fetch list ────────────────────────────────────────────────────────
# Each entry is: DEST_PATH  ENDPOINT_PATH
#
# TODO: Replace TEST_BOOK_ID and TEST_CHAPTER_ID with real IDs from the CI
#       test account once enrolled. These can be stored as GitHub secrets
#       (CF_TEST_BOOK_ID, CF_TEST_CHAPTER_ID) and read here.

TEST_BOOK_ID="${CF_TEST_BOOK_ID:-b-atomic-habits}"
TEST_CHAPTER_N="${CF_TEST_CHAPTER_N:-1}"
TEST_BOOK_ID_2="${CF_TEST_BOOK_ID_2:-b-deep-work}"
TEST_CHAPTER_N_2="${CF_TEST_CHAPTER_N_2:-1}"

echo "Refreshing fixtures from $API_BASE_URL ..."

# catalog.json — book catalogue
fetch "$API_BASE_URL/book/books" \
  "$FIXTURES_DIR/catalog.json"

# book_manifest.json — single book manifest
fetch "$API_BASE_URL/book/books/$TEST_BOOK_ID" \
  "$FIXTURES_DIR/book_manifest.json"

# book_state.json — reading state for the test book
fetch "$API_BASE_URL/book/books/$TEST_BOOK_ID/state" \
  "$FIXTURES_DIR/book_state.json"

# chapter_emh.json — a chapter in EMH variant
fetch "$API_BASE_URL/book/books/$TEST_BOOK_ID/chapters/$TEST_CHAPTER_N" \
  "$FIXTURES_DIR/chapter_emh.json"

# chapter_pbc.json — a chapter in PBC variant (different book)
fetch "$API_BASE_URL/book/books/$TEST_BOOK_ID_2/chapters/$TEST_CHAPTER_N_2" \
  "$FIXTURES_DIR/chapter_pbc.json"

# entitlement responses
fetch "$API_BASE_URL/entitlements" \
  "$FIXTURES_DIR/entitlement_pro.json"

# quiz.json
fetch "$API_BASE_URL/book/books/$TEST_BOOK_ID/chapters/$TEST_CHAPTER_N/quiz" \
  "$FIXTURES_DIR/quiz.json"

# notifications.json
fetch "$API_BASE_URL/notifications" \
  "$FIXTURES_DIR/notifications.json"

# reviews.json — spaced-repetition review queue
fetch "$API_BASE_URL/reviews" \
  "$FIXTURES_DIR/reviews.json"

# dashboard.json
fetch "$API_BASE_URL/dashboard" \
  "$FIXTURES_DIR/dashboard.json"

# streak.json
fetch "$API_BASE_URL/streak" \
  "$FIXTURES_DIR/streak.json"

# notebook.json
fetch "$API_BASE_URL/book/books/$TEST_BOOK_ID/notebook" \
  "$FIXTURES_DIR/notebook.json"

# badges.json
fetch "$API_BASE_URL/badges" \
  "$FIXTURES_DIR/badges.json"

# Mirror relevant fixtures into Models test resources.
for f in catalog.json book_state.json chapter_emh.json chapter_pbc.json \
          entitlement_pro.json quiz.json; do
  if [ -f "$FIXTURES_DIR/$f" ]; then
    cp "$FIXTURES_DIR/$f" "$MODELS_TEST_DIR/$f"
    echo "  ↳ mirrored $f → $MODELS_TEST_DIR"
  fi
done

echo ""
echo "✅ Fixture refresh complete."
echo "   Run 'swift test --package-path Packages/Fixtures' to validate locally."
