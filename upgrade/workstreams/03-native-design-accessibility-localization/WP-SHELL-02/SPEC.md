# WP-SHELL-02 — Compose the approved adaptive editorial app shell

## Problem and verified root cause

The current five-tab shell duplicates Home/Library/Discover/Profile/Settings responsibilities, richer Discover is unwired, and regular-width behavior is mostly cosmetic. Shared native primitives now belong to WP-NATIVE-01; feature-ready Discover/Detail routes belong to WP-CATALOG-01. This package only composes the approved IA.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. D-IA-01 is a mandatory owner input.

## Requirements

1. Encode the approved D-IA-01 compact/regular-width navigation model in AppFeature without duplicating feature routers or state owners.
2. Compose each feature-owned destination exactly once, including Discover and Book Detail routes from WP-CATALOG-01.
3. Preserve typed deep-link/auth-replay identity, session scope, and iOS 18 task outcomes across iOS 26 presentation enhancements.
4. Prove compact/resizable iPad/safe-area/keyboard/pointer and signed-out/guest/signed-in/reconnecting/reauth/account-switch behavior using WP-NATIVE-01 primitives.

## Acceptance criteria

### AC-SHELL-02-01

- Given approved D-IA-01
- When compact and regular shells compose
- Then each top-level destination has one role and each feature route is composed exactly once

### AC-SHELL-02-02

- Given a typed Discover, Book Detail, reader, settings, or external destination
- When navigation or auth-gated replay occurs
- Then the exact destination opens once without tab-only fallback or a second router

### AC-SHELL-02-03

- Given signed-out, guest, signed-in, reconnecting, reauth, and account A→B transitions
- When the shell recomposes
- Then stable owners remain singular and private content never flashes across scopes

### AC-SHELL-02-04

- Given compact iPhone, resizable iPad, keyboard/pointer, safe areas, and iOS 18/enhanced presentation outcomes
- When the shell matrix runs
- Then navigation, readable width, focus, and task outcome remain intentional and equivalent

## Invariants, compatibility, and rollback

AppFeature is the only composition owner. Features retain their routers/models and private state stays account-scoped. This package consumes but does not redefine DesignSystem primitives. Preserve route compatibility if tab identifiers change. Revert composition/tests together and retain exact-route tests; no release or PR #117 work.

## Test plan and definition of done

Run exact selectors in [VALIDATE.md](VALIDATE.md), AppFeature suite, unsigned app build, shell native matrix, independent exact-head review, required CI, merge verification, and safe cleanup. An unresolved D-IA-01 blocks start.
