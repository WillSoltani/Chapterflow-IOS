# ChapterFlow — iOS ↔ Backend API Contract Mismatch: Findings & Reconciliation Plan

| | |
|---|---|
| **Status** | WP-CONTRACT-01 remediation implemented on draft branches; fresh independent verification is still required |
| **Severity** | was P0 for native launch (the app could not load *any* real data from production) |
| **Date** | 2026-07-10 analysis and tolerant-client repair; backend-owned contract work updated 2026-07-13 |
| **Discovered** | First on-device run against production, during Phase 0 device bring-up |
| **Scope** | iOS client (`Chapterflow-IOS`) ↔ current backend source (`ChapterFlow`); deployed compatibility is recorded separately and is not inferred from source main |
| **Owner decision required** | None for fixture generation. Product/security decisions and deployment verification remain explicit blockers where listed. |

> This document is self-contained. It explains the bug, the root cause, why it went undetected,
> the full verified scope, the trade-off analysis, and the phased plan. §0–§13 are the original
> ANALYSIS (kept verbatim); the **Implementation Record** below documents what was actually
> built, what the analysis missed, and what remains.

## WP-CONTRACT-01 control plane (remediated 2026-07-13)

### Independent assessment and reproduced pre-fix failures

The independent verifier returned **FAIL** on the previous backend and iOS heads: two P1 integrity
failures, three P2 contract-evidence/semantic failures, and additional P3-class evidence and
regression-test gaps. This remediation does **not** claim that independent verification now passes;
a fresh verifier must inspect the new heads.

All ten reported defects were reproduced before the proof model was changed:

1. `committed_backend_branch` accepted a stale ancestor that lacked the generator and bundle.
2. Dirty relevant route/serializer bytes were hashed while provenance still named clean `HEAD`.
3. An unmerged PR head could be labeled `merged_backend`.
4. Swapping analytics track/beacon producer evidence preserved the flattened digest and passed.
5. Moving `commitment.get` between matrix rows preserved the global sets and passed.
6. Replacing matrix-summary membership while retaining operation and row names passed.
7. `account-delete.post` and `export.get` were misclassified as
   `recent_auth_active_user`.
8. All 23 blockers lacked an explicit closed resolution owner.
9. The broad iOS authority-pointer test passed through a test-local helper instead of production
   decoding/mapping.
10. The positive provenance canary itself accepted an unmerged branch head as `merged_backend`.

The remediation adds committed negative canaries for these bypasses, including constant-count
producer reassignment, operation-to-row reassignment, duplicate/missing relations, method/route
drift, producer symbol/path drift, stale and dirty sources, false merged provenance, and valid
branch, normal-merge, and squash-merge cases.

### Independent iOS inventory authority

iOS is now the sole generator authority for
`contracts/native-ios/v1/ios-source-inventory-manifest.json`. The backend consumes and validates a
byte-identical copy; it does not generate the iOS authority that it is checking. The dependency
sequence is:

- I1 `3bc162719cebda98744b05d261242bd5868841c6`: add the iOS-owned mapping, generator, and
  relational canaries.
- I2 `d65d7268c937ac9c571dd7bf165f701f9e8b7549`: pin the generated manifest.

The manifest proves 83 operations, 93 production producers, 29 matrix rows, and 93 relational
records. Each record has exactly 11 fields: operation ID, method, route template, matrix-row ID,
operation-variant ID, producer kind, producer symbol, producer source path, stable variant suffix,
source method expression, and source path expression. Its provenance hashes exactly 578 Git-object
inputs: all 576 production Swift source files plus the mapping and generator. Addition, removal,
dirty/staged/untracked changes, or nonmapped source drift therefore fail closed.

The pinned manifest SHA-256 is
`4c49bd44e01a86b344c8ab28e3c4fb684045384c38c4dd9cf4dd801764580470`; the relational-record
SHA-256 is `d8f4fcc3af527f1f9b8726f184b565a8d3cd92ab765b53856fa17940c84b8e4c`.
Backend validation requires one exact registry match per manifest relation and derives matrix
membership from those records instead of trusting flattened counts or summary sets.

### Exact backend provenance and artifacts

The backend's checked-in canonical bundle intentionally remains self-reference-safe with
`sourceRevision: null`, `sourceRevisionPhase: "uncommitted_backend"`, and
`committedInputTree: null`. The iOS bundle is a generated overlay over backend head
`01ab81848ce052a6f84709ff7729820609c5a81c`, using trusted backend-main ref
`968ff67ecafbed7e8e1d4c7b77badf507cfc5aee` and phase `committed_backend_branch`.

The overlay SHA-256 is
`120668d6484d3d49d0314a50ebbf764564e0853bd946613f51e3bd715065308a`; its committed input-tree
SHA-256 is `39deda7363debbc7f4ef044378c16cc25ca50e421d2297dcf186cc4cf1ac3919`.
Provenance binds 120 present inputs and seven expected-missing route paths to exact Git-object
bytes, then requires matching worktree bytes. It also requires a full source commit equal to
`HEAD`, a non-shallow repository, an explicit trusted main ref, the latest contract-changing
revision, and phase-correct integration evidence. Consequently, stale ancestors, dirty/staged or
unexpected untracked inputs, absent required blobs, false merged revisions, missing trusted refs,
and already-integrated branch-phase revisions all fail closed. `merged_backend` requires the exact
source revision to be reachable from the trusted main ref; branch integration additionally handles
normal and squash histories through exact ancestry/blob-history checks.

### Authentication, blocker ownership, and authority evidence

`account-delete.post` and `export.get` now use the closed class `recent_auth_user`: a Cognito
`id_token`, `requireUser`, and `requireRecentAuth` are required, while the active-account guard is
intentionally bypassed. The fenced evidence is the two route files, `app/app/api/_lib/auth.ts`, and
`app/app/api/book/_lib/account-guard.ts`; account deletion still requires `{confirm:"DELETE"}` and
remains an iOS-owned request mismatch. No runtime route or account behavior changed.

All 23 blockers now have a closed resolution owner, rationale, concrete evidence, dependency where
known, and decision status:

| Owner | Count |
|---|---:|
| `backend` | 3 |
| `coordinated` | 7 |
| `ios` | 6 |
| `product_or_security_decision` | 7 |

Authority evidence is no longer conflated:

- 51 operations have structural synthetic-fixture authority proof.
- Four have deletion tests through production iOS decoders/mappers:
  `models.chapter-progress.authority-deletion`, `models.quiz-progress.authority-deletion`,
  `models.entitlement.authority-deletion`, and
  `social.own-profile-identity.authority-deletion`.
- One is blocked/unproven: `quiz-submit.post`. No success fixture is invented; `/passed`,
  `/scorePercent`, and `/unlockedNextChapter` remain unproven, owned by iOS under `WP-SYNC-02`.

Structural fixture presence is not represented as production-consumer proof. Partial operations
without an executed production deletion test retain an explicit `native_authority_consumer_proof`
gap with an owner and dependency.

### Deterministic refresh, CI, and honest limits

The iOS refresh flow never copies a manifest from the backend. It independently regenerates the
iOS manifest from exact Git inputs, compares it byte-for-byte with the backend-consumed copy, runs
the backend Git-graph and exact-byte verifier, checks the canonical bundle, generates the overlay
twice, requires byte-stable output, and copies or checks only that overlay. The separate contract
drift workflow uses full Git history, an explicit trusted main ref, relational canaries, Models,
Networking, and SocialFeature authority consumers, plus secret/PII and deterministic-output checks.

