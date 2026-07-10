#!/usr/bin/env bash
# scripts/refresh-fixtures.sh
#
# Captures VERBATIM JSON from the live ChapterFlow API into the real-contract
# fixture directory consumed by RealContractTests (Packages/Models). These
# captures are the ground truth for the client ↔ server contract:
# docs/API-CONTRACT-MISMATCH-AND-RECONCILIATION-PLAN.md.
#
# Two tiers:
#   PUBLIC  — needs NO token; always captured. Covers the browse surface
#             (catalog, search index, book detail).
#   AUTHED  — captured only when CF_CI_TOKEN is set (a valid Cognito id_token
#             for the CI test account). Covers /book/me/* and chapter/quiz.
#
# Environment:
#   API_BASE_URL  — API base (default: production https://app.chapterflow.ca/app/api,
#                   falling back to Secrets.xcconfig when present).
#   CF_CI_TOKEN   — optional; enables the authed tier.
#   CF_TEST_BOOK_ID / CF_TEST_CHAPTER_N — authed-tier book/chapter (defaults below).
#
# Run locally:
#   bash scripts/refresh-fixtures.sh                       # public tier only
#   CF_CI_TOKEN=<token> bash scripts/refresh-fixtures.sh   # both tiers
#
# NOTE: this script deliberately does NOT touch the curated preview fixtures in
# Packages/Fixtures/Sources/Fixtures/Resources — those are small, hand-picked
# sample sets for #Previews. Contract truth lives in the prod_* captures.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

if [ -z "${API_BASE_URL:-}" ] && [ -f Secrets.xcconfig ]; then
  raw=$(grep '^API_BASE_URL' Secrets.xcconfig | cut -d'=' -f2 | tr -d ' ' || true)
  # xcconfig escapes // as $()/; undo that.
  API_BASE_URL="${raw/\$()\/\//\/\/}"
fi
API_BASE_URL="${API_BASE_URL:-https://app.chapterflow.ca/app/api}"
API_BASE_URL="${API_BASE_URL%/}"

CONTRACT_DIR="Packages/Models/Tests/ModelsTests/Resources"

# A published book that exists in the production catalog.
PUBLIC_BOOK_ID="${CF_PUBLIC_BOOK_ID:-seven-powers}"
# Authed-tier fixtures come from the CI test account's started book.
TEST_BOOK_ID="${CF_TEST_BOOK_ID:-atomic-habits}"
TEST_CHAPTER_N="${CF_TEST_CHAPTER_N:-1}"

# ── Helpers ───────────────────────────────────────────────────────────────────

FAILED=0

fetch() { # fetch <url> <dest> [--auth]
  local url="$1" dest="$2" auth="${3:-}"
  local -a headers=(-H "Accept: application/json")
  if [ "$auth" = "--auth" ]; then
    headers+=(-H "Authorization: Bearer $CF_CI_TOKEN")
  fi
  echo "  → GET $url"
  http_code=$(curl -sS -m 30 -w "%{http_code}" "${headers[@]}" \
    -o "$dest.tmp" "$url" || echo "000")

  if [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 300 ] 2>/dev/null; then
    # Pretty-print JSON for diff-friendliness; keep raw bytes if not JSON.
    python3 -m json.tool "$dest.tmp" > "$dest" 2>/dev/null || mv "$dest.tmp" "$dest"
    rm -f "$dest.tmp"
    echo "     ✓ saved $dest (HTTP $http_code)"
  else
    echo "     ⚠ skipped — HTTP $http_code"
    rm -f "$dest.tmp"
    FAILED=$((FAILED + 1))
  fi
}

# ── Tier 1: PUBLIC (no token required) ───────────────────────────────────────

echo "Refreshing PUBLIC contract fixtures from $API_BASE_URL ..."

fetch "$API_BASE_URL/book/books" \
  "$CONTRACT_DIR/prod_catalog.json"

fetch "$API_BASE_URL/book/search-index" \
  "$CONTRACT_DIR/prod_search_index.json"

fetch "$API_BASE_URL/book/books/$PUBLIC_BOOK_ID" \
  "$CONTRACT_DIR/prod_book_detail.json"

if [ "$FAILED" -gt 0 ]; then
  echo "❌ $FAILED public capture(s) failed — aborting (the API should always serve these)." >&2
  exit 1
fi

# ── Tier 2: AUTHED (requires CF_CI_TOKEN) ────────────────────────────────────

if [ -z "${CF_CI_TOKEN:-}" ]; then
  echo ""
  echo "ℹ️  CF_CI_TOKEN not set — skipping the AUTHED tier (public tier captured fine)."
  echo "   Set CF_CI_TOKEN to also capture /book/me/* + chapter/quiz shapes."
  exit 0
fi

echo ""
echo "Refreshing AUTHED contract fixtures ..."

fetch "$API_BASE_URL/book/books/$TEST_BOOK_ID/chapters/$TEST_CHAPTER_N" \
  "$CONTRACT_DIR/prod_chapter.json" --auth

fetch "$API_BASE_URL/book/books/$TEST_BOOK_ID/chapters/$TEST_CHAPTER_N/quiz" \
  "$CONTRACT_DIR/prod_quiz.json" --auth

fetch "$API_BASE_URL/book/me/entitlements" \
  "$CONTRACT_DIR/prod_entitlements.json" --auth

fetch "$API_BASE_URL/book/me/progress" \
  "$CONTRACT_DIR/prod_progress.json" --auth

fetch "$API_BASE_URL/book/me/books/$TEST_BOOK_ID/state" \
  "$CONTRACT_DIR/prod_book_state.json" --auth

fetch "$API_BASE_URL/book/me/dashboard" \
  "$CONTRACT_DIR/prod_dashboard.json" --auth

fetch "$API_BASE_URL/book/me/streak" \
  "$CONTRACT_DIR/prod_streak.json" --auth

fetch "$API_BASE_URL/book/me/badges" \
  "$CONTRACT_DIR/prod_badges.json" --auth

fetch "$API_BASE_URL/book/me/reviews" \
  "$CONTRACT_DIR/prod_reviews.json" --auth

fetch "$API_BASE_URL/book/me/notebook" \
  "$CONTRACT_DIR/prod_notebook.json" --auth

fetch "$API_BASE_URL/book/me/notifications" \
  "$CONTRACT_DIR/prod_notifications.json" --auth

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "⚠️  Done with $FAILED authed capture(s) skipped (endpoint may not be seeded for the test account)."
else
  echo "✅ Fixture refresh complete."
fi
echo "   Validate: swift test --package-path Packages/Models --filter 'Real production contract'"
