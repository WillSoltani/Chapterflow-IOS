# Test-suite repair — make `main` actually green

> Independent verification (2026-07-01) found `main` **builds** (app + all packages + Amplify) but the
> **test targets are not green** — contrary to the "32 tests green" reconcile commit, at least two test
> targets don't compile. Fix these in Xcode (only Xcode can run the full suite — the CLI blocks Amplify's
> `SmithyCodeGeneratorPlugin` build-tool-plugin trust gate). Run **Product ▸ Test (⌘U)** and don't declare
> green until it truly passes.

## 1) Networking — missing import (trivial)
`Packages/Networking/Tests/NetworkingTests/TestSupport.swift` uses `AppError` but only imports
`Foundation` + `Networking`. Add:
```swift
import CoreKit
```
(Its sibling `NetworkingTests.swift` already imports CoreKit — this file was missed.)

## 2) Persistence — the whole `TokenStoreTests` suite is stale
`Packages/Persistence/Tests/PersistenceTests/PersistenceTests.swift` `@Suite("TokenStore")` is written for an
**old async-actor** `TokenStore`; the reconciled source is a **sync struct**. Rewrite the suite to the
current API:
- Token type: `TokenStore.Tokens` → **`StoredTokens`** (top-level).
- Not async: drop every `await`. `try await store.load()` → `store.load()` (it's `func load() -> StoredTokens?`,
  non-throwing, non-async). `try await store.save(x)` → `try store.save(x)`.
- Rename: `store.clear()` → **`try store.delete()`**.
- **Delete the `changesStream()` test** — the reconciled `TokenStore` has no `changes()` reactive stream
  (Amplify owns session state now). If you decide you want reactive token-change notifications, that's a
  separate feature, not a test fix.
- Confirm `InMemoryKeychain` and the `TokenStore(keychain:)` init still exist as the tests assume; adjust if
  the init signature changed during reconciliation.

## 3) Run the FULL suite and fix the rest
Run **⌘U** (or test each package scheme) so the **Amplify-gated packages (AuthKit, AppFeature) also run** —
the CLI can't reach them, so there may be similar stale-test breakages there. Fix every failure until the
whole suite is genuinely green. Match tests to the reconciled source (the source builds and is canonical);
only change source if a test reveals a real behavioral gap.

## Definition of done
`⌘U` runs **all** package test targets and passes with **0 failures**. Then the "green" baseline is real and
you can resume the runbook at **P2.1** with the merge-as-you-go rule in effect.
