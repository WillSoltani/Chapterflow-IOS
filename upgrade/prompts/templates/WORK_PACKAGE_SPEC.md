# WP-<DOMAIN>-<NN> — <Outcome title>

## Problem and verified root cause

State exact iOS/backend revisions, paths/symbols, reproduced/static evidence, confidence, and missing
proof. Historical plan text is only a lead.

## Functional and non-functional requirements

List one complete vertical outcome with bounded requirements.

## Acceptance criteria

### AC-<DOMAIN>-<NN>-01

- Given <precondition>
- When <action/adverse event>
- Then <observable exact outcome>

Provide three to eight criteria.

## Lifecycle and adverse states

Define applicable first-use, populated, loading, cached/partial, empty, error/retry, offline,
cancellation, repeated action, auth expiry, background/foreground, relaunch, and A→B.

## Invariant matrix

Cover architecture, navigation, concurrency/cancellation, account scope, server authority,
privacy/security, accessibility, localization, performance, and observability—even if the result is
“not affected; prove no ownership change.”

## Contract, compatibility, migration, rollout, rollback

Pin exact source and deployed evidence separately; define canonical shape, compatibility, migration,
source rollout order, deployment dependency, and safe rollback.

## Non-goals and release boundary

Exclude unrelated work, deployment, App Store/TestFlight/signing/release, and PR #117.

## Test plan and definition of done

Map fresh exact-head local/CI/device/review evidence and merge/cleanup predicates.
