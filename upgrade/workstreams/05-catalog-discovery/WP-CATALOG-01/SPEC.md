# WP-CATALOG-01 — Complete the resilient catalog-to-detail journey

## Problem and verified root cause

Home can render an accidental blank state, transient section failure can obscure useful content,
row-level controls compete with selection, and stale search can publish. The richer Discover and Book
Detail implementation is also not yet a feature-ready typed path to one authoritative Start or
Continue destination. These behaviors share LibraryFeature cache, route, and presentation ownership;
integrating them separately would validate incompatible intermediate route/cache behavior.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source
`858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every
anchor on the exact lane base.

## Requirements

1. Give Home, Library, Search, Discover, and Book Detail intentional loading, valid-empty,
   cached/partial, error/retry, offline, auth-expiry, cancellation, background, and relaunch states.
2. Preserve valid cached/independent sections through transient failure and never present cache as
   freshly synchronized.
3. Separate row selection, save, and remove activation; cancel superseded search/detail work.
4. Emit typed Discover/Detail routes while AppFeature remains the sole top-level composition owner.
5. Preserve exact book/chapter/resume identity through repeated Start or Continue without granting an
   unlock locally.
6. Add a package-local string catalog with a real non-English translation; generate the complete
   candidate-head native matrix defined by WP-NATIVE-01.
7. Prove account A saved/progress state and pending work cannot publish into account B.

## Acceptance criteria

### AC-CATALOG-01-01

- Given valid empty, cached/partial, or independently failed catalog sections
- When Home or Library renders or refreshes
- Then intentional localized state/retry appears while every usable cached/independent section remains

### AC-CATALOG-01-02

- Given a selectable row also exposes save or remove
- When touch, VoiceOver, keyboard, and pointer activate it
- Then each separate target/focus/label fires only its intended action

### AC-CATALOG-01-03

- Given query A is cancelled or superseded by B
- When A completes late
- Then A cannot replace B and cancellation creates no error banner or stale analytics

### AC-CATALOG-01-04

- Given a Discover item is selected
- When LibraryFeature emits a destination
- Then one typed route retains exact book identity without deciding a top-level tab

### AC-CATALOG-01-05

- Given cached metadata and a cover or independent-section failure
- When Book Detail renders
- Then usable metadata/actions remain and only the failed portion offers retry

### AC-CATALOG-01-06

- Given Start or Continue is repeated, superseded, offline, auth-expired, backgrounded, or relaunched
- When authoritative access/resume state resolves
- Then one current exact book/chapter/resume route is emitted, context survives, and no unlock is invented

### AC-CATALOG-01-07

- Given account A has saved/progress/cache state and pending catalog work
- When A signs out and account B starts
- Then B cannot observe A or receive A's late result, and public data remains explicitly public

### AC-CATALOG-01-08

- Given every mandatory native-matrix dimension, including a real locale with translated values
- When Home, Library, Search, Discover, and Book Detail render
- Then hierarchy, actions, focus, announcements, targets, motion/transparency, and non-color status
  remain usable without clipping or route loss

## Invariants, compatibility, and rollback

LibraryFeature owns the catalog-to-detail journey; AppFeature alone composes top-level navigation.
Public and private saved/progress state remain explicit and account scoped. Cached content is not
represented as fresh, cover failure does not erase metadata, and server access remains authoritative.
The package-local catalog is processed through `Package.swift`; iOS 18 preserves the same task
outcome. Revert LibraryFeature source/tests/evidence as one rollback unit rather than restoring a
tab-only destination or erasing cache.

## Test plan and definition of done

Run every exact selector and matrix in [VALIDATE.md](VALIDATE.md), full LibraryFeature tests, affected
AppFeature route tests, unsigned app build, independent exact-head review, required CI, merge
verification, and safe cleanup. More than 20 changed files is a split/replan blocker.
