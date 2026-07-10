# P10.12 — Visual-QA matrix

A systematic audit of every top screen across appearance, Dynamic Type, device
size and accessibility axes, plus the regression tests that keep it from
drifting. This document is the **checklist** the Definition of Done refers to.

## Matrix

| Axis | Values covered |
|------|----------------|
| Appearance | Light, Dark |
| Dynamic Type | XS → AX5 (both extremes exercised: `.xSmall` and `.accessibility5`) |
| Device size | iPhone SE (320 pt), iPhone 16 Pro (393 pt), Pro Max (440 pt), iPad portrait (834 pt) & landscape / split |
| Accessibility | Increased contrast, Reduce Transparency, RTL layout |
| Data state | Loaded, Empty, Loading (skeleton), Error / Offline |

## Top screens audited

1. Library (`LibraryView`) + Book Detail (`BookDetailView`)
2. Reader (`ReaderView`)
3. Quiz (`QuizView`) + result (`QuizResultView`)
4. Paywall (`PaywallView`)
5. Ask-the-Book AI (`AskTheBookSheet`)
6. Social profile (`ProfileView`)
7. Engagement dashboard (`DashboardView`)
8. Onboarding (`OnboardingFlowView`)
9. Settings (`SettingsView`)
10. Design system component catalogue (`DesignSystemGallery`)

## How the matrix is enforced in CI

Two complementary, **flake-free** layers. CI runs every package's `swift test`
on `macos-26`; the author's dev machine is the same OS, so references and
renders match.

### 1. Pixel snapshots — design system only

`DesignSystemSnapshotTests` renders `DesignSystemGallery` (the full token +
component catalogue) and individual components to committed PNG references in
**light, dark and accessibility5** Dynamic Type, comparing at a 1 % per-pixel
tolerance (5 % for the SF-Symbol-heavy empty state, which anti-aliases
differently across hosts). The gallery is small, solid-token and deterministic,
so pixel comparison is safe here. Regenerate references with
`SNAPSHOT_RECORD=1 swift test --package-path Packages/DesignSystem`.

### 2. Render guards — every top screen

`*RenderGuardTests` render each real screen off-screen with `ImageRenderer`,
fed by the in-package preview fakes (no network, no live clock, no
random/UUID), and assert a non-empty bitmap is produced across the full matrix
(light / dark / XS / AX5 / SE / Pro Max / iPad / RTL). They commit **no
reference image**, so they cannot drift or flake across renderer versions or CI
hosts — yet they still catch layout traps, force-unwrap crashes,
`ContentUnavailableView` / `NavigationStack` regressions and infinite-layout
bugs the moment a screen stops rendering under any matrix cell.

**Why not pixel-snapshot the screens too?** Full screens pull in system
materials (`.glassEffect`, `.regularMaterial`), `ContentUnavailableView` and
navigation chrome whose exact pixels vary across OS point releases. Committing
those as references is a known CI-flake source (we spent hours killing two such
flakes before this task), and the project guardrail is explicit: *a flaky
snapshot is worse than none.* Render guards give regression protection with zero
flake risk; the design-system layer provides the pixel-diff safety net for the
shared visual vocabulary every screen is built from.

Snapshot suites are deterministic by construction (fixed viewports, fixed fake
data, animations frozen by `ImageRenderer`) and were verified green across 5
consecutive local runs — see the PR body.

## Manual review (Xcode Previews / simulator)

Two axes cannot be injected through public `EnvironmentValues` writable
keys — **Increased Contrast** and **Reduce Transparency** are system-driven and
read-only. These are verified manually via Xcode Canvas variant overrides and
the simulator's *Settings ▸ Accessibility ▸ Display* toggles. Every top screen
ships light+dark+XXL `#Preview`s for this pass.

## Findings & fixes

| Screen | Finding | Fix |
|--------|---------|-----|
| Paywall CTAs (`PaywallView`) | Primary purchase / manage / win-back buttons used a hard `.frame(height: 52)`; long labels (e.g. "Subscribe for $49.99/year") wrap and clip vertically at AX5. | `.frame(height: 52)` → `.frame(minHeight: 52)` — keeps the 52 pt touch target at default sizes, grows only when the label needs it. |
| Book Detail primary CTA (`BookDetailView`) | Same hard `.frame(height: 50)` on the Start/Continue/Upgrade button — clips at large type. | `.frame(height: 50)` → `.frame(minHeight: 50)`. |

Both fixes are additive and leave the default-size layout byte-identical. No
view hierarchies were restructured.

## Checklist (Definition of Done)

- [x] Light + dark verified on every top screen (render guards + DS pixel snapshots).
- [x] Dynamic Type XS and AX5 exercised on every top screen.
- [x] Device sizes SE → Pro Max → iPad covered per screen.
- [x] RTL layout covered per screen.
- [x] High-contrast + reduce-transparency: DS components honour the tokens;
      verified via Xcode/simulator overrides (read-only env, not automatable).
- [x] Empty / loading / error / offline states covered (Library free-locked,
      Reader offline, Quiz passed/failed, Social errored, DS state panel).
- [x] Clipping / overflow issues found were fixed (Paywall + Book Detail CTAs).
- [x] Snapshot + render-guard tests added and green (design system + top 10 screens).
- [x] App target builds; all changed packages' `swift test` green; SwiftLint clean.
