# Localization (P10.11)

ChapterFlow is **localization-ready**: every user-facing literal is routed
through a String Catalog, formatters are locale-aware, and layouts mirror
correctly for right-to-left languages. **Launch locale is English only**; this
document is also the pipeline for adding more locales later.

---

## 1. What P10.11 fixed

P0.8 was supposed to make the app "localization-ready from day one," but that
groundwork **was never actually present**: there were **no String Catalogs**
anywhere in the tree, and **no package set `defaultLocalization`**. Roughly
800–1000 user-facing string literals lived in views with nowhere to be
extracted to. P10.11 closes that gap:

- Added `Localizable.xcstrings` to the app target and to every extension that
  renders user-facing text (see §3).
- Added `defaultLocalization: "en"` to every UI-bearing local package.
- Added the reproducible extraction pipeline (`scripts/l10n-extract.sh`).
- Verified formatters, RTL, and pseudo-locale QA (see §5–§7).

The change is **purely additive**: no view body was restructured and no call
site was rewritten to `bundle: .module` (see §2 for why that is unnecessary).

---

## 2. Architecture — one app catalog in `Bundle.main`

SwiftUI resolves a `LocalizedStringKey` (`Text("Hi")`, `Button("Save")`,
`.navigationTitle("Library")`, `.alert(…)`, `.accessibilityLabel("…")`, …)
against **`Bundle.main` by default** — even when that call site lives inside a
local SwiftPM package. Most of those convenience initializers have **no
`bundle:` override**, so the *only* way to point a package string at a
per-package catalog is to rewrite the call site (`Text("Hi", bundle: .module)`)
— which means restructuring hundreds of view bodies.

We don't need to. Because package strings already resolve against `Bundle.main`,
a **single `Localizable.xcstrings` in the app target** localizes every
LocalizedStringKey string across all ~16 packages with **zero call-site edits**.

### What is (and isn't) extracted

| Extracted → catalog | Not extracted (by design) |
| --- | --- |
| `Text("…")`, `Label("…", …)`, `Button("…")` | `Text(verbatim: …)` |
| `.navigationTitle`, `.alert`, `.confirmationDialog` | `Text(someStringVariable)` |
| `TextField`/`SecureField`/`Toggle`/`Picker` titles | server/user content (book titles, notes, quiz text) |
| `.accessibilityLabel/Hint("…")` | interpolated **runtime values** (the *template* is localized, the value stays data) |
| `String(localized: "…")` | preview / gallery / debug / diagnostics strings (denylisted) |

Server- and user-generated content must **never** be localized. The extractor is
literal-only (it never pulls a `String` variable), and dev-only strings are
filtered by a denylist — but always spot-check new catalog diffs.

### Known limitation

A string that a package renders **and** that is displayed inside an *extension*
(each extension has its own `Bundle.main`) is only localized if it also lives in
that extension's catalog. In practice extensions render their own literals, so
this is a non-issue today; revisit if shared UI moves into an extension.

---

## 3. Which targets have catalogs

| Target | Catalog | Notes |
| --- | --- | --- |
| `ChapterFlow` (app) | `ChapterFlow/Localizable.xcstrings` | Covers the app shell **and every linked package**. Auto-included via the target's synchronized root group. |
| `ChapterflowWidgets` | `ChapterflowWidgets/Localizable.xcstrings` | Widgets + Live Activities + Controls. |
| `NotificationContent` | `NotificationContent/Localizable.xcstrings` | Badge-celebration content extension. |
| `ShareExtension` | `ShareExtension/Localizable.xcstrings` | Save-to-Notebook share sheet. |
| `ActionExtension` | `ActionExtension/Localizable.xcstrings` | Ask-ChapterFlow action. |
| `NotificationService` | — none — | **Renders no user-facing literals** (it only mutates notification payloads), so it intentionally has no catalog. |

Extension catalogs are registered in the project by
`scripts/l10n-add-catalogs.rb` (via the `xcodeproj` gem — the pbxproj is never
hand-edited). The app catalog needs no registration.

---

## 4. Extraction pipeline (source of truth)

Run whenever UI text changes, then commit the `.xcstrings` diffs:

```sh
scripts/l10n-extract.sh              # full: compiler-extract + sync all catalogs
SKIP_BUILD=1 scripts/l10n-extract.sh # reuse an existing .l10n-derived build
```

The script compiles the whole app with `SWIFT_EMIT_LOC_STRINGS=YES` — the **same
compiler extraction Xcode uses**, so string interpolations get correct
`%lld`/`%@` format specifiers — then `xcstringstool sync`s the per-file
`.stringsdata` into the correct catalog (see the script header for routing and
the deny/allow lists). `#Preview`/gallery/debug/diagnostics demo strings are
stripped by `scripts/l10n-filter-previews.py`; translator comments are applied
from `scripts/l10n-comments.json`. Both are invoked by `l10n-extract.sh`.