Coverage remains deliberately honest: **0 full / 60 partial / 23 blocked**. Only 24 of 60 partial
operations execute the canonical success payload through a production decoder plus cache
round-trip, and only six of 93 producers have exact runtime factory tests. `reflection.post` and
`gift-claim.post` retain structural/native authority-consumer gaps. Route-specific error coverage
is not exhaustive, source fences are selected direct evidence rather than a transitive dependency
closure, and no physical-device, deployed-backend, production-runtime, or release claim is made.
These remain explicit P2/P3 limitations, not evidence of full coverage.
This remediation changed proof tooling, fixtures, tests, CI, and documentation only: it added no
runtime route, changed no product behavior, performed no deployment, and touched no release,
App Store, TestFlight, StoreKit, or signing state.

---

## Implementation Record (added 2026-07-10, post-implementation)

**Direction taken: Option A (client-side tolerant reconciliation), implemented on
`feat/api-contract-reconcile`.** All 17 packages pass (2,065+ tests) and the app builds for the
iOS 26 simulator. Highlights, including findings BEYOND the original analysis:

### I.1 Ground truth used
- **Deployed commit identified:** production runs sha `19b44fac` (the B1 squash-merge, deployed
  2026-07-02, per the deploy.yml run history) — NOT current web `main`. All authed shapes were
  derived from that exact commit's serializers (a detached worktree), with file:line provenance
  in the new test suites. B1 IS live (probe: garbage Bearer → `401 invalid_token`).
- **Verbatim public captures** now live as contract fixtures:
  `Packages/Models/Tests/ModelsTests/Resources/prod_{catalog,search_index,book_detail}.json`
  (110-book catalog, captured 2026-07-10).

### I.2 What the analysis under-scoped (found during implementation)
- `GET /book/me/progress` → `{summary, books:[…]}` envelope (not `{progress:[…]}`), items carry
  `completedChapters` array / `lastOpenedAt` / NO `totalChapters`.
- `GET /book/books/{id}` → wrapped `{book:{…}}`; manifest chapters send `minutes` + `id`+`chapterId`.
- Chapter/quiz routes send a TRIMMED `progress` (no `bestScoreByChapter`) → reader/quiz decode failed.
- `POST /quiz/submit` returns `{quiz: <session>, progress}` — the grade lives in `quiz.result`
  (`correctAnswers`, `nextAttemptAvailableAt` renames) → adapter derives the flat `QuizAttemptResult`.
- `/me/streak` → flat + `shieldsHeld`/`lastActiveDate` renames; `consistencyScore` is a number.
- `/me/dashboard` → the WEB homepage aggregate (no `dashboard` key) → synthesizer maps
  `insightPointsBalance`→flowPoints, progress count→booksStarted; other counters overlaid by their
  dedicated endpoints.
- `/me/notifications` items carry `readAt: string|null` (no `isRead`) → whole inbox silently empty.
- `/me/badges` → `{awards:[{badgeId, earnedAt, tier}]}` (no display fields).
- `/me/flow-points` → `{summary:{balance}, recentTransactions:[{transactionId, direction, …}]}`.
- `/events/active` → `{events:[…]}` list (not `{event}`); participation object implies joined.
- `/me/commitments` items: `commitmentId`, `ifThenPlan` (single string), `chapterNumber` (no
  `chapterId` → derived `"<bookId>-chNN"`, matching the manifest scheme).
- `…/scenarios` → `{mySubmissions, approvedScenarios}` (+ `submissionId` rename).
- `/me/notebook` entries keyed `id`, no `updatedAt`.
- `/me/tier` → FLAT spread + `tiers` catalog (no `tier` wrapper).
- `/me/profile` → `{profile:<settings>|null, identity:{sub,…}}` — no stats → synthesized OwnProfile.
- `/me/pairs` → SINGLE `{pair, partner}` (not a list) + status `"ended"` (mapped → `.expired`).
- **Confirmed canonical (no change needed):** chapter payload itself, entitlements+paywall,
  book state envelope, notifications envelope, notebook envelope, FSRS card fields, reviews
  `count` (already tolerated).

### I.3 The pattern implemented
`Packages/Models/Sources/Models/Common/TolerantDecoding.swift` — `decodeFirst(_:keys:)` /
`decodeRequiredFirst` (alternate-key, canonical-first) + `LossyArray`. Every reconciled model:
exactly one required identity field; alternates for every deployed spelling; defaults for the
rest; **always encodes canonical** (so SwiftData caches written before OR after this change decode).
Wrapper-or-bare envelope adapters where the deployed route nests/flattens/lists differently.

### I.4 Red-team pass (adversarial review of the diff)
- **Confirmed fail-closed:** no default can grant access — `unlockedThroughChapterNumber ?? 1`
  never exceeds the server floor; quiz `passed`/`unlockedNextChapter` default false; `isPro`
  untouched (plan+proStatus still required from the server); chapter content is server-fetched so
  client-side unlock state cannot bypass anything.
- **Fixed from the red team:** `BlockedUser` now accepts `id`/`blockedUserId` identity spellings
  (a rename must never silently empty the safety-critical blocklist); `DiscoverModel` sort got a
  stable `bookId` tie-break; a `Commitment` with an unparseable `followUpDate` degrades to
  `.distantFuture` instead of being dropped (user-authored data); `Chapter`'s no-active-variant
  content fallback made deterministic.

### I.5 Safety net turned on (Phase 5)
- `scripts/refresh-fixtures.sh` rewritten: correct endpoint paths (the old ones 404'd — wrong
  prefixes and fake book ids), a PUBLIC tier that needs NO token and FAILS on any error, and an
  authed tier gated on `CF_CI_TOKEN`.
- `.github/workflows/contract-drift.yml`: the public tier now ALWAYS runs (weekly + manual) —
  no more silent full skip; authed tier reports its skip loudly.
- New always-on PR coverage: `RealContractTests` (verbatim captures) +
  `DeployedShapeContractTests` (serializer-derived authed shapes, Models + SocialFeature) run in
  the normal package suites.

