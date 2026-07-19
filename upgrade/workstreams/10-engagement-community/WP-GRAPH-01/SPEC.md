# WP-GRAPH-01 — Make Concept Graph understandable and operable

## Problem and verified root cause

Concept Graph is visually dense, primarily gesture-driven, and lacks an equivalent semantic model and complete focus/keyboard behavior. Combining it with dashboard and goal work exceeded one bounded package and blurred AIFeature ownership.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate at lane start.

## Requirements

1. Expose a synchronized localized outline of nodes, relationships, selection, and available actions.
2. Provide deterministic select, focus, zoom, pan-equivalent navigation, reset, and dismissal for touch, VoiceOver, keyboard, and pointer.
3. Reflow compact, regular-width, AX, real-locale, pseudo-long, and RTL states without color-only meaning.
4. Keep graph layout and analysis cancellable and off the main actor; run 30 paired
   current-main/candidate samples on identical fixture/device/toolchain, require candidate layout p95
   and peak memory no worse than current-main, and keep stalls over the predeclared 250 ms threshold
   at zero under `program/performance-budgets.json`.
5. Preserve learning/reward authority; a visual relationship never implies server-certified mastery.
6. Clear selected node, mastery explanation, cached graph, and analysis task across account A → sign out → account B.
7. Define deterministic loading, cached/partial, empty, error/retry, offline, cancellation,
   auth-expiry, background/foreground, relaunch, and recovery transitions for both graph and outline.

## Acceptance criteria

### AC-GRAPH-01-01

- Given a graph with nodes and relationships
- When the semantic outline is inspected
- Then it represents the same entities, order policy, selection, relationships, and actions

### AC-GRAPH-01-02

- Given touch, VoiceOver, keyboard, or pointer input
- When selection, navigation, zoom-equivalent, reset, and dismissal are invoked
- Then visual and semantic focus remain synchronized and recover predictably

### AC-GRAPH-01-03

- Given compact, resizable iPad, AX, real-locale, pseudo-long, RTL, contrast, and Reduce Motion states
- When the graph and outline render
- Then content and controls remain usable with non-color meaning and comfortable targets

### AC-GRAPH-01-04

- Given a large deterministic graph and a superseding request
- When layout/analysis runs
- Then the main actor remains responsive, stale work cannot publish, and declared timing/memory budgets hold

### AC-GRAPH-01-05

- Given unknown, partial, or missing mastery/reward data
- When the graph renders
- Then no client authority is granted and the semantic explanation remains truthful

### AC-GRAPH-01-06

- Given account A has selected/cached graph and mastery state
- When account A signs out and account B starts
- Then A's selection, graph, mastery explanation, and analysis result cannot appear for B

### AC-GRAPH-01-07

- Given loading, cached/partial, empty, error, offline, cancellation, auth-expiry, background, and
  relaunch graph states
- When graph/outline load and recovery transitions execute
- Then both representations remain synchronized, valid cache is preserved truthfully, stale work
  cannot publish, and retry/auth recovery does not invent mastery or reward authority

## Invariants, compatibility, and rollback

One model owns visual and semantic selection. Values crossing actors are Sendable and cancellation precedes publication. Strings and accessibility descriptions are localized. iOS 18 task outcomes remain intact. Revert model/view/tests together; do not remove the nonvisual equivalent or hide performance regression.

## Test plan and definition of done

Run exact selectors in [VALIDATE.md](VALIDATE.md), AIFeature suite, candidate-head native matrix, focused XCTest metrics, app build, independent exact-head review, required CI, merge verification, and safe cleanup.