**Verify (CI / pre-PR):**

```sh
scripts/l10n-verify.sh   # re-extracts and asserts a ZERO diff
```

This proves there are **no missing keys** (every extractable literal is already
in a catalog), the generator is **idempotent** (no churn on re-run), and there
are **no stale** entries.

### Why a script instead of the "Use Compiler to Extract Swift Strings" setting

Xcode's in-build extraction (`SWIFT_EMIT_LOC_STRINGS` on a target) only scans
that target's **own** sources — it never walks linked-package sources, so it
would capture almost nothing here (the app shell has ~0 literals; all UI text
lives in packages). Enabling it would also **mutate the committed `.xcstrings`
during every build** (dirty CI trees, noisy non-deterministic diffs) and mark
every package string `stale`. The script gives the same compiler-accurate
result as a **deterministic, reviewable, CI-safe** step. Translator comments and
translations added to a catalog are **preserved** across re-runs (`sync` only
adds/updates keys).

---

## 5. Formatters — locale-aware ✅

Dates, numbers, durations, and prices format per the user's locale + calendar +
time zone:

- **Prices** come straight from **StoreKit's localized `displayPrice`** — never
  hand-formatted (see `PaywallFeature`). This is also an App Store requirement.
- **Dates/relative dates** use `Date.FormatStyle` / `.formatted()` /
  `CoreKit.RelativeDate`, which localize by default.
- **Numbers/percentages/durations** rendered via `Text("\(n) min")` /
  `Text("\(pct)%")` become the catalog keys `%lld min` / `%lld%%`; SwiftUI
  formats the interpolated number using the environment locale (so digits are
  localized, e.g. Eastern-Arabic numerals in `ar`).

**Correctly fixed (POSIX) formatters — not user-facing, do not localize:**
`"yyyy-MM-dd"` day-bucket keys (`EngagementRepository`, `StreakModel`,
`DailyGoalModel`) and the RFC-1123 HTTP date parser in `APIClient`. These are
wire/keying formats and must stay locale-independent.

**Known minor gaps (documented, not fixed — fixing changes logic/signatures):**
a handful of Swift-Charts axis label closures and model helpers build plain
`String`s like `"\(v) min"` (e.g. `WeeklyGoalChart`, `ReadingTimeTrendChart`
axis marks, `AudioPlayer.durationLabel`). These are not `LocalizedStringKey`, so
their unit word isn't translated. They are low-visibility chart axes; converting
them to `Measurement`/`LocalizedStringResource` is a follow-up.

---

## 6. Right-to-left (RTL) — correct ✅

- Layout uses `.leading`/`.trailing` throughout (**362** uses); there are **no**
  `.left`/`.right` alignments or edges. Padding/alignment mirror automatically.
- Directional SF Symbols (`chevron.right`, `arrow.up.right`, …) **auto-mirror**
  in RTL — SwiftUI flips them for you; no manual `.flipsForRightToLeftLayoutDirection`
  needed.
- Verified with the RTL pseudolanguage (`ar-XB`, see §7).

---

## 7. Pseudo-locale QA

Two OS pseudolanguages exercise the app without any translations:

| Pseudolanguage | Reveals |
| --- | --- |
| `en-XA` (accented, ~+40% length) | **Missing keys** (un-accented text = not localized) and **truncation/overflow**. |
| `ar-XB` (bidi, double-length, RTL) | **RTL mirroring** + worst-case width. |

Run it against a stub-seeded simulator:

```sh
scripts/l10n-pseudo-run.sh en-XA     # accented / length
scripts/l10n-pseudo-run.sh ar-XB     # RTL / double-length
```

Or, in Xcode: **Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ App Language**
→ *Accented / Right-to-Left / Double-Length Pseudolanguage*.

Preview-based checks live alongside the design system
(`PseudoLocalization` + its `#Preview`s render light/dark/XXL with expanded,
accented, bidi-wrapped text so truncation is visible in the canvas).

### QA checklist — see `docs/LOCALIZATION-QA-CHECKLIST.md`.

---

## 8. Adding a locale (English → +N)

1. Open `ChapterFlow/Localizable.xcstrings` in Xcode → **＋** → add the language.
   Repeat for each extension catalog (or use **Product ▸ Export Localizations**
   to hand translators a single `.xcloc` bundle spanning all catalogs).
2. Translate. Ambiguous keys already carry translator **comments** (add more via
   the catalog's *Comment* field — they survive `l10n-extract.sh` re-runs).
3. Add the locale to the app target's **Localizations** (writes `knownRegions`).
4. Re-run pseudo QA in that locale's direction; fix truncation.
5. `scripts/l10n-extract.sh` to pick up any new keys; commit.

No code changes are required to add a locale — only translations.
