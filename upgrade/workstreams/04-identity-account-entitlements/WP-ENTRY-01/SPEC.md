# WP-ENTRY-01 — Make onboarding durable, adaptive, and localized

## Problem and verified root cause

Onboarding is a major first-use surface, but the verified base has English-only copy, weak
regular-width evidence, placeholder render guards, and incomplete interruption/relaunch/permission
recovery proof. Purchase and entitlement authority is intentionally split to WP-PAYWALL-01 because
its contracts, risk, and rollback differ.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source
`858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate each
anchor at lane start.

## Requirements

1. Preserve one durable onboarding step across interruption, denial, background, relaunch, and
   authenticated account transition without duplicate mutation.
2. Keep permission requested/denied/restricted/unavailable states truthful and recoverable.
3. Reject stale/repeated operations and exclude private identifiers from telemetry.
4. Add a package-local real non-English translation and run the complete WP-NATIVE-01 matrix.

## Acceptance criteria

### AC-ENTRY-01-01

- Given onboarding is interrupted, backgrounded, or relaunched
- When the user resumes
- Then the last durable current step is restored without duplicate completion

### AC-ENTRY-01-02

- Given permission is denied, restricted, unavailable, or later changed in Settings
- When onboarding resumes
- Then the state and recovery action are truthful without claiming permission success

### AC-ENTRY-01-03

- Given repeated/cancelled work or account A to B transition
- When asynchronous results complete
- Then only current-account/current-operation state publishes and telemetry contains no private data

### AC-ENTRY-01-04

- Given every mandatory native-matrix dimension and a real translated locale
- When all onboarding/recovery states render
- Then content, actions, focus, announcements, targets, motion/transparency, and non-color meaning
  remain usable without clipping

## Invariants, compatibility, and rollback

The authoritative session owner remains singular; durable onboarding state is explicitly scoped;
user/accessibility strings live in the package catalog; iOS 18 preserves the same task outcome. No
backend deployment, entitlement grant, purchase work, or release action is in scope. Revert
OnboardingFeature source/tests/evidence together without resetting user data.

## Test plan and definition of done

Run exact selectors and matrix in [VALIDATE.md](VALIDATE.md), full OnboardingFeature tests, dependent
composition tests, unsigned app build, independent exact-head review, required CI, merge verification,
and safe cleanup.
