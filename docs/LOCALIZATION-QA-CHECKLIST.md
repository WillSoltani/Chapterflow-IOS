# Localization QA Checklist (P10.11)

Run before shipping any locale change. Automated proofs first, then the manual
pseudo-locale sweep.

## Automated (run these; they gate the PR)

- [x] **No missing keys / idempotent generator** — `scripts/l10n-verify.sh`
      re-extracts and asserts the committed catalogs are unchanged (every
      extractable literal is present) and that a second run produces a zero diff.
- [x] **No stale entries** — same script asserts no `stale` string units.
- [x] **No server/dynamic/demo leakage** — the extractor is literal-only
      (never a `String` variable), `#Preview`/gallery/debug/diagnostics strings
      are filtered, and the catalog was spot-checked (see PR body).
- [x] **Pseudo transform unit tests** — `DesignSystemTests/PseudoLocalizationTests`.
- [x] **App-target build** — `xcodebuild build` compiles all five catalogs into
      their bundles (app + 4 extensions).

## Manual pseudo-locale sweep

Launch with each pseudolanguage and walk **every tab / sheet / alert**:

```sh
scripts/l10n-pseudo-run.sh en-XA    # accented, +40% length
scripts/l10n-pseudo-run.sh ar-XB    # bidi, double-length, RTL
```

For each screen confirm:

- [ ] **No plain English.** Every visible label is accented/expanded. Plain
      English text = a hardcoded literal that escaped the catalog → fix the call
      site (or, if it's server/user data, that's expected — verify it is).
- [ ] **No truncation / overflow.** Buttons, list rows, toolbar titles, tab bar
      items, badges, chart labels, and empty-states all fit or wrap. Watch
      fixed-width `HStack`s and `.frame(width:)`.
- [ ] **RTL mirrored (ar-XB).** Leading/trailing padding flips; chevrons/arrows
      point the other way; back-swipe and navigation feel native.
- [ ] **Numbers/dates/durations/prices** use the locale (digits, separators,
      order). Prices come from StoreKit `displayPrice`.
- [ ] **Dynamic Type.** Repeat a spot-check at the largest accessibility size
      (Settings ▸ Accessibility ▸ Display & Text Size, or the XXL previews).

## Screens to cover

Library · Discover · Search · Book detail · Reader (+ toolbar, TOC, chapter-end)
· Quiz (+ result) · Paywall · Subscription management · Onboarding · Settings
(+ downloads, push, sync, delete-account) · Engagement (dashboard, streak,
badges, commitments, notebook, reviews, tier, journeys) · AI (ask, history,
concept graph) · Social (pairs, invites) · Notifications · Widgets · Live
Activities · Share & Action extensions · Notification content (badge).
