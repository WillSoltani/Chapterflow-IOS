# WP-PAYWALL-01 — Make paywall and entitlement reconciliation truthful

## Problem and verified root cause

Paywall purchase/restore and server entitlement are authority-sensitive and cannot share the lower-risk
onboarding rollback unit. The verified base lacks complete pending/cancel/offline/already-Pro evidence,
real localization, and a proof that StoreKit-only success never grants server-backed access.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source
`858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate source,
deployed environment, StoreKit configuration, and every authority boundary at lane start.

## Requirements

1. Keep pending, cancelled, unavailable, offline, restore, verification-failed, and already-Pro states
   distinct with no false success.
2. Never grant Pro/unlocks or finish a transaction contrary to the verified server reconciliation rule.
3. Single-flight repeated actions, reject stale results, and isolate account A from B.
4. Keep receipts, transaction IDs, and private state out of logging/analytics/evidence.
5. Add package-local real localization and run every mandatory native dimension.
6. Reconcile pending/unfinished transactions truthfully across background/foreground and relaunch,
   preserving single-flight identity and denying Pro until server authority confirms it.

## Acceptance criteria

### AC-PAYWALL-01-01

- Given each purchase/restore/network/verifier outcome
- When the paywall reacts
- Then the truthful distinct state and recovery action appears without false success

### AC-PAYWALL-01-02

- Given StoreKit reports success without confirmed server entitlement
- When reconciliation runs
- Then Pro/protected unlock remain denied and the transaction follows the verified finish policy

### AC-PAYWALL-01-03

- Given a purchase/restore is repeated, cancelled, or superseded
- When asynchronous work completes
- Then only one current operation can mutate state and no receipt/identifier is emitted

### AC-PAYWALL-01-04

- Given account A has pending/cached entitlement state and account B starts
- When late reconciliation returns
- Then A state cannot grant or render for B

### AC-PAYWALL-01-05

- Given every mandatory native dimension and a real translated locale
- When all paywall/recovery states render
- Then copy, consequences, actions, focus, announcements, targets, motion, and non-color meaning remain usable

### AC-PAYWALL-01-06

- Given a purchase, restore, or server-verification operation backgrounds or the app relaunches
- When transaction reconciliation resumes
- Then exactly one stable operation is recovered, stale callbacks cannot publish, pending remains
  truthful, and no StoreKit-only result grants Pro or finishes outside the verified policy

## Invariants, compatibility, and rollback

Backend entitlement is authoritative; StoreKit alone does not grant Pro. The authoritative session and
transaction processor remain singular. Existing transaction/receipt encoding changes only under a
verified migration and device evidence. StoreKit test fixtures never ship in production artifacts.
Rollback preserves fail-closed access and never restores false success. No backend deployment,
App Store Connect, TestFlight, signing, or release work is authorized.

## Test plan and definition of done

Run [VALIDATE.md](VALIDATE.md), full PaywallFeature tests, StoreKit Test scenarios, dependent app tests,
unsigned build, independent contract/security/native review, required CI, merge verification, and safe
cleanup. Unknown deployed verification remains blocked for runtime claims.
