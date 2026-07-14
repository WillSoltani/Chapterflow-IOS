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

### 5. Deterministic async storage bootstrap — `WP-BOOT-01A`

**Problem.** `ChapterFlowApp.init()` synchronously created `AppModel`, whose main-actor initializer opened SwiftData with `try?`. A failure silently removed annotations, sync, and downloads while the UI still appeared usable. The same path delayed the first frame until persistent storage was open.

**Fix.** `ChapterFlowApp` now creates only an observable bootstrap coordinator. Its initial state renders a lightweight launch shell. `DefaultAppPersistenceLoader.load()` uses Swift's `@concurrent` execution boundary to open the existing SwiftData migration plan and required download directory away from the caller's actor. Only then does the main actor configure the minimal required session and construct one live graph with non-optional storage resources. Storage or session failure publishes a dedicated retry surface; production has no in-memory, reset, or alternate-directory fallback.

**Architectural evidence.** Deterministic tests hold storage suspended while asserting the first frame exists and graph count remains zero; duplicate starts and retry taps retain one active attempt; a superseded loader that ignores cancellation cannot publish stale results. The unsigned generic Simulator build passes with both Simulator architectures.

**Measurement status.** This is an architecture and correctness result, not a new device-performance measurement. The historical 80–150 ms fresh-install store-open estimate above is not reused as an after number. `WP-BOOT-01B` owns privacy-safe launch signposts, migration fixtures, protected-data recovery, the closed storage-failure taxonomy, and the remaining physical-device measurements.

### 6. Closed storage recovery and launch evidence — `WP-BOOT-01B`

**Problem.** `WP-BOOT-01A` intentionally failed closed, but every persistence failure reached the same retry surface. A device whose protected data was temporarily unavailable could therefore invite a useless manual retry, while a persistent-store failure and a required-file-store failure could not be distinguished without retaining raw errors. Historical migration coverage also created only the current schema instead of proving each supported predecessor.

**Fix.** Bootstrap now exposes a value-free, closed storage taxonomy: protected data unavailable, persistent-store open or migration failure, required file-store failure, and conservative unavailable. Each category has a fixed support code. Protected-data unavailability renders a distinct non-retry surface and automatically resumes the existing generation exactly once after UIKit reports protected data available. Persistent-store and required-file-store failures remain explicit and retryable. Production still has no automatic deletion, reset, in-memory store, alternate directory, or silent fallback.

**Migration evidence.** Deterministic fixtures create an exact store for each declared historical schema V1 through V7, seed a durable record, and reopen it through the unchanged production V8 migration plan. The matrix asserts exact coverage of all declared schemas and all seven migration stages, verifies the seeded value survives, and verifies a current-model record remains writable.

**Instrumentation evidence.** Fixed-name `OSSignposter` events cover bootstrap start, first launch view availability, protected-data wait/resume, persistence start/end, required-session start/end, ready, and each fixed failure category. They contain no paths, raw errors, identifiers, configuration values, or dynamic metadata. The injected recorder proves the valid deterministic phase order and proves instrumentation failure cannot block launch. An unsigned iPhone 17 Pro Simulator launch captured fixed `BootstrapStarted`, `InvalidConfigurationFailed`, and `FirstLaunchViewAvailable` events from the placeholder-configuration path.

**Measurement status.** The simulator capture proves signpost availability and privacy shape; it is not a cold- or warm-launch performance result. No signed physical-device capture was run, so the 1.5-second reference-device budget remains unmeasured and unchanged.

## Known remaining launch work after `WP-BOOT-01B`

- Measure cold and warm launch on the reference device and a representative older supported device using the fixed signposts; adjust budgets only from those captures.
- Add deterministic classifications for disk-full and corruption only when the storage stack exposes stable, privacy-safe signals that do not depend on parsing SDK text. Unknown failures currently map conservatively to unavailable.
- Decide whether safe public browsing can be separated from account-private durable storage; bootstrap intentionally fails closed for every currently promised durable feature.

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
