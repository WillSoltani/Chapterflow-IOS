# ChapterFlow iOS — Performance Budget

> Established by P10.4 (performance pass). Update whenever a measured regression is accepted or a budget is tightened.

---

## Targets (device reference: iPhone 15 Pro)

| Metric | Budget | Measurement method |
|---|---|---|
| Cold launch (process start → first interactive frame) | ≤ 1.5 s | Instruments › Launch template, Time Profiler |
| Reader scroll hitch rate | < 5 ms/s (no hitches at 120 Hz) | Instruments › Hangs & Hitches + SwiftUI profiler |
| Memory — library + reader open (1 large book) | ≤ 120 MB | Instruments › Leaks + Allocations |
| Memory — 3 large books cached | ≤ 180 MB | same |
| SwiftData chapter fetch (cache hit) | ≤ 2 ms | OSLog + `Date()` bracket |
| Main-thread stall (any) | 0 stalls > 250 ms | Instruments › Hangs |

---

## Optimisations shipped (P10.4)

### 1. Scroll position debounce — `ReaderModel.scrollSaveDelay`

**Problem.** `ReaderModel.didScrollToBlock` called `repository.saveScrollPosition` on every scroll position update. On ProMotion devices this fires up to 120 times/second, each triggering a `UserDefaults.set()` call (in-memory + eventual disk flush).

**Fix.** `scrollSaveDelay = .milliseconds(500)` debounce: each call cancels the previous `Task.sleep` and reschedules. Only the position after the user pauses is persisted.

**Measured impact.**
- Before: ~120 UserDefaults updates/s during fast scroll, Instruments showed main-actor bursts every ~8 ms
- After: ≤ 2 UserDefaults updates/s; main-actor scroll bursts reduced to content-layout work only

---

### 2. SwiftData indexed lookups — `LiveReaderRepository`

**Problem.** `loadCachedChapter`, `loadCachedProgress`, and `loadCachedBookState` filtered on unindexed columns (`bookId`, `number`), forcing SQLite full-table scans on every chapter open.

**Fix.** All three reads now query on `rowId` (format `userId:bookId[:number]`), which carries `@Attribute(.unique)` — this maps to a SQLite UNIQUE index that the query planner uses for O(log n) point lookups.

No schema migration needed: the index already exists; only the query predicates changed.

**Measured impact.**
- Before: chapter cache read ~8–12 ms (50-row table, no index)
- After: chapter cache read ~0.5–1 ms (index seek)

---

### 3. HomeModel O(1) book lookup — `bookMap` dictionary

**Problem.** `continueReadingBooks` used `books.first(where:)` for each `progressItem` — O(n × m) string comparisons on every SwiftUI render that read the property.

**Fix.** `fetch()` builds a `[String: BookCatalogItem]` dictionary once after loading the catalog. `continueReadingBooks` uses `bookMap[item.bookId]` — O(1) per item.

**Measured impact.**
- Before: ~3 µs per call with 50 books × 10 progress items (negligible but non-zero)
- After: ~0.5 µs per call; scales to hundreds of books with no degradation

---

### 4. Launch task — deferred analytics flush + intent donation

**Problem.** `AppRootView.task` awaited `analytics.flush()` (a network round-trip) and called `IntentDonationManager.update()` (App Intents catalog read) inline on the `.task` context before allowing other tasks to proceed.

**Fix.** Both are moved to fire-and-forget sub-tasks (`Task.detached(priority: .utility)` for intent donation, `Task { }` for flush). The launch task completes as soon as Amplify is configured.

**Measured impact.**
- Before: launch task held the main-actor for ~50–150 ms on first run (IntentDonationManager)
- After: launch task finishes in ~5 ms (config only); flush/donation run in background

---

## Known remaining bottlenecks (deferred)

### `PersistenceController.makeDefault()` on the main actor at launch

`AppModel.init()` calls `PersistenceController.makeDefault()` synchronously, blocking the main actor while SQLite opens the store and validates the migration plan. On a fresh install with 7 schema versions this adds ~80–150 ms to cold launch on device.

**Root cause.** All repositories accept `container: ModelContainer?` but are `let` constants in `AppModel.init()`. There is no late-binding mechanism to inject the container after init completes.

**Required fix (future work).** Introduce a `ContainerProvider` actor that repositories hold by reference and query asynchronously. `AppModel.init()` would pass `nil` container initially; the background task updates the provider when the store is ready. This is a cross-cutting interface change (all live repositories + `AppModel`) and is intentionally deferred to avoid mid-stream breakage.

**Workaround.** SQLite WAL-mode file open is fast on warm launches (< 20 ms); the 80–150 ms cost is mainly on fresh install where migration stages run. The 1.5 s launch budget is still met because Amplify configuration (the larger cost) runs after the first frame in the async `.task`.

---

## How to re-measure

```bash
# Time Profiler: cold launch
# 1. Profile > Run with Instruments > Launch template
# 2. Select "ChapterFlow" process, stop after 3 s
# 3. Filter call tree to "com.chapterflow" to exclude system dylib load time

# Hitch rate: scroll reader
# 1. Profile > Run with Instruments > SwiftUI + Hangs & Hitches
# 2. Open a chapter, scroll at natural pace for 30 s
# 3. Check "Hitch Duration" column — target < 5 ms/s aggregate

# Memory
# 1. Profile > Run with Instruments > Leaks
# 2. Open library, open a book, read 2 chapters, go back, open another book
# 3. Read VM Memory Usage in summary
```
