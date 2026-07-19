# WP-ENGAGE-01 — Make engagement surfaces adaptive, owner-safe, and exactly routed

## Problem and verified root cause

The dashboard, daily-goal, charts, and journey/event affordances have dense layouts, incomplete semantic chart equivalents, weak partial-failure proof, and unverified reward/progress fallback behavior. Concept Graph is a separate AIFeature outcome in WP-GRAPH-01.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate at lane start.

## Requirements

1. Reflow dashboard/goal/chart states across compact, iPad, AX, real-locale, pseudo-long, RTL, keyboard/pointer, contrast, and motion settings.
2. Preserve valid sections through independent failures and distinguish cached/unknown from fresh state.
3. Give every chart a concise localized summary and navigable values where action is required.
4. Keep rewards, tiers, badges, goals, and progress server-authoritative; unknown grants nothing.
5. Route visible journey/event actions exactly or render truthful unavailability.
6. Localize package-owned copy in `Engagement.xcstrings`, including accessibility summaries, and
   prove account A → sign out → account B clears dashboard, reward, route, and shared-snapshot state.
7. Publish only the owner-bound, versioned shared snapshot defined by WP-EXT-01; no anonymous,
   stale-account, or authority-bearing fallback is allowed.
8. Define and deterministically test loading, cached/partial, empty, error/retry, offline,
   cancellation/repeated refresh, auth expiry, background/foreground, relaunch, and recovery without
   erasing valid sections or surfacing stale-account state.

## Acceptance criteria

### AC-ENGAGE-01-01

- Given compact/iPad/AX/real-locale/pseudo-long/RTL states
- When dashboard, daily goal, and charts render
- Then hierarchy reflows without clipping, overlap, or unreachable action

### AC-ENGAGE-01-02

- Given one dashboard section fails while another has valid content
- When refresh completes
- Then valid content remains and retry/status is scoped truthfully

### AC-ENGAGE-01-03

- Given a chart or heatmap is presented
- When VoiceOver/keyboard users inspect it
- Then a localized summary and navigable values preserve its decision-relevant meaning

### AC-ENGAGE-01-04

- Given a visible journey or event action
- When it is activated
- Then an exact typed destination opens once or the action is truthfully unavailable

### AC-ENGAGE-01-05

- Given reward, tier, badge, goal, or progress data is unknown/partial
- When the dashboard renders
- Then no value or authority is invented and status is not color-only

### AC-ENGAGE-01-06

- Given account A has dashboard, reward, journey, and shared-snapshot state
- When account A signs out and account B starts
- Then account A state is absent and account B receives only owner-matching state

### AC-ENGAGE-01-07

- Given WP-EXT-01's versioned owner-bound shared-snapshot schema
- When EngagementFeature publishes dashboard state for cross-process consumers
- Then the payload conforms exactly and unknown ownership publishes nothing

### AC-ENGAGE-01-08

- Given loading, cached/partial, empty, error, offline, cancellation, auth-expiry, background, and
  relaunch states
- When dashboard/goal/chart refresh and recovery transitions execute
- Then valid sections remain, stale work cannot commit, retry/auth recovery is scoped, and state is
  represented truthfully without invented authority

## Invariants, compatibility, and rollback

EngagementFeature owns dashboard/goal/journey/event presentation and snapshot publication, not Concept Graph or snapshot storage. AppFeature remains the composition/router owner. Server authority controls rewards and progress. Evidence is localized/privacy-safe, iOS 18 outcomes remain, and no feature router is duplicated. D-SURFACE-01 must be resolved before visible journey/event scope is implemented. Revert feature source/tests/evidence together.

## Test plan and definition of done

Run exact selectors in [VALIDATE.md](VALIDATE.md), full EngagementFeature suite, adverse-state
transition tests, app build, candidate-head native matrix, independent exact-head review, required
CI, merge verification, and safe cleanup.
