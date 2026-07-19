# Native Product and Design Standard

## Direction

ChapterFlow is calm, editorial, content-first, and recognizably native. Content hierarchy and
learning continuity lead; decorative containers, gamification, and novel interaction do not.
Preserve the existing serif editorial voice, semantic backgrounds, restrained accent, and base-4
spacing relationships where they work.

Official Apple documentation is the live authority:

- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)

Bundled skill prose and automated checkers are advisory measurement aids, never App Store readiness
scores. Do not impose an unsupported universal eight-point grid.

## Foundation requirements

- Use semantic `DesignSystem` color, typography, spacing, radius, material, motion, and haptic
  tokens; add a token only for a demonstrated repeated relationship.
- Use system navigation, controls, sheets, menus, search, focus, and feedback when they satisfy the
  outcome. Never nest one interactive control inside another.
- Target iOS 18. Newer iOS 26 APIs require compile availability, `#available`, and an iOS 18
  fallback that preserves the same user outcome.
- Liquid Glass, when available, belongs sparingly to the functional navigation/control layer.
  Standard content and reading surfaces remain visually quiet.
- Avoid generic card grids, ornamental gradients, indiscriminate pills/glass, novelty gestures, and
  animation that competes with reading.

## Required state contract

Every changed surface defines applicable:

- first use and populated;
- loading and cached/partial;
- empty;
- actionable error/retry;
- offline/degraded;
- cancellation and repeated action;
- auth expiry/reauth;
- background/foreground;
- relaunch and exact resume;
- account A → sign out → account B.

Transient failure never erases valid cached content. Success appears only after real success.
Destructive actions explain consequences and use proportional confirmation.

## Adaptive layout

- Compact iPhone: preserve comfortable reading width, reachable primary actions, safe areas, and
  keyboard behavior.
- Regular width/iPad: define the information relationship intentionally with readable-width columns,
  split views, sidebars/inspectors, or adaptive grids; do not merely stretch an iPhone column.
- Test portrait/landscape and resizable iPad windows, keyboard/pointer, sheets/popovers, and
  navigation restoration.
- Book Detail, Search, Quiz, engagement dashboards, Ask/Concept Graph, Paywall, Auth, and Settings
  require explicit regular-width acceptance evidence.

## Accessibility contract

- VoiceOver: localized labels, values, hints only when useful, correct traits, logical order,
  focus after navigation/errors/sheets, announcements for material async changes, and equivalent
  actions for gesture-only behavior.
- Dynamic Type: support accessibility sizes without clipping, overlap, hidden actions, or forced
  one-line critical copy. Prefer reflow over scaling down.
- Controls: 44×44 points is the default iOS/iPadOS target. Apple documents a 28×28 minimum; any
  smaller-than-default control needs current-HIG support plus usability evidence and spacing that
  prevents accidental activation.
- Contrast: semantic colors adapt to Dark Mode and Increased Contrast; status never depends on color
  alone.
- Motion/transparency: respect Reduce Motion and Reduce Transparency without removing meaning.
- Graphs/charts: provide concise text summaries and navigable equivalents. The Concept Graph needs
  a synchronized native list/outline and explicit zoom/reset actions.

## Localization and writing

- All user-facing and accessibility strings use the repository localization system.
- Prefer concise, concrete, non-technical language and truthful state (“Saved for later submission,”
  not “Submitted”).
- Validate one real non-English locale, pseudo-localization/long text, plurals, dates/numbers, and
  RTL. Mirroring must not reverse semantic media controls or reading order incorrectly.
- Preserve book content and user text exactly; do not send private text into logs or visual evidence.

## Motion and feedback

- Motion explains continuity or state change; it is brief, interruptible, and cancellation-safe.
- Repeated taps cannot duplicate a mutation. Loading controls expose state and remain accessible.
- Haptics confirm meaningful user actions, not decoration, and use current native APIs when possible.

## Visual evidence

The program must replace the invalid gallery placeholder and non-comparing render guards with
deterministic, revision-bound evidence:

1. canonical data and stable locale/time/animation;
2. meaningful pixel or semantic assertions;
3. Light/Dark, compact iPhone, iPad regular width, and AX Dynamic Type;
4. reviewable baselines updated only with an explained behavior/design change;
5. simulator screenshots plus device checks where rendering/input differs.

Pixel snapshots are for deterministic content surfaces. OS-dependent navigation chrome/material
effects use semantic/render guards and manual screenshots rather than brittle pixel thresholds.

## Known redesign obligations

- App shell/Home/Library/Settings IA after `D-IA-01`.
- Intentional Home empty/recovery state.
- Book Detail regular-width layout.
- Accessible Concept Graph and adaptive engagement dashboards.
- Catalog/search interaction ownership.
- Cross-feature localization, focus, motion, contrast, and touch-target remediation.

Every later feature package owns the quality of its own states; the shared foundation is not a pass
that defers accessibility or design to a final cleanup lane.
