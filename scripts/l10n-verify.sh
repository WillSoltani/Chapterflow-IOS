#!/usr/bin/env bash
#
# scripts/l10n-verify.sh — P10.11 Localization
#
# Static "no missing keys" proof for CI / pre-PR. Re-runs the extraction and
# asserts the committed catalogs are already in sync with the source — i.e. every
# extractable user-facing literal is present (nothing missing) and the generator
# is idempotent (no churn). Also fails if any catalog contains a `stale` string
# (a key no longer produced by source), which would mean drift.
#
# Usage:
#   scripts/l10n-verify.sh          # full: build + extract + assert clean
#   SKIP_BUILD=1 scripts/l10n-verify.sh   # reuse an existing .l10n-derived build
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

CATALOGS=(
  "ChapterFlow/Localizable.xcstrings"
  "ChapterflowWidgets/Localizable.xcstrings"
  "NotificationContent/Localizable.xcstrings"
  "ShareExtension/Localizable.xcstrings"
  "ActionExtension/Localizable.xcstrings"
)

echo "▸ Re-running extraction to verify catalogs are in sync…"
SKIP_BUILD="${SKIP_BUILD:-0}" bash "$REPO/scripts/l10n-extract.sh" >/dev/null

status=0

# 1. Idempotency / completeness: no uncommitted change after a fresh extract.
if git diff --quiet -- "${CATALOGS[@]}"; then
  echo "✓ catalogs in sync — no missing keys, generator is idempotent"
else
  echo "✗ catalogs changed after extraction — run scripts/l10n-extract.sh and commit:"
  git --no-pager diff --stat -- "${CATALOGS[@]}"
  status=1
fi

# 2. No stale entries left behind.
for c in "${CATALOGS[@]}"; do
  stale=$(python3 -c "
import json,sys
d=json.load(open('$c'))
n=0
for k,v in d.get('strings',{}).items():
    for loc in v.get('localizations',{}).values():
        if loc.get('stringUnit',{}).get('state')=='stale': n+=1
print(n)
")
  if [[ "$stale" != "0" ]]; then
    echo "✗ $c has $stale stale entr(y/ies)"
    status=1
  fi
done
[[ "$status" == "0" ]] && echo "✓ no stale entries"

exit $status