### I.6 Remaining / follow-ups
1. **Audio is deployment-blocked, not contract-blocked:** deployed prod (19b44fac) STREAMS a
   stitched MP3 from the audio route; the `?mode=plan` JSON manifest (PR #385) merged AFTER the
   deployed sha. The iOS narration player needs a **web deploy** — no client change can fix it.
2. **`GET /book/config/ios` (B4) 404s in prod** for the same reason (merged `d276ab244`, not
   deployed) — force-update/kill-switch is inert until the next web deploy.
3. **`CF_CI_TOKEN`** still wanted so the authed tier captures REAL fixtures (replacing the
   serializer-derived ones); the script + workflow are ready for it.
4. Dashboard/tier/profile synthesized values are placeholders (0/reader) by design — the UI
   overlays real values from the dedicated endpoints; if any screen shows a zero it shouldn't,
   check whether it reads the aggregate instead of the dedicated endpoint.
5. Next web deploy should be checked against the drift workflow (manual dispatch) since prod
   will jump from 19b44fac to a much newer main.

---

## Table of contents

0. [TL;DR](#0-tldr)
1. [Symptom](#1-symptom)
2. [How the app talks to the backend](#2-how-the-app-talks-to-the-backend)
3. [Root cause](#3-root-cause)
4. [Why this wasn't caught earlier](#4-why-this-wasnt-caught-earlier)
5. [Full scope of the mismatch](#5-full-scope-of-the-mismatch)
6. [Impact / blast radius](#6-impact--blast-radius)
7. [The decisive question: are the missing fields load-bearing?](#7-the-decisive-question-are-the-missing-fields-load-bearing)
8. [Solution options analysed](#8-solution-options-analysed)
9. [Recommended solution — phased plan](#9-recommended-solution--phased-plan)
10. [Effort estimate & sequencing](#10-effort-estimate--sequencing)
11. [Immediate tactical unblock](#11-immediate-tactical-unblock)
12. [Decisions needed from the owner](#12-decisions-needed-from-the-owner)
13. [Risks & mitigations](#13-risks--mitigations)
- [Appendix A — Full response-model field inventory](#appendix-a--full-response-model-field-inventory)
- [Appendix B — Evidence & file references](#appendix-b--evidence--file-references)
- [Appendix C — The reference tolerant-decoding pattern](#appendix-c--the-reference-tolerant-decoding-pattern)

---

## 0. TL;DR

On first launch on a real device against production, the app **signs in successfully** (Cognito auth
works) but **every data screen fails** with *"We received something unexpected. Please try again."*

The cause is a **client ↔ server contract mismatch**: the iOS Codable models expect one JSON shape,
and the deployed backend serves a different one. Concretely, the iOS `BookCatalogItem` requires
`bookId` / `status` / `latestVersion` / `updatedAt`, but the deployed `GET /book/books` returns `id`
(not `bookId`) and `publishedVersion` (not `latestVersion`), and omits `status` and `updatedAt`
entirely. Because the iOS decoder does **exact key matching with no tolerance for missing required
fields**, the *entire* response fails to decode → the whole screen shows the generic error.

Four findings shape the fix:

1. **It is the backend that drifted from the documented contract**, not the iOS client. `docs/PLAN.md §3`
   documents `BookCatalogItem = { bookId, …, status, latestVersion, currentPublishedVersion, updatedAt }`.
   The iOS models implement that faithfully; the deployed web endpoints diverge from it.
2. **The mismatch is systemic** (every endpoint hand-projects its own shape server-side, inconsistently)
   but **bounded and pattern-based** on the client (~10–15 high-risk models).
3. **The dropped fields are decode-required but logic-dead** — `status`, `latestVersion`, and
   `updatedAt` are not used for sync, gating, versioning, or correctness anywhere in the app. Making
   them optional removes the mismatch with *zero* behavioural change.
4. **The safety net that should have caught this was never switched on** — a fixture-capture + decode
   drift check exists in design (`contract-drift.yml`) but skips without a secret that was never set,
   and the hand-authored fixtures encode the *documented* shape, so tests validated the models against
   themselves, never against reality.

**Recommendation:** fix **client-side** with the existing RF2 tolerant-decoding pattern, driven by
**real captured fixtures** and a red/green decode-test loop; change the **backend only** if the full
authed-endpoint diff turns up a genuinely load-bearing dropped field (none found so far); and **turn on
the drift safety net** so this never recurs. This avoids a risky backend reshape/redeploy and is
lossless because the missing fields are dead. Estimated effort: days, parallelizable.

---

## 1. Symptom

- The app builds, installs, and launches on a physical device (Phase 0 succeeded).
- Sign-in works — the user reaches the authenticated app shell. **This proves Cognito auth + the
  Bearer-id_token transport are functioning.** Auth is a *separate* concern from the data API (auth
  uses Cognito directly via the `COGNITO_*` config; data uses `API_BASE_URL`).
- Every content screen (library, home, reader, dashboard, …) shows:
  > **"Couldn't load — We received something unexpected. Please try again."**

That exact string is the user-facing description of exactly **one** internal error case (see §2), which
is what makes the diagnosis precise.

---

## 2. How the app talks to the backend

**Base URL is correct.** `Secrets.xcconfig` sets `API_BASE_URL = https://app.chapterflow.ca/app/api`
(the production API, correctly accounting for the double-nested `/app/api` path). iOS endpoint paths
like `/book/books` compose to `https://app.chapterflow.ca/app/api/book/books`, which returns **HTTP 200
`application/json`** when probed directly. So the mismatch is *not* a URL/config error — the app reaches
the right endpoint and gets a real JSON body back.

**The decode path is strict.** In `APIClient`, every response is decoded via
`JSONCoding.decoder.decode(T.self, …)` with:

- **No `keyDecodingStrategy`** — JSON keys must match Swift property names **exactly**
  (`id` ≠ `bookId`, `publishedVersion` ≠ `latestVersion`).
- **Only date parsing is tolerant** — everything else is standard synthesized `Decodable`.
- Success bodies are decoded **directly into the model** — there is no generic envelope wrapper, and
  `Endpoint` carries no return type; the model is bound at the repository's `send` call site.

**Error mapping.** When decoding throws, the client produces `AppError.decoding(Error)`. Its
user-facing description is:

```
AppError.swift:60
case .decoding:
    return "We received something unexpected. Please try again."
```

So the message the user sees is a **decode failure**, categorically — not a 401 ("You're signed out…"),
not offline ("You're offline…"), not a server error envelope. The app received JSON it could not parse
into the expected Swift type.

**Consequence:** any single required (non-optional, no-default) field that the server omits, or any key
the server names differently, throws and **fails the entire response** — the whole screen, not just one
field.

---

## 3. Root cause

### 3.1 The concrete mismatch (catalog)

**iOS model** — `Packages/Models/Sources/Models/Catalog/BookCatalogItem.swift:4`
(synthesized `Codable`, **no `CodingKeys`, no custom `init(from:)`**):

Required (non-optional, no default):
`bookId, title, author, categories, tags, variantFamily, status, latestVersion, updatedAt`
Optional: `cover`, `currentPublishedVersion`.

**Deployed response** — `GET https://app.chapterflow.ca/app/api/book/books` returns, per book:

```json
{
  "id": "seven-powers",
  "title": "7 Powers: The Foundations of Business Strategy",
  "author": "Hamilton Helmer",
  "icon": "♟️",
  "coverImage": "https://…/covers/seven-powers.webp",
  "category": "Business",
  "categories": ["Business", "Strategy"],
  "difficulty": "Hard",
  "estimatedMinutes": 108,
  "chapterCount": 9,
  "pages": 240,
  "publishedVersion": 3,
  "synopsis": "…",
  "tags": [ … ],
  "variantFamily": "…"
}
```

**The diffs that break decoding:**

| iOS expects (required) | Deployed returns | Result |
|---|---|---|
| `bookId` | `id` | key mismatch → missing `bookId` → **throw** |
| `latestVersion` | `publishedVersion` | key mismatch → missing `latestVersion` → **throw** |
| `status` | *(absent)* | missing required → **throw** |
| `updatedAt` | *(absent)* | missing required → **throw** |

Any one of these fails the decode; all four are present. `CatalogResponse` wraps the list with
`decodeLossy` (drop-bad-elements), so the failure is **silent** — *every* book is dropped and the
library renders empty rather than erroring loudly. Other screens error loudly (see §5.2).

### 3.2 It is the backend that drifted from the documented contract

This is not "the iOS models are wrong." The **documented** contract in `docs/PLAN.md §3` (the
prose API reference; lines ~956 and ~2144) specifies:

```
BookCatalogItem = { bookId, …, status, latestVersion:Int, currentPublishedVersion:Int?, updatedAt:String }
```

The iOS models implement the documented contract faithfully. The **deployed web backend diverges from
its own documented contract**. Server-side, each route hand-projects its response instead of serializing
the canonical shape:

- `app/app/api/book/_lib/library-catalog.ts`
  - line ~77: `id: catalog.bookId` — **renames** `bookId` → `id`
  - line ~96: `publishedVersion: catalog.currentPublishedVersion ?? catalog.latestVersion` — **renames**
    `latestVersion` → `publishedVersion`
  - **drops** `status` and `updatedAt`, replaces `cover` with `icon`/`coverImage`, re-derives
    `category`/`difficulty`/`estimatedMinutes`.
- The **canonical** type still exists and carries the right fields:
  `app/app/api/book/_lib/types.ts:279-294` — `BookCatalogItem { bookId, latestVersion,
  currentPublishedVersion, status, updatedAt, … }`, and is returned raw by
  `repo.ts:listPublishedCatalogItems()` / `getCatalogBook()`. The catalog *builder* discards it in
  favour of a web-UI-friendly shape consumed by `app/book/_lib/library-data.ts` (`LibraryCatalogBook`).

There is **no shared serializer** — every `app/app/api/book/**` route builds its own JSON inline
(via `bookOk(...)` from `_lib/http.ts:125`), so field naming is **inconsistent route-to-route**
(the catalog emits `id`; `GET /me/progress` keeps `bookId` and `updatedAt`). There is therefore **no
single canonical wire shape** the iOS Codable models can target uniformly — the "web-shaped,
hand-projected" habit is the systemic root.

There is **no native content-negotiation**: the recently added Bearer-id_token path
(commit `c31fa695d`) only changes *authentication* (which token to verify, whether to skip CSRF); the
"native-ness" of a request is never propagated into any route body, and no `Accept`/`Accept-Version`/
`?client=`/header switch shapes responses. There is no versioned API surface (`/v1/`, `/native/`).

### 3.3 Why the *whole* response fails (not just one field)

The app's decode-tolerance strategy is **array-level, not field-level**:

- Most **list** envelopes use `decodeLossy` — they drop a bad element and keep the rest
  (catalog, search, badges, journeys, scenarios, commitments, notebook, notifications, reviews).
- **Single-object** responses have **no net at all** — one missing/renamed required field throws and
  fails the entire response (`BookManifest`, `Chapter`, `Dashboard`, `Entitlement`, `SeasonalEvent`).
- Two list envelopes are **not** lossy and behave like single-objects (`PairsListResponse`,
  `BlockedUsersResponse`).

Enum values are **not** a source of failure — `VariantFamily`, `EdgeType`, `Entitlement.Plan`, etc. all
map unknown wire strings to `.unknown` and never throw. **Missing/renamed keys are the failure mode.**

---

## 4. Why this wasn't caught earlier

The app was **built and CI-tested entirely against fixtures and stubs that were authored to match the
models** — it never exercised the real API. The intended safety net exists in design but was never
effective:

1. **`contract-drift.yml` (iOS repo, `.github/workflows/contract-drift.yml`)** is designed to capture
   live API responses (`scripts/refresh-fixtures.sh` using `CF_CI_TOKEN` + `CF_API_BASE_URL`) and run
   RF2 decode tests against them. But it:
   - **Skips entirely if `CF_CI_TOKEN` is unset** — and it was never set (`echo "Contract-drift check
     is SKIPPED"`).
   - Runs only **weekly** (`cron: '0 2 * * 0'`), not on PRs.
   - (Note: the *implementation* of the capture/compare job lives on the iOS side; the web repo has no
     such workflow. The check was described in the runbook as a P0.17 task and is effectively dormant.)
2. **The fixtures encode the *documented* shape, not captured-from-prod** (`Packages/Fixtures/…`), so the
   decode tests validated the models against a copy of themselves — a closed loop that could never
   detect divergence from the real server.
3. **`EvolutionTests` test the wrong failure mode** — they verify tolerance to *extra/unknown* fields
   and *bad enum* values (both of which Swift `Codable` already tolerates), but **not missing required
   fields**, which is exactly what happens in production.
4. **XCUITest flows** run against a `URLProtocol` stub (`CFStubRoutes`) fed by the same
   model-shaped fixtures — deterministic, but blind to the real contract.

Net: there was no point in the pipeline where iOS-decodes-real-server was ever exercised — until the
first on-device run against prod. (This is precisely the value of the INT on-device checkpoints.)

---

## 5. Full scope of the mismatch

### 5.1 Endpoint → response-model map (verified first-hand)

Auth flag from `Endpoint.swift`; model bound at the repository `send` call site. `⚠️` = model carries
canonical/DB-shaped required fields and/or strict decode → high mismatch risk.

| Method · Path | Auth | Decoded model |
|---|---|---|
| GET `/book/books` | ❌ | `CatalogResponse{books:[⚠️ BookCatalogItem]}` — **confirmed broken** |
| GET `/book/search-index` | ❌ | `SearchIndexResponse{books:[SearchIndexBook]}` — prod returns a **bare array** |
| GET `/book/books/{id}` | ✅ | `⚠️ BookManifest` (single-object, not lossy) |
| GET `/book/books/{id}/chapters/{n}` | ✅ | `ChapterResponse{chapter:Chapter, progress:BookProgress}` |
| GET `.../chapters/{n}/quiz` | ✅ | `QuizResponse{quiz:QuizClientSession, progress:BookProgress}` |
| GET `/book/me/entitlements` | ✅ | `EntitlementResponse{entitlement:Entitlement, paywall?}` |
| GET `/book/me/progress` | ✅ | `ProgressOverviewResponse{progress:[…]}` (lossy) |
| GET/POST `/book/me/saved` | ✅ | `SavedBooksResponse{savedBookIds:[String]}` |
| GET `/book/me/books/{id}/state` | ✅ | `BookStateResponse` **and** `BookStateResponseEnvelope` (two models, one path) |
| POST `.../start`, PATCH `.../state` | ✅ | `BookStateResponse` |
| GET `/book/me/dashboard` | ✅ | `⚠️ DashboardResponse{dashboard:Dashboard}` |
| GET `/book/me/streak` | ✅ | `StreakResponse` |
| GET `/book/me/flow-points` | ✅ | `FlowPointsResponse` (lossy) |
| GET `/book/me/shop` | ✅ | `ShopResponse{items:[ShopItem]}` (lossy) |
| GET `/book/me/badges` | ✅ | `BadgesResponse` (lossy) |
| GET `/book/me/reviews` | ✅ | `ReviewsResponse` (lossy) |
| GET `/book/me/dashboard`, `/tier`, `/profile` | ✅ | `DashboardResponse` / `TierResponse` / `OwnProfileResponse` |
| GET `/book/config/ios` | ❌ | `IOSAppConfig` — **fully tolerant; the reference pattern to copy** |
| GET `/auth/session` | ✅ | `getSession()` defined but **never decoded in live code** (tests only) — dead |
| events, journeys, commitments, pairs, gifts, notebook, settings, reflections, referrals, scenarios, safety, onboarding, devices, ask, concept-graph, audio | ✅ | see [Appendix A](#appendix-a--full-response-model-field-inventory) |

### 5.2 The structural insight

Because tolerance is **array-level not field-level**, the blast radius concentrates in **single-object
responses** and the **two non-lossy lists**. These fail *loudly* (whole screen errors). The lossy lists
fail *quietly* (empty screen). Both are broken; the quiet ones are arguably worse because they look like
"no data" rather than an error.

### 5.3 Highest-risk models (fix these first)

Ranked by required-field count × no-tolerance × canonical-shaped names × blast radius:

1. **`BookManifest`** (`Catalog/BookManifest.swift:4`) — 10 required incl. `status`/`latestVersion`/
   `updatedAt` + `chapters`; **single-object, not lossy**. Book detail + reader + offline download
   seeding. **Highest risk.**
2. **`Chapter`** (`Content/Chapter.swift:10`) — 9 required incl. `activeVariant`, `content`,
   `contentVariants`, `examples`. The reader fails entirely.
3. **`Dashboard`** (`Engagement/Dashboard.swift:4`) — 9 required counters. A serializer that omits a
   zero-valued stat throws the whole dashboard.
4. **`Entitlement`** (`Entitlement/Entitlement.swift:5`) — 5 required; **paywall gating** critical path.
5. **`SeasonalEvent`** (`Engagement/SeasonalEvent.swift:9`) — 9 required inside an optional wrapper.
6. **`BookCatalogItem`** (`Catalog/BookCatalogItem.swift:4`) — **confirmed**; fails *quietly* → empty
   library.
7. **`UserScenario`** (`Engagement/Scenario.swift:99`) — 10 required, DB-row shape.
8. **`Commitment`** (`Engagement/Commitment.swift:103`) — 8 required, DB-row shape.
9. **`QuizAttemptResult`** (`Quiz/QuizAttemptResult.swift:5`) — 7 required; blocks quiz completion.
10. **`OwnProfile`** (`SocialFeature/…/OwnProfile.swift:6`) / **`ChapterReflection`**
    (`SocialFeature/…/ChapterReflection.swift:10`, strict `Date` `createdAt`).

### 5.4 Traps to watch

- **`PairsListResponse`, `BlockedUsersResponse`** — the only two list envelopes that are **not** lossy;
  a single bad element fails the whole list.
- **`ChapterReflection.createdAt`** — strict `Date`; throws if the server sends epoch-millis or a
  non-ISO string.
- **`PrivacySettings`** — all 6 Bools are required despite having `.default` values; a partial settings
  object throws.
- **Same path → two models**: `/book/me/books/{id}/state` decodes as both `BookStateResponse` and
  `BookStateResponseEnvelope`; `/book/me/settings` decodes as three different models across features.
- **`AudioSegment.url`** is a `URL` (throws on a non-URL string), and `ChapterReflection`/others use
  strict `Date`.

### 5.5 Live-probe evidence (unauthenticated, first-hand)

| Endpoint | HTTP | Shape observed | iOS expectation | Verdict |
|---|---|---|---|---|
| `/app/api/book/books` | 200 JSON | `{books:[{id, publishedVersion, …}]}` | `{books:[{bookId, latestVersion, status, updatedAt, …}]}` | **mismatch** |
| `/app/api/book/search-index` | 200 JSON | **bare array** `[{id, type, bookId, bookTitle, author, …}]` | `{books:[…]}` object | **mismatch (envelope + fields)** |
| `/app/api/book/books/{id}` | 200 JSON | `{book:{…}}` | `BookManifest` | needs field check |
| `/app/api/auth/session` | 200 JSON | `{loggedIn}` | `{loggedIn, user}` (but model is dead) | n/a |
| `/app/api/book/me/progress` | 401 JSON | clean 401 (no auth) | — | endpoint exists, behaves correctly |

Authenticated endpoints (`/me/*`) return correct 401 JSON without a token, confirming they exist; their
**response shapes are unverified** because probing them requires a valid token (see §12).

---

## 6. Impact / blast radius

- **The entire authenticated experience is non-functional against production**: library is empty
  (quiet), and book detail, reader, quiz, dashboard, paywall, engagement, social all error loudly.
- **Auth is fine.** Sign-in, token handling, and CSRF-skip-for-Bearer all work.
- **Offline / sync (INT-3), push (INT-9), IAP-sandbox** on-device checklists are **blocked** until data
  loads, because they all begin by loading a book.
- **This is prod-only.** All fixture/stub-based tests remain green because they never touch the real
  contract — so CI will *not* flag this and cannot be relied on to verify the fix (see §9 Phase 2).

---

## 7. The decisive question: are the missing fields load-bearing?

This determines whether the client can simply drop/optionalize the fields, or whether the backend
**must** be changed to provide them. Verified by grepping every package for reads of the catalog fields:

| Field | Reads found | Verdict |
|---|---|---|
| `BookCatalogItem.status` / `BookManifest.status` | **Zero** functional reads (all `.status ==` hits are unrelated types: commitments, pairs, `NWPath.status`, download status, `AVPlayerItem.status`) | **Dead** |
| `.latestVersion` (catalog/manifest) | **Zero** reads (the only `.latestVersion` reads are on `IOSAppConfig`/`CoreKit.IOSConfig` — app-store version gating, a *different* type). Write-only on catalog items. | **Dead** |
| `.updatedAt` (catalog) | **One** read — `DiscoverModel.newBooks` sorts the "New & Updated" shelf by `updatedAt` (`LibraryFeature/Model/DiscoverModel.swift:46`), lexicographic on the ISO string. **Cosmetic ordering only.** Offline cache-invalidation uses a *local* `CachedKeyValue.updatedAt` (`LiveLibraryRepository:56/66/144`), **not** this field. | **Cosmetic** |

**Bottom line:** none of `status`, `latestVersion`, `updatedAt` feed sync, version comparison, offline
reconciliation, gating, or cache invalidation. Their **only** harm today is that, being non-optional
with no default and no tolerant `init`, their absence throws and fails the whole decode. **Making them
optional (and `updatedAt` a nil-safe `String?`) removes the mismatch with zero logic changes.** The
remaining real work is the key renames (`id`→`bookId`, `publishedVersion`→`currentPublishedVersion`) via
`CodingKeys` or a tolerant `init(from:)`.

The two models to *watch* for a genuinely load-bearing dropped field — because they gate real behaviour —
are **`Entitlement`** (paywall) and **`BookUserBookState`** (offline sync). These are behind auth and
unverified; the real-fixture capture in Phase 1 will settle them.

---

## 8. Solution options analysed

### Option A — Client-side tolerant reconciliation **(RECOMMENDED)**

Adapt the iOS models to decode the **actual deployed shapes**, using the RF2 tolerant-decoding pattern
the codebase already uses for `IOSAppConfig` (custom `init(from:)`, optional/defaulted fields, cannot
throw) plus `CodingKeys` for renames.

- **Pros:** no backend change, no deploy, zero risk to the web UI; lossless (the mismatched fields are
  dead); hardens the client against *future* drift (RF2's whole purpose); fully within the iOS repo.
- **Cons:** couples iOS models to the current web-UI shapes (mitigated by Phase 5 drift check); requires
  touching ~10–15 models; cannot recover a field that is genuinely load-bearing *and* absent
  server-side (none found so far — would fall back to Option B/C for just that field).

### Option B — Backend content-negotiation (serve canonical to native clients)

Branch each route's serializer on a "native" signal (the existing `isHeaderAuthenticatedRequest` Bearer
detector, or a new `Accept-Version`/`X-CF-Client` header) to emit the canonical shape.

- **Pros:** iOS models stay as-designed (matching the documented contract); one canonical shape.
- **Cons:** **no serialization chokepoint** — must edit ~10–20 route/`_lib` builders individually;
  **CDN cache-poisoning risk** — `/books` sets `Cache-Control: public` and a per-client body would need
  correct `Vary` or the native branch pollutes the shared cache; two shapes per route to maintain
  forever; requires a prod deploy. **Unjustified given the fields aren't load-bearing.**

### Option C — Dedicated native API surface (`/app/api/book/native/**` or `/v1/**`)

A parallel route tree that reuses the canonical `repo.ts` accessors and serializes canonical shapes
directly; iOS points at it.

- **Pros:** cleanest long-term separation; isolates the native contract from web-UI churn; no
  cache-poisoning; single stable shape the iOS models own.
- **Cons:** most backend work (a whole new route tree) + a prod deploy + an iOS base-path change;
  over-engineering for a non-load-bearing mismatch. **Revisit only if the native and web contracts must
  diverge hard later.**

### Comparison

| | A. Client-side | B. Content-negotiation | C. Native surface |
|---|---|---|---|
| Backend change | none | ~10–20 routes | new route tree |
| Prod deploy | no | yes | yes |
| Risk to web UI | none | medium (cache/Vary) | low |
| Time to working app | fastest | medium | slowest |
| Loses functionality | no (fields dead) | no | no |
| Guards future drift | yes (RF2) | partial | yes |
| **Verdict** | **Recommended** | Only for a load-bearing field | Long-term, not now |

---

## 9. Recommended solution — phased plan

**Client-side tolerant reconciliation, real-fixture-driven, backend-additive only for a proven
load-bearing gap, plus turning on the drift safety net.**

### Phase 1 — Capture reality (make it precise)
- Set `CF_CI_TOKEN` + `CF_API_BASE_URL` (production) and run `scripts/refresh-fixtures.sh` against real
  prod, so the capture covers the authed `/me/*` endpoints too.
- **Replace the hand-authored fixtures** in `Packages/Fixtures/` with the captured ones. Now every
  fixture reflects the *actual* deployed shape.
- *If no token can be supplied:* start with the public endpoints (`/book/books`, `/book/search-index`,
  `/book/books/{id}`, `/book/books/{id}/chapters/{n}`) which already cover the core browse→read loop;
  capture the authed ones later.

### Phase 2 — Make it test-driven (expose every mismatch)
- The current `EvolutionTests` test the *wrong* failure mode (extra/unknown fields, bad enums). Add
  **decode tests over the real fixtures** for every model. They will **fail loudly on exactly the models
  that mismatch** — that failing list *is* the punch-list. No guessing.

### Phase 3 — Reconcile client-side with the RF2 tolerant pattern
For each failing model, apply the `IOSAppConfig` reference pattern
(see [Appendix C](#appendix-c--the-reference-tolerant-decoding-pattern)):
- **`CodingKeys`** for renames (`id`→`bookId`, `publishedVersion`→`currentPublishedVersion`, and the
  search-index / any others surfaced in Phase 2).
- **Optionalize the dead fields** (`status`, `latestVersion`); `updatedAt` → `String?` (keep the
  `DiscoverModel` shelf sort nil-safe).
- **Custom `init(from:)`** so a missing *optional* never throws; render "only complete sub-objects" per
  the RF2 policy.
- **Handle envelope shape differences** where they exist (e.g. `search-index` returns a bare array →
  decode `[SearchIndexBook]` directly or wrap).
- **Fix the traps**: make the two non-lossy lists lossy where appropriate; make strict `Date` fields
  tolerant of epoch/ISO variants; relax `PrivacySettings` to defaulted Bools.

This unblocks the app against the **existing** prod, with no deploy and no web-UI risk.

### Phase 4 — Backend additive fixes, only for a proven load-bearing gap
If Phase 2 reveals an endpoint dropping a field that *is* load-bearing (watch `Entitlement`,
`BookUserBookState`), fix **that field** on the backend by **adding** it to the response (additive →
non-breaking for the web UI) + deploy. Based on the catalog evidence this is expected to be small or
zero.

### Phase 5 — Close the process hole (so this never recurs)
- Wire the fixture-capture + real-decode tests into **CI on every run** (not the dormant weekly job),
  gated on the token, with a **loud** skip if the token is ever removed.
- Keep fixtures **captured-from-prod**, never doc-authored.
- Extend `EvolutionTests` to assert on **missing-required** fields, not just extra/unknown ones.

---

## 10. Effort estimate & sequencing

- **Not** ~40 bespoke rewrites. The fix is **one pattern** applied to ~10–15 high-risk models, plus
  `CodingKeys` for renames — most list envelopes already have `decodeLossy`, and many small models are
  already tolerant.
- With real fixtures + a red/green loop, the reconciliation is mechanical and **parallelizable across
  feature packages** (Catalog/Content, Engagement, Social, Quiz, …).
- **Rough estimate: a few focused work-sessions (days), not weeks.**
- Suggested order: Phase 1 → 2 (get the exact punch-list) → 3 on the **§11 tactical subset first**
  (browse→read→quiz), then the rest → 4 (only if needed) → 5 (safety net).

---

## 11. Immediate tactical unblock

To get the **core loop working on-device fastest**, fix just the models on the browse → read → quiz
path — this needs **no token** (the first three are public):

1. `BookCatalogItem` (library grid)
2. `SearchIndexBook` / `SearchIndexResponse` (search + envelope-array shape)
3. `BookManifest` (book detail)
4. `Chapter` + `BookProgress` (reader)
5. `QuizClientSession` / `QuizResponse` + `QuizAttemptResult` (quiz)

With these decoding real prod, a user can browse the library, open a book, read chapters, and take a
quiz on-device — enough to start the INT-3 offline walkthrough. The authed engagement/social/dashboard
tail follows in the full reconciliation (needs a token for capture).

---

## 12. Decisions needed from the owner

1. **Direction** — proceed with **Option A (client-side)** per this plan? (Recommended.)
2. **Token** — can you supply a `CF_CI_TOKEN` (a service/CI credential that can read the authed `/me/*`
   endpoints) so Phase 1 captures the *complete* real contract? If not, we start with the public subset
   (§11) and capture the authed shapes once a token exists.
3. **Backend appetite** — if Phase 2 surfaces a genuinely load-bearing dropped field (e.g. on
   `Entitlement`/`BookUserBookState`), do you want the **additive backend fix + deploy** for that field,
   or should the client degrade gracefully without it?
4. **Longer-term** — do you eventually want the clean **native API surface (Option C)** as a follow-up,
   or is the hardened client contract sufficient? (Not needed now.)

---

## 13. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Client "fix" masks a truly load-bearing missing field | Phase 2's real-fixture decode tests + the §7 load-bearing analysis flag any field that's actually read; those go to Phase 4 (backend-additive). |
| The web UI shape changes later and re-breaks iOS | Phase 5 turns on the drift check on every CI run → caught immediately, not in production. |
| Making fields optional hides a future *required* field | Tolerant `init(from:)` renders "only complete sub-objects" (RF2) — partial data degrades visibly rather than crashing, and drift tests assert shape. |
| Authed endpoints have worse mismatches than the catalog | Capture them in Phase 1 with a token before committing to scope; the punch-list is empirical, not assumed. |
| Two-models-one-path / non-lossy-list traps missed | Enumerated in §5.4; covered explicitly in Phase 3. |

---

## Appendix A — Full response-model field inventory

`#req` = non-optional stored properties with no default (must be present or decode throws). ⚠️ = carries
canonical/DB-shaped required fields. "lossy" = list envelope drops bad elements; "single-object" = no
net.

### Models package — envelopes (`Responses.swift`)
| Type | line | #req | Required | Notes |
|---|---|---|---|---|
| CatalogResponse | 6 | 1 | books | **lossy** |
| ProgressOverviewItem | 21 | 4 | bookId, currentChapterNumber, totalChapters, completedChapterCount | synth |
| ProgressOverviewResponse | 55 | 1 | progress | **lossy** |
| SavedBooksResponse | 72 | 1 | savedBookIds | synth |
| ChapterResponse | 80 | 2 | chapter, progress | synth |
| QuizResponse | 90 | 2 | quiz, progress | synth |
| EntitlementResponse | 100 | 1 | entitlement | synth |
| BookStateResponseEnvelope | 110 | 1 | state | alt wrapper |
| ShopResponse | 120 | 1 | items | **lossy** |
| JourneysListResponse | 140 | 1 | journeys | **lossy** |
| RedeemFlowPointsResponse | 167 | 1 | balance | synth |

### Models — catalog / content
| Type | line | #req | Required | Notes |
|---|---|---|---|---|
| ⚠️ BookCatalogItem | Catalog/BookCatalogItem.swift:4 | 9 | bookId, title, author, categories, tags, variantFamily, **status, latestVersion, updatedAt** | synth; **confirmed broken** |
| Cover | :49 | 0 | — | synth |
| ⚠️ BookManifest | Catalog/BookManifest.swift:4 | 10 | bookId, title, author, categories, tags, variantFamily, **status, latestVersion, updatedAt**, chapters | **single-object** |
| BookManifestChapter | :63 | 4 | chapterId, number, title, readingTimeMinutes | synth |
| Chapter | Content/Chapter.swift:10 | 9 | chapterId, number, title, readingTimeMinutes, activeVariant, availableVariants, content, contentVariants, examples | **single-object** |
| ChapterVariantContent | :5 | 0 | — | synth |
| Example | Content/Example.swift:6 | 3 | scenario, whatToDo, whyItMatters | union types |
| ConceptGraph / ConceptNode / ConceptEdge | Content/ConceptGraph.swift | 2/2/3 | concepts,edges / id,label / from,to,edgeType | edgeType→`type`, tolerant |

### Models — progress / quiz / entitlement / auth / audio / notification
| Type | line | #req | Required | Notes |
|---|---|---|---|---|
| BookProgress | Progress/BookProgress.swift:5 | 4 | currentChapterNumber, unlockedThroughChapterNumber, completedChapters, bestScoreByChapter | synth |
| ⚠️ BookUserBookState | Progress/BookUserBookState.swift:5 | 4 | completedChapterIds, unlockedChapterIds, chapterScores, chapterCompletedAt | id-keyed maps |
| QuizClientSession | Quiz/QuizClientSession.swift:5 | 1 | questions | rest optional |
| QuizQuestion | :31 | 3 | questionId, choices, prompt(or `stem` legacy) | CodingKeys + init |
| QuizChoice | :70 | 2 | choiceId, text | synth |
| QuizAttemptResult | Quiz/QuizAttemptResult.swift:5 | 7 | passed, scorePercent, correctCount, totalQuestions, cooldownSeconds, unlockedNextChapter, questionResults | synth |
| Entitlement | Entitlement/Entitlement.swift:5 | 5 | plan, freeBookSlots, unlockedBookIds, unlockedBooksCount, remainingFreeStarts | Plan tolerant; **paywall gate** |
| Paywall | Entitlement/Paywall.swift:4 | 3 | price, pricingTiers, benefits | synth |
| UserProfile | Auth/UserProfile.swift:5 | 2 | userId, email | synth |
| AudioSegment | Audio/AudioNarrationPlan.swift:40 | 3 | segmentId, kind, **url(URL)** | url throws on non-URL |
| AudioNarrationPlan | :67 | 3 | bookId, chapterNumber, segments | synth |
| AppNotification | Notification/AppNotification.swift:59 | 6 | notificationId, type, title, body, isRead, createdAt | list-lossy |
| NotificationsResponse | :94 | 2 | notifications, unreadCount | **lossy** |

### Models — engagement
| Type | line | #req | Required | Notes |
|---|---|---|---|---|
| ⚠️ Dashboard | Dashboard.swift:4 | 9 | currentStreak, longestStreak, todayReadingMinutes, weeklyGoalMinutes, weeklyReadMinutes, booksStarted, booksCompleted, flowPoints, dueReviewCount | **single-object** |
| DashboardBookEntry | :48 | 3 | bookId, title, lastChapterNumber | synth |
| StreakState / StreakDay / StreakResponse | StreakState.swift | 3/2/1 | … | synth |
| BadgeItem / BadgesResponse | BadgeItem.swift | 5/1 | badgeId,name,description,category,isEarned / badges | **lossy** |
| FlowPointsState / FlowPointsResponse | FlowPointsState.swift | 1/1 | balance | **lossy** ledger |
| FlowLedgerEntry | FlowLedgerEntry.swift:6 | 5 | id, type, amount, description, createdAt | type tolerant |
| ShopItem | ShopItem.swift:6 | 5 | id, kind, name, description, cost | kind tolerant |
| TierState / TierResponse | TierState.swift | 2/1 | currentTier, overallProgress / tier | synth |
| JourneyCatalogItem / UserJourney | Journey.swift | 5/4 | … | synth |
| ⚠️ UserScenario | Scenario.swift:99 | 10 | id, bookId, chapterNumber, title, scenario, whatToDo, whyItMatters, scope, status, createdAt | array lossy |
| CommunityScenario / ScenariosResponse | Scenario.swift | 7/2 | … / scenarios,community | **lossy** |
| ⚠️ SeasonalEvent | SeasonalEvent.swift:9 | 9 | eventId, title, startsAt, endsAt, targetChapters, dailyTarget, bonusIp, isActive, hasJoined | **single-object** (optional wrapper) |
| EventProgress | :64 | 4 | eventId, chaptersCompleted, dailyChaptersCompleted, isCompleted | synth |
| FsrsCard | FsrsCard.swift:66 | 4 | cardId, bookId, front, back | 11 sched optional |
| ReviewsResponse | FsrsCard.swift:148 | 2 | cards, dueCount | **lossy** |
| ⚠️ Commitment | Commitment.swift:103 | 8 | id, bookId, chapterId, ifStatement, thenStatement, followUpDate, status, createdAt | status tolerant |
| CommitmentsResponse | :147 | 1 | commitments | **lossy** |
| ⚠️ NotebookEntry | NotebookEntry.swift:64 | 5 | entryId, bookId, type, createdAt, updatedAt | type tolerant |
| NotebookResponse | :123 | 1 | entries | **lossy** |
| SearchIndexBook | Search/SearchIndex.swift:27 | 3 | bookId, title, author | init defaults categories/tags/chapters |
| SearchIndexResponse | :8 | 1 | books | **lossy**; prod returns **bare array** |

### SocialFeature
| Type | line | #req | Required | Notes |
|---|---|---|---|---|
| ⚠️ ChapterReflection | ChapterReflection.swift:10 | 5 | reflectionId, bookId, chapterN, text, **createdAt(Date)** | strict Date |
| ReflectionsResponse | :60 | 1 | reflections | **lossy** |
| Gift / *Response | Gift.swift | 3/1 | code, giftType, status / gift | status tolerant |
| ⚠️ OwnProfile | OwnProfile.swift:6 | 7 | userId, tier, currentStreak, longestStreak, booksFinished, flowPoints, badgeCount | 5 raw counters |
| PrivacySettings | PrivacySettings.swift:10 | 6 | showStreak, showBooksFinished, showProgress, useDisplayName, leaderboardOptIn, discoverabilityOptIn | **trap: all 6 required despite defaults** |
| PublicProfile | PublicProfile.swift:5 | 3 | userId, tier, badgeCount | softer than OwnProfile (shapes disagree) |
| ⚠️ ReadingPair | ReadingPair.swift:54 | 5 | partnerId, partnerTier, partnerCurrentStreak, partnerBooksFinished, status | counters required (disagree w/ PublicProfile) |
| PairsListResponse | :118 | 1 | pairs | **NOT lossy (trap)** |
| ReferralProfile | ReferralProfile.swift:118 | 2 | code, stats | tolerant init |
| BlockedUsersResponse | SafetyModels.swift:101 | 1 | blockedUsers | **NOT lossy (trap)** |

### AIFeature / thin wrappers
| Type | line | #req | Notes |
|---|---|---|---|
| BookAskResponse | AIFeature/Models/BookAskResponse.swift:7 | 2 | answer, citations |
| IOSAppConfig | Networking/Endpoint+Config.swift:83 | 0 | **fully tolerant — the reference pattern** |
| ReadingSettingsResponse / UserReadingSettings | SettingsFeature | 0 | tolerant, decodeIfPresent |
| NotificationPreferences | NotificationsFeature | 0 | tolerant, decodeIfPresent ?? default |
| DeviceRegistrationResponse / *Ack | various | 0 | empty acks |

**Not Codable / excluded:** `PushPayload` (hand-parsed from APNs userInfo), `SubscriptionStatus`
(local StoreKit enum), request bodies, `@Model` caches, view models, outbox/pending types,
bundle-loaded WhatsNew models.

---

## Appendix B — Evidence & file references

**iOS (`/Users/radinsoltani/Chapterflow-IOS`)**
- Decode path & error: `Packages/Networking/Sources/Networking/APIClient.swift`;
  `Packages/CoreKit/Sources/CoreKit/AppError.swift:60` (`.decoding` → "We received something unexpected").
- Confirmed model: `Packages/Models/Sources/Models/Catalog/BookCatalogItem.swift:4`.
- Load-bearing evidence: `Packages/LibraryFeature/Sources/LibraryFeature/Model/DiscoverModel.swift:46`
  (only `updatedAt` read); `LiveLibraryRepository.swift:56/66/144` (local cache TTL, not the field).
- Base URL: `Secrets.xcconfig` → `API_BASE_URL = https://app.chapterflow.ca/app/api`.
- Documented contract: `docs/PLAN.md §3` (≈ lines 956, 2144) — specifies the `bookId/status/latestVersion/
  currentPublishedVersion/updatedAt` shape the iOS models implement.
- Dormant safety net: `.github/workflows/contract-drift.yml` (skips without `CF_CI_TOKEN`, weekly cron);
  `scripts/refresh-fixtures.sh`; `Packages/Fixtures/…`; `Packages/Models/Tests/ModelsTests/EvolutionTests.swift`
  (tests extra/unknown + enums, not missing-required).
- Reference tolerant model: `Packages/Networking/Sources/Networking/Endpoint+Config.swift:83` (`IOSAppConfig`).

**Web backend (`/Users/radinsoltani/ChapterFlow`, branch `web/native-bearer-auth`)**
- Catalog serializer (the rename/drop): `app/app/api/book/_lib/library-catalog.ts:77` (`id: catalog.bookId`),
  `:96` (`publishedVersion: … ?? latestVersion`).
- Canonical types: `app/app/api/book/_lib/types.ts:279-294` (`BookCatalogItem`).
- Canonical accessors: `app/app/api/book/_lib/repo.ts:260 listPublishedCatalogItems`, `:301 getCatalogBook`.
- Per-route JSON builder (no shared serializer): `app/app/api/book/_lib/http.ts:125 bookOk`.
- Web-UI presentation types: `app/book/_lib/library-data.ts:15-32 (LibraryCatalogBook)`.
- Bearer/auth path (auth-only, no serialization branch): commit `c31fa695d`;
  `app/app/api/book/_lib/auth-credential-core.ts`, `_lib/auth.ts:149-150`.
- Inconsistency example: `app/app/api/book/me/progress/route.ts:44-54` keeps `bookId`/`updatedAt`.
- `/books` cache header (cache-poisoning consideration for Option B): `app/app/api/book/books/route.ts:18`
  (`Cache-Control: public`).

**Live probes (production, 2026-07-10):**
- `GET /app/api/book/books` → 200 `application/json`, books with `id`/`publishedVersion`, no `status`/`updatedAt`.
- `GET /app/api/book/search-index` → 200, **bare array**, items keyed `id/type/bookId/bookTitle/author/text`.
- `GET /app/api/book/books/seven-powers` → 200 `{book:…}`.
- `GET /app/api/auth/session` → 200 `{loggedIn}`.
- `GET /app/api/book/me/progress` (no auth) → 401 `application/json` (correct).

---

## Appendix C — The reference tolerant-decoding pattern

`IOSAppConfig` (`Packages/Networking/Sources/Networking/Endpoint+Config.swift:83`) is the pattern to
replicate: a custom `init(from:)` that reads every field with `decodeIfPresent` and a default, so the
model **cannot throw** on missing/renamed/extra fields. Applied to a mismatching model, the shape is:

```swift
public struct BookCatalogItem: Codable, Sendable, Identifiable, Equatable {
    public let bookId: String
    public let title: String
    public let author: String
    public let categories: [String]
    public let tags: [String]
    public let cover: Cover?
    public let variantFamily: VariantFamily
    // Formerly required; now optional/defaulted — logic-dead per §7:
    public let status: String?
    public let latestVersion: Int?
    public let currentPublishedVersion: Int?
    public let updatedAt: String?     // DiscoverModel sort is nil-safe

    private enum CodingKeys: String, CodingKey {
        case bookId = "id"                       // server sends `id`
        case latestVersion = "publishedVersion"  // server sends `publishedVersion`
        case currentPublishedVersion
        case title, author, categories, tags, cover, variantFamily, status, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookId       = try c.decode(String.self, forKey: .bookId)   // still required — the id
        title        = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author       = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        categories   = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        tags         = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        cover        = try c.decodeIfPresent(Cover.self, forKey: .cover)
        variantFamily = try c.decodeIfPresent(VariantFamily.self, forKey: .variantFamily) ?? .unknown
        status       = try c.decodeIfPresent(String.self, forKey: .status)
        latestVersion = try c.decodeIfPresent(Int.self, forKey: .latestVersion)
        currentPublishedVersion = try c.decodeIfPresent(Int.self, forKey: .currentPublishedVersion)
        updatedAt    = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
    public var id: String { bookId }
}
```

> Illustrative, not final — the exact per-model shape comes from the Phase-2 real-fixture tests. The
> principle: **exactly one truly-required identity field; everything else optional/defaulted; renames via
> `CodingKeys`; cannot throw on partial data (render only complete sub-objects, per RF2).**

---

*End of document. No code changes have been made. Awaiting the §12 decisions before implementing.*
