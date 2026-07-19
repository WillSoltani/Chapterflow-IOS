# WP-DEVICE-01 — Qualify signed-device behavior and exact-final performance

## Problem and verified root cause

Simulator automation cannot prove signed Keychain groups, Sign in with Apple, APNs, widgets/Live Activities, extension process boundaries, real audio interruptions/routes/backgrounding, real-network transitions, or representative memory/energy performance. Measuring before feature integration would make evidence stale.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. This package runs only after WP-JOURNEY-01 creates an immutable final development candidate.

## Requirements

1. Bind a committed scenario manifest to candidate SHA, signed build, device class, OS,
   configuration, environment, samples, and privacy-safe artifacts; consume the predeclared
   `upgrade/program/performance-budgets.json` and never author or relax thresholds in this lane.
2. Prove Keychain/SIWA relaunch and A→B isolation on approved devices and nonproduction configuration.
3. Prove APNs registration, widget/Live Activity/extension identity, import transaction boundaries, audio interruptions/routes/background, and real-network/offline/storage recovery.
4. Measure launch, catalog/reader scroll and pagination, image cache, memory, energy, main-actor
   stalls, long audio, and downloads against the predeclared budget IDs and sample policies on the
   exact candidate.
5. Return failures to the owning product package; this qualification lane edits no production source and never converts blocked to skipped.
6. Prove the central journey with VoiceOver on an approved physical device using recorded operator
   gestures plus expected/observed focus order, labels, values, traits, announcements, and recovery;
   Accessibility Inspector/device evidence supplements but does not masquerade as an automated test.
7. Independently qualify VoiceOver on every other changed visible surface from the localization/
   surface inventory regenerated from the exact final candidate: auth, onboarding, paywall, account,
   notifications, extensions, offline, engagement, Concept Graph, and social. Consume the exact
   append-only inventory attempt, record actual operator gestures and expected/observed speech/focus,
   and never let automated semantics alone pass.

Qualification is four independently resumable sublanes: auth; routing/process boundaries;
audio/network/storage lifecycle; and performance/accessibility. Each records its own authority,
candidate, device, checkpoint, and block state. A blocked sublane does not prevent unaffected
sublanes from running, but the package cannot complete until every acceptance criterion passes.

## Acceptance criteria

### AC-DEVICE-01-01

- Given the WP-JOURNEY-01 candidate and device manifest
- When qualification starts
- Then every scenario binds exact SHA/build/device/OS/environment/budget/sample metadata and redacts private data

### AC-DEVICE-01-02

- Given signed Keychain and approved identity-provider configuration
- When relaunch, expiry, reauth, sign-out, and account A→B run
- Then continuity and isolation hold without token or private-data exposure

### AC-DEVICE-01-03

- Given APNs, widgets/Live Activities, Share/Action extensions, and notification actions
- When delivery, denial, failure, process kill, import, and auth replay occur
- Then acknowledgement, ownership, transaction ordering, and exact destination are truthful

### AC-DEVICE-01-04

- Given audio/background/interruption/route, real network transitions, low storage, and relaunch scenarios
- When they execute
- Then media/text fallback, durable data, and recovery remain correct without silent loss

### AC-DEVICE-01-05

- Given exact-final launch, scroll, image, memory, energy, main-actor, audio, and download scenarios
- When statistically declared samples run
- Then every budget passes on the candidate or development-quality completion remains blocked and returns to the owning package

### AC-DEVICE-01-06

- Given an approved physical device, signed candidate, VoiceOver, and the central-journey script
- When an operator performs the declared gestures through Discover → Detail → Read/Listen → Annotate/Ask → Quiz/Resume
- Then observed focus, order, labels, values, traits, announcements, and recovery match the expected record without private data

- Given the candidate-bound changed-visible-surface inventory and the same approved physical-device
  qualification authority
- When an operator exercises every non-central auth/onboarding/paywall/account,
  notification/extension/offline, engagement/graph/social surface listed by that inventory
- Then every surface has an actual expected/observed focus, speech, announcement, action, and recovery
  record or the criterion remains blocked

## Invariants, compatibility, and rollback

Evidence contains no tokens, identifiers, private URLs/content, receipts, or raw bodies. Nonproduction environment and deployed revision are explicit. This package is development qualification, not TestFlight/App Store/release evidence. A source merge is not deployment. Revert only package-owned scripts; qualification artifacts remain outside the product tree. Production fixes belong in a newly validated owner package and invalidate the candidate.

## Test plan and definition of done

Run the exact manifest/scenario commands in [VALIDATE.md](VALIDATE.md) on approved devices. Every required scenario is passed, failed, or blocked; none is waived. Independent reviewer checks exact candidate/evidence identity and budgets before merge/post-merge verification and safe cleanup.
