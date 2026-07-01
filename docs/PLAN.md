# ChapterFlow iOS — Architecture, Roadmap & Execution Plan

> **Purpose of this document.** This is the single source of truth for building the **native iOS app** for ChapterFlow in **Swift / SwiftUI**, using **Claude inside Xcode 26.3+**. It contains the architecture, the phased roadmap, a parallelization map, and a library of **~115 copy-paste prompts** (B1–B4 backend changes + ~110 iOS prompts across 11 phases) you feed to Claude in Xcode, one at a time, to build the app **end to end (0→100)** — from an empty project to App Store submission. The prompts are intentionally fine-grained: one prompt ≈ one focused Claude session ≈ one PR, so nothing is left implicit.
>
> **Goal stated by the owner:** the iOS app must be **better and more advanced than the web app** — not a port. The plan bakes native-only superpowers (offline reading, real audio, widgets, Live Activities, App Intents, on-device intelligence, haptics, ProMotion) in as first-class features, not afterthoughts.
>
> **The backend does not change** (it stays on AWS), except for **four small, well-specified server tweaks** (Section 3.2) that the native client requires. Those are written as prompts you run in the **web repo** (`~/ChapterFlow`), separate from the iOS prompts.

---

## Table of contents

0. [How to use this document with Claude in Xcode](#0-how-to-use-this-document-with-claude-in-xcode)
1. [Product vision: what makes the iOS app "better than web"](#1-product-vision-what-makes-the-ios-app-better-than-web)
2. [Architecture](#2-architecture)
3. [Backend contract (API reference) + required server changes](#3-backend-contract-api-reference--required-server-changes)
4. [Engineering conventions](#4-engineering-conventions)
5. [Roadmap: phases, dependency graph & parallelization map](#5-roadmap-phases-dependency-graph--parallelization-map)
6. [The prompt library](#6-the-prompt-library) — the heart of this doc
7. [App Store submission checklist](#7-app-store-submission-checklist)
8. [Risks & gotchas](#8-risks--gotchas)
- [Appendix A: Codable model catalog](#appendix-a-codable-model-catalog)
- [Appendix B: Endpoint quick reference](#appendix-b-endpoint-quick-reference)

---

## 0. How to use this document with Claude in Xcode

### The workflow

1. **Create the new iOS repo** (separate from the web repo). Run **Prompt P0.1** first — it scaffolds the Xcode project and packages.
2. **Copy this file** (or the trimmed "Shared Context Preamble" + "Conventions" sections) into the iOS repo as **`CLAUDE.md`** at the repo root, so Claude in Xcode reads your conventions automatically on every task. Also drop this whole roadmap at `docs/PLAN.md` in the iOS repo so prompts can say "per `docs/PLAN.md`".
3. **One prompt = one focused unit of work = one git branch = one PR.** Start a fresh Claude conversation per prompt (or per small cluster within a phase) to keep context clean. Paste the prompt; let Claude work to its **Definition of Done**.
4. **Use Xcode Previews to verify UI.** In Xcode 26.3 Claude can capture the Preview canvas and self-correct. Always ask it to add a `#Preview` and confirm it renders.
5. **Commit + test per prompt.** Each prompt ends with acceptance criteria; don't merge until they pass and `swift build`/tests are green.
6. **Run an integration pass at the end of each phase** (Prompt template `INT-x` pattern: "wire these features into the app shell, run the app, fix integration issues").

### The Shared Context Preamble (put this in the iOS repo's `CLAUDE.md`)

> You are building the **native iOS app for ChapterFlow**, an AI book-learning product. A production backend already exists on AWS and **does not change**: a REST API (base URL in `Secrets.xcconfig` as `API_BASE_URL`) with ~74 JSON endpoints, **AWS Cognito** auth (JWT `id_token`), DynamoDB, and S3. This app is a **fresh native SwiftUI client** that consumes that API. It must be **more polished and capable than the web app**: offline reading, premium typography, audio narration, widgets, Live Activities. **Design bar: Apple "Pro" restraint** — like Apple's own first-party apps. Calm, typographic, deferential to content. Not flashy.
>
> **Hard conventions (do not deviate):**
> - **Swift 6**, strict concurrency. **SwiftUI** only (no Storyboards/UIKit screens unless wrapping a specific control). **iOS 18.0** minimum target.
> - State via the **Observation framework** (`@Observable`), `@MainActor` on UI models. **async/await** everywhere; avoid Combine.
> - **Modular local SPM packages** (see architecture). Every feature package ships **SwiftUI `#Preview`s**.
> - **API envelope:** a SUCCESS response body is the **raw JSON object** (e.g. `{"books":[...]}`, `{"chapter":{...},"progress":{...}}`). An ERROR response body is `{"error":{"code":"...","message":"...","requestId":"...","details":?}}` with the matching HTTP status. Decode both shapes.
> - **Auth:** send the Cognito `id_token` as **`Authorization: Bearer <token>`**. Never cookies.
> - **Never hardcode** colors, spacing, fonts, radii — always use `DesignSystem` tokens.
> - Write **unit tests** for all non-trivial logic. Verify UI with **Previews**.
> - **Definition of Done (every task):** the package builds, tests pass, previews render, acceptance criteria met. Keep going until done; don't hand back partial work.

### Conventions for parallel work

Prompts are tagged **[SEQUENTIAL]** (must follow its dependency) or **[PARALLEL: Track X]** (can be built concurrently on its own branch by a separate Claude session). The parallelization map in Section 5 tells you exactly which tracks can run at once. When running parallel tracks, give each its own git branch off the latest `main`, and integrate via PRs in the order the map suggests.

---

## 1. Product vision: what makes the iOS app "better than web"

These native capabilities are **designed into the roadmap** (not bolted on). They are the answer to "why install the app instead of using the website":

| Superpower | What it does | Phase |
|---|---|---|
| **Offline-first reading** | Download books; read, take quizzes, take notes, and do reviews with zero connectivity; sync when back online. | 3 |
| **Real audio narration** | Background playback, lock-screen + Control Center controls, AirPlay, CarPlay, sleep timer, variable speed, offline audio. | 6 |
| **Home-screen widgets** | Streak, "continue reading," progress ring, next-due review — glanceable without opening the app. | 8 |
| **Live Activities + Dynamic Island** | Live reading-session timer; streak-at-risk countdown. | 8 |
| **App Intents + Siri** | "Start my daily reading," "Review now," "Log a chapter" — voice + Shortcuts + Spotlight. | 8 |
| **On-device intelligence** | Apple **Foundation Models** for offline summaries, smart highlight suggestions, and an offline fallback for "Ask the book." A genuine web-impossible feature. | 6 |
| **Premium reading craft** | ProMotion 120Hz scrolling, native text selection → highlights, Dynamic Type, haptics, page-turn feel, true dark/sepia themes. | 2 |
| **Native spaced repetition** | FSRS scheduling with **local notifications** for due cards — works even offline. | 5 |
| **System integration** | Universal Links, Handoff (start on web, continue on phone), Spotlight indexing, Focus filters, Quick Actions. | 8 |
| **Apple-native auth & pay** | Sign in with Apple; StoreKit 2 subscriptions with seamless restore. | 1, 4 |

---

## 2. Architecture

### 2.1 Stack & platform targets

- **Language/UI:** Swift 6 (strict concurrency), SwiftUI, Observation framework.
- **Minimum OS:** iOS 18.0. (Unlocks mature SwiftData, modern StoreKit 2, WidgetKit interactive widgets, ActivityKit, App Intents, Foundation Models on supported devices.)
- **Persistence:** **SwiftData** for the offline content cache + user state; **Keychain** for tokens; **App Group** container shared with widgets/extensions.
- **Auth:** AWS Cognito. Use **AWS Amplify Swift (Auth category)** for robust SRP/refresh/MFA handling, OR a thin custom `InitiateAuth`/`RespondToAuthChallenge` client via `aws-sdk-swift` if you want zero Amplify. **Recommendation: Amplify Auth** (fewer footguns), with **Sign in with Apple** federated into the same Cognito pool.
- **Payments:** StoreKit 2 (async API), products defined in App Store Connect.
- **Push:** APNs via `UserNotifications`; device token registered to the backend.
- **Audio:** AVFoundation (`AVPlayer`) + `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`, background-audio mode.
- **Charts:** Swift Charts (progress/streak visualizations).
- **Images:** Book covers are **emoji + color gradient** (from the API model), so most "covers" are *rendered*, not downloaded — no heavy image pipeline needed. A small `RemoteImage` (URLSession + `URLCache` + `NSCache`) covers any optional remote art.
- **Dependencies:** keep minimal. Amplify (auth) is the only large one. Everything else (networking, image cache, DI) is hand-rolled on the standard library to keep builds fast and the surface small.

### 2.2 Architectural pattern: "MV + Repositories + Actors"

Modern SwiftUI does not need heavy MVVM/VIPER/TCA ceremony. Use:

- **Views** (SwiftUI) observe **Models** (a.k.a. stores): `@Observable @MainActor final class LibraryModel { ... }`. Models hold view state and call repositories.
- **Repositories** are the data boundary: `LibraryRepository`, `ReaderRepository`, etc. They combine **Networking** + **Persistence** and expose async methods returning domain models. Repositories are where offline/online logic lives (read-through cache, outbox writes).
- **Actors** for shared mutable infrastructure that must be thread-safe: `TokenStore` (actor), `DownloadManager` (actor), `SyncEngine` (actor), `APIClient` (actor).
- **Dependency injection:** a single `Dependencies` container built at the app root and injected via SwiftUI `.environment(...)`; models receive the repositories they need through their initializer (constructor injection). No DI framework.
- **Navigation:** `NavigationStack` with **type-safe `Route` enums** and a per-tab `Router` (`@Observable`) owning a `NavigationPath`. A `DeepLinkParser` maps URLs/intents to `Route`s. Root is a `TabView`.

> Why not TCA? It's powerful but adds a large dependency, a steep idiom, and boilerplate that slows a Claude-driven build. The MV+Repository pattern is idiomatic, testable (repositories are protocols you can fake), and fast to generate. If you later want stricter unidirectional flow in one complex feature, you can adopt it locally.

### 2.3 Module map (local SPM packages)

A thin app target composes many small packages. This speeds builds, enforces boundaries, enables per-package previews, and is what makes **parallel track development** clean.

```
ChapterFlowApp (app target — @main, thin composition root only)
│
├── Packages/
│   ├── DesignSystem      — tokens (color/type/spacing/radii/shadow), components, haptics, motion
│   ├── CoreKit           — Logger, AnalyticsClient, FeatureFlags, AppError, Router primitives, utilities
│   ├── Networking        — APIClient(actor), Endpoint, Envelope/Error decoding, auth-token provider hook
│   ├── Persistence       — SwiftData stack, Keychain TokenStore(actor), AppGroup store, migrations
│   ├── Models            — Codable domain models + pure business logic (Entitlement, FSRS, Progress math)
│   ├── AuthKit           — Cognito AuthService + auth UI (sign in/up/verify/reset, Sign in with Apple)
│   │
│   ├── LibraryFeature    — home/library/book-detail, saved
│   ├── ReaderFeature     — the reader (content rendering, themes, highlights, notes, audio hook)
│   ├── QuizFeature       — quiz session, grading, retry, unlock
│   ├── PaywallFeature    — StoreKit, entitlement, paywall, gating
│   ├── EngagementFeature — progress dashboard, streak, badges, tiers, flow points/shop, journeys, events, reviews(FSRS), commitments
│   ├── AIFeature         — ask-the-book, audio narration player, concept graph, depth, on-device intelligence
│   ├── SocialFeature     — profile, pairs, gifts, reflections, share cards, referrals
│   ├── NotificationsFeature — APNs + local notifications + inbox + prefs
│   ├── OnboardingFeature — first-run, depth/tone selection
│   ├── SettingsFeature   — settings, account lifecycle, legal, export
│   └── AppFeature        — TabView root, routing, DI container, deep-link handling
│
└── Targets/
    ├── Widgets           — WidgetKit extension (App Intents config)
    ├── LiveActivity      — ActivityKit (Dynamic Island)
    └── WatchApp          — (stretch) watchOS companion
```

> **Granularity note:** `EngagementFeature`, `AIFeature`, and `SocialFeature` are listed as single packages for the map, but each is built by **many separate prompts** (Section 6) and you may split them into sub-packages (e.g. `StreakFeature`, `ReviewsFeature`) if a track gets large. Splitting further is encouraged — it increases parallelism.

### 2.4 Data flow (read + offline-write)

```
                 ┌─────────────┐     async      ┌──────────────┐
   SwiftUI View ─▶│  @Observable │──── calls ───▶│  Repository  │
        ▲         │    Model     │               └──────┬───────┘
        │ observe └─────────────┘            read-through│
        │                                ┌──────────────┴───────────────┐
        │                                ▼                              ▼
        │                        ┌──────────────┐  offline?     ┌──────────────┐
        └───────── state ────────│  Networking  │◀── online ────│ Persistence  │
                                 │ APIClient act.│               │  (SwiftData) │
                                 └──────┬───────┘                └──────┬───────┘
                                  Bearer│token                   mutations│queued
                                        ▼                                ▼
                                  AWS REST API                     SyncEngine(actor)
                                                                  replays outbox on reconnect
```

**Offline writes** (progress, quiz results, notes, review grades) go to a **SwiftData outbox** with optimistic UI; the `SyncEngine` actor replays them to the API on reconnect, resolving conflicts by `updatedAt`/`progressRev` (server is authority for gating fields — see Section 3).

### 2.5 Concurrency model

- UI models are `@MainActor`. Repositories are actor-isolated or `Sendable` structs that hop to actors for shared state.
- `APIClient`, `TokenStore`, `DownloadManager`, `SyncEngine` are **actors**.
- All domain models are `Sendable` value types (`struct`, `enum`).
- Use structured concurrency (`async let`, `TaskGroup`) for parallel fetches (e.g. dashboard aggregates several endpoints).

---

## 3. Backend contract (API reference) + required server changes

### 3.1 The envelope (verified from the codebase)

- **Success:** HTTP 2xx, body is the **raw data object** the route returns. Examples:
  - `GET /book/books` → `{ "books": BookCatalogItem[] }`
  - `GET /book/books/{id}/chapters/{n}` → `{ "chapter": {...}, "progress": {...} }`
  - `GET /book/me/entitlements` → `{ "entitlement": {...}, "paywall": {...} }`
- **Error:** matching 4xx/5xx, body `{ "error": { "code": string, "message": string, "requestId": string, "details"?: any } }`.
- **Error codes the client must handle specifically:**
  - `401 unauthenticated` → token missing/invalid → route to sign-in.
  - `401 reauth_required` (with `details.reauth === true`) → token valid but too old for a sensitive action → force a fresh login, then retry the original request.
  - `503 verifier_unavailable` → transient auth-verifier outage → **retry with backoff**, do **not** log the user out.
  - `403 forbidden_origin` → CSRF guard (see 3.2 — must be made Bearer-exempt server-side).
  - `429 rate_limited` → show "try again later"; respect for AI ask / scenario submit.
  - `400 invalid_*` → input validation; surface message.

### 3.2 REQUIRED server changes (run these in the WEB repo `~/ChapterFlow`)

These are **prerequisites**. Without B1 the app cannot authenticate; without B2/B3 push and IAP don't work. They are small and surgical.

#### Prompt B1 — Accept Bearer tokens + exempt Bearer-authed requests from the CSRF guard `[SEQUENTIAL, do first]`
```
In the ChapterFlow web repo, the API authenticates by reading the Cognito id_token
from an `id_token` cookie (app/app/api/_lib/auth.ts, requireUser()). Native iOS
clients cannot send cookies and will send `Authorization: Bearer <id_token>` instead.
Also, mutating routes run a same-origin/CSRF guard (app/app/api/book/_lib/http.ts,
requireSameOrigin via withBookApiErrors) that rejects requests lacking a same-origin
Origin/Sec-Fetch-Site — which a native app never sends.

Make these changes WITHOUT weakening browser security:
1. In requireUser() (and any sibling token reader), accept the token from EITHER the
   `id_token` cookie OR an `Authorization: Bearer <token>` header. Cookie stays the
   default for web. Verify the JWT identically (same JWKS, issuer, audience, token_use=id).
2. CSRF is a COOKIE-auth concern only. When a request authenticates via the Bearer
   header (no cookie credential), it is immune to CSRF by construction — so skip the
   same-origin guard for header-authenticated requests. Implement this cleanly: detect
   "auth came from header, not cookie" and bypass requireSameOrigin for that request,
   while cookie-authed mutations keep the guard exactly as today.
3. Do NOT broaden CORS (native apps don't need it) and do NOT accept the access_token
   as identity.
Add unit tests: (a) a Bearer-authed GET and PATCH succeed with no Origin header;
(b) a cookie-authed cross-site POST is still rejected; (c) an invalid Bearer token
yields 401 invalid_token. Keep all existing auth tests green. Explain the security
rationale in code comments.
Definition of Done: a Bearer-authed GET and PATCH succeed with NO Origin header; a cookie-authed cross-site
POST is still rejected (403); an invalid/expired Bearer → 401 invalid_token; all prior auth + CSRF tests green.
```

#### Prompt B2 — APNs device tokens `[needed before Phase 9]`
```
Today device tokens are web-push only: BookUserDeviceTokenItem has platform: "web"
and keys {p256dh, auth} (app/app/api/book/_lib/types.ts), and /book/me/devices/register
expects a web-push subscription. Extend the model and the register/unregister routes to
ALSO accept Apple Push Notification service (APNs) device tokens from iOS:
- Add platform "ios" and an apnsToken (hex string) shape; make the web-push keys optional
  when platform === "ios".
- /book/me/devices/register accepts { platform: "ios", apnsToken } and upserts it keyed
  per user+token; /unregister removes by token.
- Wherever the backend SENDS push (the push-service that currently uses web-push/VAPID),
  branch on platform: send via APNs (HTTP/2, token-based auth with your APNs key) for
  iOS tokens, web-push for web tokens. Add an APNS_KEY_ID / APNS_TEAM_ID / APNS_AUTH_KEY /
  APNS_BUNDLE_ID env config (document in docs/ENVIRONMENT.md). If you only stub the send
  path, clearly mark it TODO and keep registration working end-to-end.
Add tests for the new register/unregister shapes and platform branching. Keep web-push working.
Definition of Done: POST /devices/register accepts {platform:"ios",apnsToken} and upserts it; unregister
removes it; the send path branches APNs vs web-push by platform; web-push still works; tests green.
```

#### Prompt B3 — StoreKit 2 server validation → entitlement `[needed before Phase 4 ships]`
```
The app sells "Pro" today via Stripe; entitlements live in BookUserEntitlement
(plan FREE/PRO, proSource "stripe"|"license"|"flow_points"|"gift_code"|"admin"), written
by stripe-entitlement-write-core.ts from Stripe webhooks. Apple requires in-app digital
subscriptions to use StoreKit/In-App Purchase. Add an Apple purchase path that grants the
SAME entitlement:
1. New route POST /book/me/billing/apple/verify: body { transactionJWS } (a StoreKit 2
   signed transaction / JWS). Verify the JWS against Apple's root certs, extract the
   product id + expiry + originalTransactionId, and write the entitlement with a new
   proSource "apple" (add it to the union), setting plan PRO, proStatus active, and
   currentPeriodEnd = Apple expiry. Make it idempotent on originalTransactionId.
2. New route POST /book/me/billing/apple/notifications: an App Store Server Notifications
   V2 webhook (signedPayload JWS). Handle SUBSCRIBED / DID_RENEW / EXPIRED / DID_CHANGE_RENEWAL_STATUS
   / REFUND etc., updating proStatus/currentPeriodEnd/cancelAtPeriodEnd. Reject out-of-order
   events by signedDate, mirroring the lastStripeEventAt high-water-mark pattern.
3. Entitlement read (/book/me/entitlements) needs no change — it already returns the merged
   view. Ensure a user can hold at most one active source; if both Stripe and Apple are
   active, prefer the most recent and note it.
Add env config (APPLE_BUNDLE_ID, APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY,
APP_STORE_SHARED_SECRET as needed) and tests for JWS verification (happy path + tampered
+ expired) and the notification state machine. Document the App Store Connect setup steps.
Definition of Done: an Apple StoreKit transaction JWS verifies and grants PRO via proSource "apple";
the ASSN webhook drives renew/expire/refund correctly and rejects out-of-order events; idempotent on
originalTransactionId; JWS verification tests (happy/tampered/expired) green; existing Stripe path untouched.
```

#### Prompt B4 — (optional) iOS mobile-config endpoint `[nice-to-have, Phase 0/10]`
```
Add GET /book/config/ios returning { minSupportedVersion, latestVersion, featureFlags:{...},
storeKitProductIds:[...], maintenanceMode:bool, messageOfTheDay?:string }. The app reads it
at launch to drive force-update prompts, kill-switch feature flags, and the StoreKit product
list without an app release. Public, cacheable (max-age 300). Add a test.
Definition of Done: GET /book/config/ios returns the documented shape, is public + cacheable, and has a test.
```

### 3.3 Endpoint catalog (the 74 user-facing routes, grouped)

The app consumes these. Base path `/app/api` (the API is double-nested in the web repo; the public path is `/api`). All require `Authorization: Bearer` unless marked public.

**Auth / identity**
- `GET /auth/session` → `{ loggedIn, user }` (or `{loggedIn:false}` / `{loggedIn:null}` on 503)
- `GET /me` → current user/profile summary
- `GET /book/me/is-admin` → `{ isAdmin }`

**Catalog / content** (content GETs are cacheable)
- `GET /book/books` (public, cacheable) → `{ books: BookCatalogItem[] }`
- `GET /book/books/{bookId}` → book detail + manifest
- `GET /book/books/{bookId}/chapters/{n}` → `{ chapter, progress }` (chapter incl. `contentVariants`, `examples`, `implementationPlan`, `reviewCards`, `keyTakeawayCard`, `v21Extras`; supports `?mode=<variant>`)
- `GET /book/books/{bookId}/chapters/{n}/quiz` → `{ quiz (client session), progress }` (supports `?tone=`)
- `GET /book/books/{bookId}/chapters/{n}/audio` → narration audio (stream/URL)
- `GET /book/books/{bookId}/concept-graph` → `ConceptGraph`
- `GET /book/books/{bookId}/metrics`, `GET /book/books/journeys`, `GET /book/search-index`

**Reading state & progress** (the core loop)
- `POST /book/me/books/{bookId}/start` — start/own a book (consumes a free slot or requires Pro)
- `GET|PATCH /book/me/books/{bookId}/state` → `{ state: BookUserBookStateItem, applicationStates }` (PATCH moves cursor only; gating is server-truth)
- `POST /book/me/books/{bookId}/state/reset`
- `GET /book/me/progress`, `GET /book/me/progress/{bookId}`
- `GET|PATCH /book/me/books/{bookId}/chapters/{n}/state` — per-chapter UI state (notes/scroll)
- `POST /book/me/chapters/{bookId}/{n}/unlock` — quiz-gated unlock
- `GET /book/me/books/{bookId}/depth-recommendation`
- `GET|POST /book/me/books/{bookId}/chapters/{n}/scenarios`
- `POST /book/me/reading-sessions` — session start/heartbeat/end (time tracking)

**Quiz**
- `POST /book/me/quiz/{bookId}/{n}/submit` — submit attempt → graded `QuizAttemptItem`
- `POST /book/me/quiz/{bookId}/{n}/check` — single-answer check
- `POST /book/me/quiz/{bookId}/{n}/events`

**Monetization**
- `GET /book/me/entitlements` → `{ entitlement, paywall:{ price, pricingTiers, benefits } }`
- `POST /book/billing/checkout-session`, `POST /book/billing/portal-session` (web/Stripe — iOS uses StoreKit + B3)
- `GET /book/billing/license`, `POST /book/me/tier`

**Engagement / gamification**
- `GET /book/me/dashboard`, `GET /book/me/streak`, `GET /book/me/badges`
- `GET /book/me/flow-points`, `POST /book/me/flow-points/redeem`, `GET /book/me/shop`
- `GET|POST /book/me/journeys/{journeyId}` (+ `/start`), `GET /book/me/journeys/{id}`
- `GET /book/events/active`, `POST /book/me/events/{eventId}/join`, `GET|POST /book/me/events/{eventId}/progress`
- `GET|POST /book/me/commitments`, `GET|PATCH /book/me/commitments/{id}`
- `GET /book/me/reviews`, `GET|POST /book/me/reviews/{cardId}` (FSRS spaced repetition)
- `GET|POST /book/me/saved`, `GET|POST /book/me/notebook`

**Social**
- `GET /book/me/profile`, `PATCH /book/me/settings`
- `GET /book/me/pairs`, `POST /book/me/pairs/invite`, `POST /book/me/pairs/accept/{code}`, `GET|DELETE /book/me/pairs/{partnerId}`, `POST /book/me/pairs/{partnerId}/nudge`
- `GET /book/me/gifts/{code}`, `POST /book/me/gifts/{code}/claim`
- `GET|POST /book/me/reflections/{bookId}/{n}`, `POST /book/me/reflections/{bookId}/{n}/feedback`
- `POST /book/me/share-events`

**AI**
- `POST /book/books/{bookId}/ask` — AI Q&A (daily-limited, returns answer + citations)

**Notifications / devices**
- `GET /book/me/notifications`, `POST /book/me/notifications/read-all`
- `POST /book/me/devices/register`, `POST /book/me/devices/unregister`, `GET /book/me/devices/vapid-key` (web only)
- `GET|PATCH /book/me/settings` (notification prefs live here)

**Account**
- `POST /book/me/account/deactivate`, `POST /book/me/account/delete`, `GET /book/me/export`
- `POST /book/me/onboarding/progress`, `POST /book/me/onboarding/complete`
- `GET /book/me/entitlements`, `GET /book/me/analytics/track`, `POST /book/me/analytics/beacon`

### 3.4 The content model (critical for the Reader — verified from `types.ts`)

A chapter's teaching content is **tone-keyed** and **variant-keyed**. The Reader must handle this:

- `chapter.contentVariants` is a map of **reading-depth variant** → content. Variant keys: `easy | medium | hard` (EMH family) or `precise | balanced | challenging` (PBC family). The reader switches depth client-side without refetching.
- Within a variant, modern fields are **tone-keyed**: `ToneKeyed = { gentle, direct, competitive }`. The user's tone preference selects which string to show. Fields include `chapterBreakdown`, `keyTakeaways[].point`, `oneMinuteRecap`, `activationPrompt`, `selfCheckPrompts`, `reflectionPrompts`.
- `chapter.v21Extras` (optional) drives premium reader chrome: `hook`, `counterintuition`, `tryThisNow`, `keyTakeaway`, `memorableLines[]`, and `experiencePlan` (failure-recovery, transfer-prompt, behavior-loop "which pattern fits you?").
- `chapter.examples[]`: each has `scenario`, `whatToDo`, `whyItMatters` (each `string | ToneKeyed`).
- `chapter.implementationPlan`: tone-keyed `coreSkill`, `concreteAction`, `ifThenPlans`, `twentyFourHourChallenge`, etc.
- `chapter.reviewCards[]` and `keyTakeawayCard`: feed spaced repetition.
- **Quiz** (`/quiz`): the server returns a **client session** with questions; each question has `questionId`, a stem/`prompt`, `choices`/`options`, and a server-managed **choiceId scheme**. Submit selected `choiceId`/`selectedIndex` to `/submit`; the server grades and returns `questionResults` with `correctChoiceId`/`isCorrect`, plus `passed`, `cooldownSeconds`, `nextEligibleAttemptAt`, `unlockedNextChapter`. **Do not grade client-side** — the server is authority.

> The full Codable model set is in **Appendix A**. The single most important reader rule: **resolve `(variant, tone)` → display string** in one place (`ChapterContentResolver` in `Models`) and render from that, so depth/tone switches are instant.

---

## 4. Engineering conventions

- **Naming:** Types `UpperCamel`; properties/functions `lowerCamel`. Models suffix UI state types `…Model` (e.g. `ReaderModel`), data boundaries `…Repository`, network `…Endpoint`. Match server field names in Codable via `CodingKeys` (server uses `lowerCamel` already, so default decoding mostly "just works").
- **Errors:** one `AppError` enum in `CoreKit` (`.unauthenticated`, `.reauthRequired`, `.verifierUnavailable`, `.rateLimited(retryAfter:)`, `.offline`, `.server(code:message:requestId:)`, `.decoding`, `.notFound`). `Networking` maps the error envelope → `AppError`. Views render errors via a shared `ErrorView`/`Toast`.
- **Async:** every I/O method is `async throws`. No completion handlers. Cancel tasks on view disappear where relevant.
- **Testing:** `swift-testing` (the `Testing` framework) for unit tests; XCUITest for 3–4 critical end-to-end flows; snapshot tests for the design system. Repositories are protocols with in-memory fakes for fast tests.
- **Previews:** every view has a `#Preview` using fake repositories + sample data fixtures (a `Fixtures` module/target with canned JSON decoded into models).
- **Git:** one branch per prompt (`feat/p2-4-reader`), PR titled with the prompt id. Keep PRs small. `main` always builds.
- **Secrets:** `Secrets.xcconfig` (gitignored) holds `API_BASE_URL`, Cognito pool/client ids, APNs/StoreKit ids. A `Secrets.example.xcconfig` is committed.
- **Accessibility from day one:** every interactive element has an accessibility label; the reader supports Dynamic Type; respect Reduce Motion.

---

## 5. Roadmap: phases, dependency graph & parallelization map

### 5.1 Phase overview

| Phase | Theme | Sequencing | Depends on |
|---|---|---|---|
| **B** | Backend prerequisites (web repo) | B1 first; B2/B3 before their phases | — |
| **0** | Foundations (project, design system, networking, persistence, core, routing) | P0.1 first, then 0.2–0.6 **parallel** | B1 |
| **0B** | Cross-cutting foundations (icon, localization, iPad/adaptive, images, lifecycle, background tasks, UI-states, security, schemes, fixtures, CI) | P0.7–P0.17 **highly parallel** | P0.1 |
| **1** | Auth & identity (incl. credential mgmt, resilience) | mostly sequential | P0, B1 |
| **2** | Core reading loop (models, library, search, discovery, **reader P2.4a–e**, quiz, ToC, sessions) | P2.1 first, then partial parallel | P0, P1 |
| **3** | Offline & sync | sequential after reader | P2 |
| **4** | Monetization (StoreKit, paywall, gating) | parallel track after P1 | P1, P2.1, B3 |
| **5** | Engagement & gamification | **highly parallel** pod | P1, P2.1 |
| **6** | AI features (ask, audio, concept graph, on-device) | **parallel** pod | P1, P2 |
| **7** | Social (profile, pairs, gifts, reflections, share) | **parallel** pod | P1, P2.1 |
| **8** | Advanced native (widgets, Live Activities, App Intents, Spotlight, deep links) | **parallel** pod | data from P2/P5/P6 |
| **9** | Notifications (APNs + local + inbox) | parallel track | P1, B2 |
| **10** | Quality, settings, onboarding, accessibility, perf, App Store | finishing; accessibility/testing **continuous** | all |

### 5.2 Dependency graph (critical path in **bold**)

```
B1
 │
 ▼
**P0.1** ─► P0.2 ─┐
          P0.3 ─┤ (0.2–0.6 run in parallel once 0.1 lands)
          P0.4 ─┤
          P0.5 ─┤
          P0.6 ─┘
              │
              ▼
        **P1.1 ─► P1.4 ─► P1.5**     (P1.2 Apple-sign-in & P1.3 auth UI parallel to each other)
              │
              ▼
        **P2.1 (models)**
        ┌───────────────┬───────────────┬────────────────────────────────────┐
        ▼               ▼               ▼                                    (fan-out parallel tracks)
   **P2.4 Reader**   P2.2 Library    P2.6 Quiz          Track C: P4.* (StoreKit/paywall)   [needs B3]
        │            P2.3 Detail     P2.7 Sessions      Track D: P5.* (engagement pod)
        ▼                                               Track E: P6.* (AI/audio pod)
   **P2.5 Highlights**                                  Track F: P7.* (social pod)
        │                                               Track H: P9.* (push)               [needs B2]
        ▼
   **P3.* Offline/Sync**
        │
        ▼          Track G: P8.* (widgets/intents) — consumes P5/P6 data, build after those land
   **P10 Launch**  P10 accessibility/testing run CONTINUOUSLY alongside all tracks
```

### 5.3 Parallelization map — what to build concurrently

Once **P0** and **P1** are done and **P2.1 (models)** exists, you can run up to **6 Claude-in-Xcode sessions in parallel**, each on its own branch:

| Track | Prompts | Can start after | Notes |
|---|---|---|---|
| **Foundation** | P0.1 → P0.2–P0.6 + P0.7–P0.17 (Phase 0B) | B1 | P0.1 first; the rest highly parallel. Build P0.16 fixtures right after P2.1 models. |
| **A — Critical path** | P2.1 → P2.4a–e → P2.5 → P2.6 → P2.7 → P3.1–P3.7 | P1 done | The reading + offline spine. Highest priority; build the reader units (P2.4a–e) in order. |
| **B — Auth** | P1.1–P1.7 | P0, B1 | Gates everything; finish first. |
| **C — Monetization** | P4.1–P4.7 | P1 + P2.1 (+B3) | Independent of the reader; P4.4 gating integrates after P2.3; P4.7 reconciles web/iOS Pro. |
| **D — Engagement** | P5.1–P5.13 | P1 + P2.1 | The most parallel pod — split into 2–3 sessions. Build P5.12 celebrations early (shared). |
| **E — AI** | P6.1–P6.7 | P1 + P2 | Audio (P6.2/P6.6 CarPlay) is large; on-device (P6.5) is optional polish. |
| **F — Social** | P7.1–P7.8 | P1 + P2.1 | Profile (P7.1) first; P7.7 safety is REQUIRED before social ships to review. |
| **G — Advanced native** | P8.0–P8.10 | P5/P6 data exists | P8.0 shared-state first; widgets/controls need streak/continue data. |
| **H — Notifications** | P9.1–P9.7 | P1 + B2 | P9.5 priming before prompting; P9.3 local-notifs pair with P5.9/P5.10. |
| **(continuous)** | P10.3 a11y, P10.4 perf, P10.5 tests, P10.11–P10.13 QA/security | alongside all | Apply throughout, not just at the end. |

**Recommended cadence:** Weeks 1–2 Tracks A+B (foundation+auth+reader spine). Then fan out C/D/E/F in parallel while A finishes offline. Then G/H. Then Phase 10 hardening. **Phase 10 accessibility + testing should be applied continuously**, not saved for the end.

### 5.4 Execution lanes (the definitive map)

A **lane** is a coherent track of work owned by one Claude session at a time. **Within a lane**, prompts run in the listed order: `→` = strictly sequential, `[a, b, c]` = parallelizable among themselves (separate worktrees, any order). **Across lanes**, work runs in parallel, subject only to the cross-lane gates noted (e.g. most lanes wait for `P2.1` models). Branch each prompt per the Envelope (worktree = prompt id).

```
LANE F · Foundation        P0.1 → [P0.2 P0.3 P0.4 P0.5 P0.6 P0.7 P0.8 P0.9 P0.10
                                    P0.11 P0.12 P0.13 P0.14 P0.15 P0.17] → P0.16*
   └ web repo (parallel):  B1 → [B2 B3 B4]                         (*P0.16 after P2.1)

LANE A · Auth              P1.1 → [P1.2 P1.3] → P1.4 → P1.5 → [P1.6 P1.7]
                              (gate: P0.1–P0.6, B1)

LANE R · Reading spine     P2.1 → [P2.2 P2.3] → P2.4a → P2.4b → P2.4c → P2.4d → P2.4e
   ★ CRITICAL PATH ★            → P2.5 ;  P2.6 ∥(after P2.1) ;  P2.7(after 2.4e+2.6)
                              → [P2.8 P2.9 P2.10 P2.11]
                              → P3.1 → P3.2 → P3.3 → P3.4 → [P3.5 P3.6 P3.7]
                              (gate: Lane A done, P2.1 first)

LANE M · Monetization      P4.1 → P4.2 → [P4.3 P4.5 P4.6 P4.7] → P4.4   (gate: P1, P2.1, B3)

LANE E · Engagement        [P5.1 P5.12] → [P5.2 P5.3 P5.4 P5.5 P5.6 P5.7 P5.8 P5.9
                                            P5.10 P5.11 P5.13]          (gate: P1, P2.1)

LANE I · AI                [P6.1 P6.3 P6.4] ;  P6.2 → P6.6 ;  P6.7(after 6.1) ;
                            P6.5(optional)                              (gate: P1, P2)

LANE S · Social            P7.1 → [P7.2 P7.3 P7.4 P7.5 P7.6 P7.8] ;  P7.7(required) (gate: P1, P2.1)

LANE N · Advanced native   P8.0 → [P8.1 P8.2 P8.3 P8.4 P8.5 P8.6 P8.9 P8.10] ;
                            [P8.7 P8.8] stretch        (gate: streak/continue/audio data from E,I)

LANE P · Notifications     P9.5 ∥ P9.1 → P9.2 → [P9.3 P9.4 P9.6 P9.7]   (gate: P1, B2)

LANE Q · Quality / Launch  continuous: [P10.3 P10.4 P10.5 P10.11 P10.12 P10.13]
                            mid:        [P10.1 P10.2 P10.6]
                            pre-launch: [P10.8 P10.9 P10.10]
                            submission: P10.14 → P10.7 → P10.15 → P10.16   (sequential, last)
```

### 5.5 Wave-by-wave run order (what is safe to run at once)

Run top-to-bottom. Everything inside a wave's "Run in parallel" cell can execute concurrently (one worktree each). A wave's **Gate** must be merged before the wave starts.

| Wave | Run in parallel (one worktree per prompt) | Gate (must be done first) | Max sessions |
|---|---|---|---|
| **0 · Backend** | `B1`, then `B2` `B3` `B4` (web repo) | — | 1–3 |
| **1 · Bootstrap** | `P0.1` only — **hard sequential gate** | B1 merged | 1 |
| **2 · Foundation** | `P0.2`–`P0.15`, `P0.17` + start `P1.1` | P0.1 | up to ~8 |
| **3 · Auth + Models** | finish Lane A (`P1.1→1.4→1.5`, +`1.2/1.3/1.6/1.7`); build `P2.1`; then `P0.16` | P0.* foundation | 2–4 |
| **4 · Feature fan-out** | **Lane R** (`P2.2…P2.11`, priority) ∥ **Lane M** ∥ **Lane E** ∥ **Lane I** ∥ **Lane S** ∥ **Lane P** | P1, P2.1 | **up to 6** |
| **5 · Offline + integrate** | Lane R `P3.1…P3.7` (critical path tail) ∥ `P4.4` gating ∥ INT-2/INT-5/INT-6/INT-7 checkpoints | reader spine (P2.4e+) | 3–5 |
| **6 · Advanced native** | **Lane N** `P8.0…P8.10` | streak/continue/audio data (E, I) | 2–4 |
| **7 · Launch** | INT-3/INT-9/INT-10, then Lane Q **submission** chain `P10.14→P10.7→P10.15→P10.16` | all features merged | 1–2 |
| **continuous** | **Lane Q** a11y `P10.3` · perf `P10.4` · tests `P10.5` · QA `P10.11–P10.13` | runs **throughout** Waves 4–7 | +1 |

**If you run solo (one session):** walk the **critical path** — Wave 0 → P0.1 → enough of Lane F (P0.2–P0.6, P0.10, P0.13, P0.16) → Lane A → P2.1 → Lane R (reader→quiz→offline) → P4 → then pick up E/I/S/N/P lanes → Lane Q → submit. Defer P0.7/0.8/0.9/0.11/0.12/0.14/0.15 and the stretch P8.7/8.8 until after the core loop works.

**If you run a crew (parallel sessions):** Wave 4 is your peak — up to **6 lanes at once** plus the continuous Lane Q. Always **merge Lane R first** each wave and rebase the other lanes onto it (it owns the shared models/reader). Keep one session permanently on Lane Q so accessibility, performance, and tests never fall behind the feature work.

---

## 6. The prompt library

> **READ THIS FIRST — how to run every prompt.** Each entry below has an **ID**, a **tag** (lane/sequencing), a **dependency**, and a fenced **TASK**. The TASK is the *work*, not the whole prompt. To run it, wrap it in the **Prompt Envelope** below — the Envelope supplies the **role, the git worktree, the context, and the mandatory test/verification standard** so every prompt you send is complete and self-isolating. Fill the four `<…>` slots from the prompt's header line, paste the fenced TASK into the `<TASK>` slot, and send the whole thing to Claude in Xcode. The Envelope is what makes all 120 tasks "complete prompts."

#### ▶ The Prompt Envelope (prepend to EVERY task — `P…` and `B…`)

```
████ CHAPTERFLOW iOS — PROMPT ENVELOPE ████

ROLE
You are a senior iOS engineer building ChapterFlow, a premium native app in Swift 6 +
SwiftUI (iOS 18+). You hold an Apple "Pro" quality bar: calm, typographic, first-party-
feeling. You write production-grade, fully-tested, accessible, concurrency-safe code,
and you DO NOT STOP until the Definition of Done passes and tests are green.
(For a `B…` backend task, instead: "You are a senior TypeScript/Next.js engineer working
in the ChapterFlow WEB repo (~/ChapterFlow); make the change without weakening security.")

WORKTREE  — do this BEFORE writing any code (keeps parallel prompts from colliding)
  git worktree add ../cf-ios-<ID> -b feat/<ID> <BASE>
  cd ../cf-ios-<ID>
    • <ID>   = this prompt's id, lowercased+hyphenated (e.g. p2-4a, p5-9, b1)
    • <BASE> = origin/main — EXCEPT a critical-path task that builds on an unmerged
               predecessor: branch from that predecessor's branch (see "depends:").
  Do ALL work in this worktree; commit in small, logical steps.

CONTEXT  — load before coding
  • Read repo CLAUDE.md and docs/PLAN.md — especially §2 Architecture, §3 API contract +
    envelope, §4 Conventions, and Appendix A models. Obey them; invent no new patterns.
  • Package/target you are building: <PACKAGE>.
  • Already built, available to depend on: <DEPENDS>.
  • API rules: success body = raw JSON object; error = {error:{code,message,requestId}};
    auth = `Authorization: Bearer <id_token>`. Use DesignSystem tokens — never hardcode
    colors/spacing/fonts. All I/O is `async throws`; UI models are `@MainActor @Observable`.
  • If something required is missing or ambiguous, state the assumption and proceed with
    the most idiomatic choice — do not block or stub silently.

TASK
<paste the fenced TASK body from the prompt below>

TESTS & VERIFICATION  — mandatory; part of "done", not optional
  • Write unit tests (Testing framework) for ALL non-trivial logic, covering every case
    the task names; use the Fixtures module (P0.16) for sample data.
  • Add #Preview(s) for every view (light + dark + one accessibility text size) and
    confirm they render; in Xcode, capture the Preview to visually verify UI tasks.
  • Run `xcodebuild build` AND `xcodebuild test` for the app + this package — BOTH green,
    no new warnings. Run SwiftLint/swift-format clean.
  • Manually verify EACH acceptance criterion in the Definition of Done on the simulator
    (or a real device when the task says "on device").

DEFINITION OF DONE
  The task's "Definition of Done:" line is your acceptance checklist. Do not hand back or
  open the PR until every item is literally true and all tests pass.

DELIVER
  Commit, push `feat/<ID>`, open a PR titled "<ID> — <prompt title>" summarizing what you
  built and exactly what you tested + verified. Then `git worktree remove` the worktree.

████ END ENVELOPE — the specific TASK follows ████
```

**Slot-fill convention:** `<ID>` and `<prompt title>` come from the `####` header; `<PACKAGE>` from the `· package:`/`· target:` tag; `<DEPENDS>` from the `depends:` tag (plus the Foundation packages, which are always available). Example for **P2.6**: `<ID>=p2-6`, `<PACKAGE>=QuizFeature`, `<DEPENDS>=Models (P2.1), Networking, DesignSystem`, `<BASE>=origin/main`.

**Worktree layout & merge order:** each prompt lives in `../cf-ios-<id>/`. Within a wave, **merge the critical-path lane (Lane R) first**, then rebase the feature lanes on it before merging. Run the order/parallelism from the **Lane & Wave map in §5.4–§5.5**.

> Every task below ends with a **Definition of Done:** line — that is its built-in verification checklist. The Envelope above turns each task into a complete, role-bound, isolated, test-gated prompt.

### Phase 0 — Foundations

#### P0.1 — Project & package scaffold `[SEQUENTIAL — do this first]` · depends: B1
```
Create a new iOS app project "ChapterFlow" from scratch with this structure:
- App target "ChapterFlow", @main App entry, iOS 18.0 deployment target, Swift 6 language
  mode with strict concurrency = complete. Bundle id com.chapterflow.ios (adjust to mine).
- A local Swift Package workspace under Packages/ with EMPTY but compiling packages:
  DesignSystem, CoreKit, Networking, Persistence, Models, AuthKit, LibraryFeature,
  ReaderFeature, QuizFeature, PaywallFeature, EngagementFeature, AIFeature, SocialFeature,
  NotificationsFeature, OnboardingFeature, SettingsFeature, AppFeature. Each package has a
  Sources/<Name> folder with a placeholder public symbol and a Tests/<Name>Tests target
  using the Testing framework. Wire AppFeature to depend on the others as the composition root.
- The app target depends only on AppFeature and renders a placeholder TabView with 5 tabs
  (Home, Library, Reviews, Profile, Settings) using SF Symbols.
- Add Secrets.xcconfig (gitignored) with API_BASE_URL, COGNITO_REGION, COGNITO_USER_POOL_ID,
  COGNITO_CLIENT_ID placeholders, and a committed Secrets.example.xcconfig. Surface these in
  an AppConfig struct in CoreKit read from Info.plist (xcconfig-injected). 
- Add a .gitignore for Xcode/SPM, an App Group entitlement (group.com.chapterflow) on the app
  target for future widgets, and a CLAUDE.md at the repo root containing the Shared Context
  Preamble and conventions from docs/PLAN.md.
- Configure build settings: enable strict concurrency, treat warnings as errors off for now,
  and add SwiftLint optional config.
Definition of Done: `xcodebuild build` succeeds for the app and every package; the app launches
in the simulator showing the 5-tab shell; all placeholder test targets pass; CLAUDE.md exists.
```

#### P0.2 — Design system `[PARALLEL: after P0.1]` · package: DesignSystem
```
Build the DesignSystem package — the foundation of an Apple "Pro"-grade look (calm, typographic,
content-first, like Apple's own apps). Deliver:
- TOKENS as static namespaces: Color (semantic: background, surface, surfaceElevated, textPrimary,
  textSecondary, textTertiary, accent, success, warning, danger, separator — all with light AND
  dark values via asset catalog or dynamic UIColor), Typography (a type scale mapped to Dynamic
  Type text styles: largeTitle, title, title2, headline, body, callout, subheadline, footnote,
  caption — using a refined serif for reading body if available, SF Pro for UI; expose
  .scaledFont helpers that respect Dynamic Type), Spacing (4-pt grid: xs=4…xxl=48), Radius,
  Shadow (subtle elevation set), and Motion (standard durations + springs, all gated by Reduce Motion).
- HAPTICS helper (Haptics.tap/success/warning/selection) wrapping UIFeedbackGenerator.
- CORE COMPONENTS, each with #Preview in light+dark+Dynamic-Type-XXL: PrimaryButton, SecondaryButton,
  IconButton, Card, Tag/Pill, Avatar, ProgressRing, LinearProgressBar, Skeleton (shimmer),
  EmptyState, Toast, BottomSheet container, SegmentedControl, and a Badge view. Buttons must have
  pressed-state scale + haptic, full Dynamic Type, and 44pt min tap targets.
- A ThemeMode (system/light/dark) environment value + modifier.
Everything is token-driven; no literal colors/sizes in components. Provide a DesignSystemGallery
view that lists all components for visual QA.
Definition of Done: package builds; the gallery preview renders all components in light/dark and at
the largest Dynamic Type size without clipping; haptics fire in the simulator log.
```

#### P0.3 — Networking `[PARALLEL: after P0.1]` · package: Networking · depends: B1
```
Build the Networking package: a typed async API client for the ChapterFlow REST API.
- APIClient is an actor with `func send<T: Decodable>(_ endpoint: Endpoint) async throws -> T`.
- Endpoint: a value type capturing method, path, query items, optional Encodable body, and whether
  auth is required. Build URLRequests against AppConfig.apiBaseURL.
- AUTH: APIClient holds a `TokenProviding` dependency (async `validToken() async throws -> String?`
  and `refresh()`); inject the Cognito id_token as `Authorization: Bearer <token>` when auth is
  required. (TokenProviding is implemented later in AuthKit; define the protocol here.)
- ENVELOPE: success bodies are the raw JSON object; decode directly into T. On non-2xx, decode
  `{ "error": { code, message, requestId, details } }` and throw a mapped AppError (from CoreKit):
  401 unauthenticated→.unauthenticated; 401 with details.reauth→.reauthRequired; 503
  verifier_unavailable→.verifierUnavailable; 429→.rateLimited; 403 forbidden_origin→.forbidden;
  400 invalid_*→.invalidInput(message); else→.server(...). Network/offline errors→.offline.
- RESILIENCE: automatic one-time token refresh + retry on 401 unauthenticated; exponential backoff
  retry (max 3) on .verifierUnavailable and transient URLErrors; respect Retry-After on 429.
- JSON: a shared JSONDecoder/JSONEncoder config (ISO8601 dates; the API uses ISO strings and
  lowerCamel keys). 
- A `MockAPIClient`/protocol so features can be tested without the network, plus a request logger
  (debug only).
Define Endpoints as an enum or namespaced static factory for at least: getSession, getBooks,
getBook(id), getChapter(bookId,n,mode), getQuiz(bookId,n,tone), getEntitlements. (More added per feature.)
Definition of Done: package builds; unit tests cover envelope decode, each error-code mapping, the
401-refresh-retry path, and backoff — all green using a stubbed URLProtocol.
```

#### P0.4 — Persistence `[PARALLEL: after P0.1]` · package: Persistence
```
Build the Persistence package:
- SwiftData stack: a ModelContainer factory with a configurable schema (features register their
  @Model types). Store in the App Group container (group.com.chapterflow) so widgets can read it.
  Provide a `PersistenceController` with main + background contexts and migration plan scaffolding.
- TokenStore: an actor that stores/loads/deletes the Cognito tokens (id, access, refresh) in the
  KEYCHAIN (kSecClassGenericPassword, accessible afterFirstUnlock, App Group access). Expose
  async get/set/clear and a tokens-changed AsyncStream.
- Preferences: an @Observable AppPreferences backed by UserDefaults in the App Group (reading tone:
  gentle/direct/competitive; depth variant; theme mode; reader font scale; audio speed; reminder time).
- A small KeyValueStore wrapper and a FileStore for downloaded audio/content blobs (Application
  Support, excluded from iCloud backup where large).
Definition of Done: package builds; tests verify Keychain round-trip (set/get/clear), SwiftData
container boots with a sample @Model, and AppPreferences persists across instances.
```

#### P0.5 — CoreKit (errors, logging, analytics, flags) `[PARALLEL: after P0.1]` · package: CoreKit
```
Build CoreKit, the shared foundation used by all packages:
- AppError: the canonical error enum (.unauthenticated, .reauthRequired, .verifierUnavailable,
  .rateLimited(retryAfter:), .forbidden, .offline, .invalidInput(String), .notFound,
  .server(code:String,message:String,requestId:String?), .decoding(Error)). Conform to
  LocalizedError with user-facing messages.
- Logger: a thin wrapper over os.Logger with subsystem/category helpers and privacy-aware logging.
- AnalyticsClient: a protocol with `track(_ event: AnalyticsEvent)` + `beacon(...)`, and a default
  implementation that POSTs to /book/me/analytics/track and /book/me/analytics/beacon (batched,
  best-effort, never throws to the UI). Define a typed AnalyticsEvent enum for key funnels
  (app_open, sign_in, book_started, chapter_opened, quiz_submitted, paywall_viewed, purchase, etc.).
- FeatureFlags: an @Observable provider seeded from /book/config/ios (B4) with safe local defaults,
  so flags work offline and before first fetch.
- Router primitives: a generic `Routed` protocol, a `Router` @Observable owning a NavigationPath,
  and a DeepLink type. (Concrete routes live in AppFeature/features.)
- Small utilities: Debouncer, AsyncRetry, RelativeDate formatting, Result+async helpers.
Definition of Done: builds; tests cover AppError messages, analytics batching/non-throwing behavior,
and feature-flag default fallback.
```

#### P0.6 — Navigation & app shell `[PARALLEL: after P0.1, integrates P0.2/0.5]` · package: AppFeature
```
Build the AppFeature composition root and navigation:
- A Dependencies container (struct holding APIClient, TokenStore, AppPreferences, AnalyticsClient,
  FeatureFlags, and the repositories as they come online) created once at app start and injected via
  SwiftUI .environment. Provide a preview/mocked Dependencies for previews.
- Route enums per tab (HomeRoute, LibraryRoute, ReviewsRoute, ProfileRoute, SettingsRoute) and a
  TabRouter (@Observable) with one NavigationPath per tab + selectedTab. Each tab is a NavigationStack
  driven by its router with a `navigationDestination` switch.
- A DeepLinkParser mapping URLs (chapterflow://book/{id}/chapter/{n}, /pair/accept/{code},
  /gift/{code}, /review, etc.) and userActivity to Routes; route them into the correct tab/path.
- A RootView that shows: a Splash while auth state resolves, then either the AuthFlow (from AuthKit,
  stubbed for now) or the MainTabView. Wire the DesignSystem theme + Toast presenter at the root.
- An AppRootModel (@Observable) that owns app lifecycle: on launch, resolve session, fetch config,
  kick off sync.
Use placeholder feature screens for now (real ones replace them in later phases).
Definition of Done: builds and runs; tabs switch; a test deep link (paste a chapterflow:// URL via
`xcrun simctl openurl`) navigates to the right tab/screen; splash→shell transition works.
```

> **Integration checkpoint INT-0:** Open a fresh Claude session: "Wire P0.2–P0.6 into the app target via AppFeature's Dependencies, run the app, and fix any composition/build issues. Confirm the 5-tab shell renders with the design system theme and a deep link routes correctly."

### Phase 0B — Cross-cutting foundations (build alongside Phase 0; many are parallel)

> These are app-wide capabilities every feature relies on. Build them early so feature prompts can
> assume they exist. P0.7–P0.17 can run in parallel once P0.1 lands.

#### P0.7 — App identity assets (icon, launch, brand) `[PARALLEL: after P0.1]` · target: app
```
Set up the app's visual identity assets. Create the App Icon set (all required iOS sizes + the
single 1024 marketing icon; support tinted/dark/clear icon variants for iOS 18). Build a launch
screen (storyboard or SwiftUI launch — a clean wordmark on the brand background, NO spinner). Add a
brand asset catalog (logo, wordmark, accent gradient) wired to DesignSystem. Add an alternate-app-icons
mechanism (so cosmetic rewards from P5.4 can change the icon). Provide placeholder art if final art
isn't ready, clearly marked TODO.
Definition of Done: app shows the icon on the home screen (light/dark/tinted), launch screen renders
with no flash-of-unstyled-content, and an alternate icon can be set programmatically.
```

#### P0.8 — Localization & formatting infrastructure `[PARALLEL: after P0.1]` · all packages
```
Make the app localization-ready from day one even though launch is English:
- Adopt String Catalogs (.xcstrings) in every package; route ALL user-facing strings through
  LocalizedStringKey / String(localized:). No hardcoded display strings in views.
- Centralize formatting: a Formatters helper for dates (relative + absolute), durations
  (reading time), numbers, percentages, and CURRENCY (use the StoreKit-provided localized price,
  never hand-format money). Use the user's locale + calendar + time zone.
- Make layouts RTL-safe (leading/trailing, no left/right; mirror chevrons). Add a pseudo-locale
  scheme for testing.
Definition of Done: builds; switching the scheme to a pseudo-locale shows every string is localized
(no missing keys) and layouts mirror correctly in RTL; dates/durations/prices format per locale.
```

#### P0.9 — Adaptive & iPad/multiplatform layout foundations `[PARALLEL: after P0.2]` · package: DesignSystem/AppFeature
```
Establish responsive layout so the app is first-class on iPhone AND iPad (and Mac Catalyst-ready):
- Use size classes + a layout helper to switch between compact (iPhone) and regular (iPad) layouts.
  The root uses NavigationSplitView on regular width (sidebar + content + detail) and the TabView on
  compact. The Library/Reader/Reviews adapt (e.g. multi-column grids, a persistent reader sidebar/ToC
  on iPad).
- Support multitasking, Stage Manager, orientation, and Dynamic Type-driven reflow. Define max content
  widths so reading measure stays ideal on large screens.
- Add a ViewThatFits / adaptive-stack toolkit to DesignSystem.
Definition of Done: builds; the app looks intentional on iPhone, iPad portrait/landscape, and split
view — no stretched single-column iPhone UI on iPad; the reader keeps an ideal measure on large screens.
```

#### P0.10 — RemoteImage & image caching `[PARALLEL: after P0.2]` · package: DesignSystem/CoreKit
```
Build a RemoteImage component + an image cache (covers are mostly emoji+color, but support optional
remote art for book covers, avatars, share assets, notification images):
- An async image loader on URLSession with a two-tier cache (NSCache in-memory + URLCache/disk),
  cancellation on disappearance, downsampling to the target size, placeholder + failure states, and
  a prefetch API for scroll performance.
- A CoverView that renders the emoji+color gradient cover (the default) OR remote art when present,
  with consistent rounded styling and an accessibility label.
Definition of Done: builds; covers render fast and crisp; remote images load with placeholder→image
transition, cache across launches, downsample correctly, and don't leak memory while scrolling a long list.
```

#### P0.11 — App lifecycle, scene phase & state restoration `[PARALLEL: after P0.6]` · package: AppFeature
```
Handle the full app lifecycle robustly:
- React to ScenePhase (active/inactive/background): pause reading-session timers + audio ducking
  appropriately, flush analytics, kick a sync, and refresh entitlement/session on return to active.
- State restoration: persist and restore navigation (selected tab + each tab's path) and the
  in-progress reader position/scroll across cold launches via SceneStorage/AppStorage, so the user
  returns exactly where they were.
- Cold-start deep links: ensure a link/notification that launches the app from terminated routes
  correctly after the session resolves (queue the route until auth is ready).
Definition of Done: builds; backgrounding pauses timers/audio correctly; relaunching restores the tab,
nav stack, and reader position; a deep link that cold-launches the app lands on the right screen post-auth.
```

#### P0.12 — Background task framework `[PARALLEL: after P0.4]` · package: CoreKit/Persistence
```
Set up BGTaskScheduler infrastructure used by sync, downloads, and token refresh:
- Register BGAppRefresh + BGProcessing task identifiers; a scheduler that (re)submits tasks, and a
  dispatcher that runs registered jobs with expiration handling. Jobs: outbox sync (Phase 3), token
  pre-refresh (P1.4), content prefetch for downloaded books, and review-schedule recompute.
- Respect Low Power Mode and the user's background-refresh setting; coalesce work; never exceed budgets.
Definition of Done: builds; background tasks register and run (verify via the Xcode "simulate background
fetch" debug trigger); a queued sync completes in the background; jobs handle expiration without crashing.
```

#### P0.13 — Reusable UI-state system + forms/validation kit `[PARALLEL: after P0.2]` · package: DesignSystem
```
Build the cross-app state + form primitives so every screen is consistent:
- A generic AsyncContentView<Phase> that renders loading (skeleton), empty (illustration + CTA),
  error (message + Retry, mapping AppError to friendly copy), and loaded states from one async source.
  A standard Refreshable wrapper and a paginated list helper.
- A Form/validation kit: ValidatedField (inline validation, error text, success state), a FormModel
  pattern, common validators (email, password strength, non-empty, length, code), keyboard-type +
  submit-label handling, and a keyboard-avoidance modifier.
Definition of Done: builds; a demo screen shows all four async states and a validated form with live
inline errors and disabled-until-valid submit; everything is token-driven and accessible.
```

#### P0.14 — Security & privacy hardening `[PARALLEL: after P0.4]` · package: CoreKit/Persistence
```
Harden the app:
- Keychain items use the App Group + appropriate accessibility (afterFirstUnlockThisDeviceOnly for
  tokens), and are cleared on sign-out. No secrets in the bundle or source (Secrets.xcconfig only).
- Configure App Transport Security (HTTPS only). Add OPTIONAL certificate/public-key pinning for the
  API host behind a build flag (with a documented rotation plan). 
- A lightweight tamper/posture check (debugger-attached + basic jailbreak heuristics) that only soft-
  signals (telemetry), never hard-bricks legitimate users.
- Privacy: ensure no PII in logs; a redaction helper; and an analytics opt-out honored everywhere.
Definition of Done: builds; tokens are stored with correct protection and cleared on sign-out; ATS is
enforced; pinning works when enabled and fails closed on a bad cert in a test; logs contain no PII.
```

#### P0.15 — Multi-environment schemes & developer menu `[PARALLEL: after P0.1]` · target/app
```
Set up environments and a dev toolbox:
- Xcode schemes + xcconfigs for Debug, Staging, Release, each with its own API_BASE_URL, Cognito ids,
  bundle id suffix, and app icon badge, so testers can run against staging/prod cleanly.
- A hidden Developer Menu (debug builds only, shake or a Settings entry) to switch environment, inspect
  the current user/token/entitlement/flags, toggle feature flags, clear caches, force errors, and view
  the request log.
Definition of Done: builds; selecting a scheme targets the right backend; the dev menu (debug only) can
switch environment, dump state, and toggle a flag at runtime; release builds hide it entirely.
```

#### P0.16 — Fixtures & sample-data module `[PARALLEL: after P2.1 models exist]` · target: Fixtures
```
Create a Fixtures module/target holding captured REAL API JSON (hit each endpoint once with a dev token
and save the responses) decoded into domain models, plus hand-made sample data, for use in EVERY
#Preview and unit test. Cover: catalog, book detail, EMH + PBC chapters (with/without v21Extras), quiz
session + graded result, entitlement (FREE/PRO), book state, dashboard, streak, badges, reviews, notebook,
concept graph, notifications. Provide a PreviewDependencies that injects fakes returning these fixtures.
Definition of Done: builds; every feature can import Fixtures for previews/tests; all fixtures decode
without loss; PreviewDependencies powers previews with no network.
```

#### P0.17 — CI pipeline `[PARALLEL: after P0.1]` · repo
```
Set up continuous integration (GitHub Actions on a macOS runner): on every PR, resolve packages, build
the app + all packages, run all unit tests on a simulator, run SwiftLint/swift-format checks, and report
status. Cache SPM. Add a manual lane that builds an unsigned archive to catch release-only breakage.
Require green to merge. Document how to run the same checks locally.
Definition of Done: a PR triggers the workflow; build+test+lint run and gate merges; the archive lane
succeeds; the README documents local equivalents.
```

### Phase 1 — Auth & identity

#### P1.1 — Cognito AuthService `[SEQUENTIAL]` · package: AuthKit · depends: P0.3, P0.4, B1
```
Implement AuthService in AuthKit using AWS Cognito (the backend verifies Cognito id_token JWTs).
Use AWS Amplify Swift (Auth category) configured against my user pool (COGNITO_* from AppConfig);
if Amplify proves heavy, fall back to a thin aws-sdk-swift CognitoIdentityProvider client doing
USER_SRP_AUTH. Provide:
- `signUp(email,password,name)`, `confirmSignUp(email,code)`, `resendCode(email)`,
  `signIn(email,password)`, `signOut()`, `forgotPassword(email)`, `confirmForgotPassword(...)`.
- On successful auth, persist id/access/refresh tokens via Persistence.TokenStore.
- Implement `TokenProviding` (from Networking): `validToken()` returns a non-expired id_token,
  transparently refreshing via the Cognito refresh token when near expiry; `refresh()` forces it.
  Wire this instance into the APIClient so all calls are authenticated.
- An @Observable AuthState (.unknown/.signedOut/.signedIn(UserSummary)) published app-wide, derived
  from token presence + validity. Expose an `authEvents` stream.
- Map Cognito errors to friendly messages (wrong password, unconfirmed user, user exists, code expired).
Definition of Done: builds; against a real test pool I can sign up, confirm, sign in, and the
TokenStore holds tokens; an authenticated GET /auth/session returns loggedIn:true; sign-out clears
tokens; refresh works when the id_token is expired. Unit-test the token-refresh decision logic with a fake clock.
```

#### P1.2 — Sign in with Apple `[PARALLEL with P1.3]` · package: AuthKit
```
Add "Sign in with Apple" to AuthKit, federated into the same Cognito user pool (configure Apple as
a Cognito identity provider; coordinate the App Store Connect Service ID + key — document the steps).
- Use AuthenticationServices (ASAuthorizationAppleIDProvider) for the native button + flow.
- Exchange the Apple identity token with Cognito (Amplify federated sign-in or Hosted-UI token
  exchange) so the resulting session yields the same id_token our API expects.
- Persist tokens via TokenStore; update AuthState identically to email/password sign-in.
- Handle the first-time name/email (Apple only provides them once) and the private-relay email case.
- Provide the Apple-compliant button styles (black/white/outline) in DesignSystem.
Definition of Done: builds; tapping Sign in with Apple on device produces a signed-in session whose
id_token authenticates GET /auth/session; returning users sign in without re-consent; documented setup steps.
```

#### P1.3 — Auth UI flows `[PARALLEL with P1.2]` · package: AuthKit · depends: P1.1, P0.2
```
Build the auth UI in AuthKit using DesignSystem (premium, calm, single-column, large type):
Screens — Welcome (value prop + "Continue with Apple" + "Sign up with email" + "Log in"),
Sign Up (name/email/password with inline validation + strength), Verify Email (6-digit code with
auto-advance + resend timer), Log In (email/password + "forgot password"), Forgot Password (request +
reset-with-code). Each screen: loading/disabled states, friendly error toasts mapped from AuthService
errors, keyboard handling, and full Dynamic Type/VoiceOver. Drive everything through an @Observable
AuthFlowModel that calls AuthService and reports AuthState. Add #Previews for each screen and each
state (idle/loading/error).
Definition of Done: builds; the entire sign-up→verify→signed-in and log-in→signed-in flows work end
to end against the real pool; previews cover all states; VoiceOver reads every field/label.
```

#### P1.4 — Session lifecycle & error handling `[SEQUENTIAL]` · package: AuthKit/CoreKit · depends: P1.1
```
Implement robust session lifecycle handling app-wide:
- A SessionManager that observes AuthState and the APIClient error stream. On .unauthenticated from
  any call (after the one auto-refresh in Networking failed), transition to signedOut and present the
  AuthFlow. On .reauthRequired, present a lightweight "confirm it's you" re-auth sheet (re-enter
  password or Face ID via LocalAuthentication), then RETRY the original request transparently. On
  .verifierUnavailable, show a non-destructive "reconnecting" state and keep the user signed in.
- Face ID / Touch ID app-lock option (optional, in prefs) gating app open.
- Token refresh scheduling in the background (BGTaskScheduler) so a returning user is already fresh.
- Clean sign-out: clear Keychain, SwiftData user-scoped data, and caches.
Definition of Done: builds; simulate each error (expired token, 401, 503, reauth_required) and verify
the correct UX with no accidental logout on transient errors; the original request resumes after step-up reauth.
```

#### P1.5 — Identity bootstrap & launch gating `[SEQUENTIAL]` · package: AppFeature · depends: P1.1, P0.6
```
Wire identity into app launch:
- AppRootModel resolves session on cold start: read tokens → validate → GET /auth/session and GET /me
  to hydrate a UserProfile (sub, email, displayName per the server's identity resolution: profile >
  cognito name > email-derived > "Reader"). Show Splash until resolved; then route to AuthFlow or MainTab.
- Persist a minimal UserProfile for instant launch (optimistic) then refresh.
- Expose currentUser through Dependencies for all features.
- Handle account-status: if the API returns account deactivated/deleted signals, route to the proper screen.
Definition of Done: builds; cold launch signed-in goes straight to the shell with the user's name shown;
signed-out goes to Welcome; killing the app and relaunching preserves the session; deactivated-account path handled.
```

#### P1.6 — Credential management (change email/password) `[SEQUENTIAL: after P1.4]` · package: AuthKit/SettingsFeature
```
Add signed-in credential management via Cognito: change password (re-enter current + new, strength
meter), change email (request → verify the new address with a code → confirm), and "sign out of all
devices" (Cognito global sign-out). Each sensitive action goes through the step-up reauth from P1.4.
Surface friendly errors (wrong current password, email already in use, code expired). These live in
Settings (P10.2) but the AuthKit service methods are built here.
Definition of Done: builds; I can change my password and email (with verification) while signed in,
sign out all devices, and each requires recent auth; errors are clear.
```

#### P1.7 — Auth resilience & abuse handling `[SEQUENTIAL: after P1.3]` · package: AuthKit
```
Handle the unhappy auth paths so users never get stuck: rate-limit / too-many-attempts lockout UX with
a cooldown, unconfirmed-account resend path, "account exists — log in instead" redirect, network-failure
retry, and a clear path when Cognito returns PasswordResetRequired or a forced new-password challenge.
Add inline guidance and a support/contact escape hatch. Cover the Sign in with Apple revoked-credential
case (re-prompt). 
Definition of Done: builds; each failure path shows correct, non-dead-end UX; lockout shows a countdown;
unconfirmed users can resend + confirm; revoked Apple credentials re-prompt cleanly.
```

> **Integration checkpoint INT-1:** "Run the full app: fresh install → Welcome → Sign in with Apple → land on Home with my display name. Force-expire the token and confirm transparent refresh. Sign out and confirm return to Welcome. Fix any issues."

### Phase 2 — Core reading loop

#### P2.1 — Domain models & content resolver `[SEQUENTIAL — gates all of Phase 2]` · package: Models · depends: P0.3
```
Build the Models package: Codable domain models matching the API exactly (see docs/PLAN.md Appendix A
and Section 3.4). Implement as Sendable value types:
- Catalog: BookCatalogItem (bookId,title,author,categories,tags,cover{emoji,color},variantFamily,
  status,latestVersion,updatedAt). BookManifest + BookManifestChapter.
- Content: Chapter (chapterId,number,title,readingTimeMinutes,activeVariant,availableVariants,
  contentVariants:[VariantKey:ChapterVariantContent],examples,implementationPlan,reviewCards,
  keyTakeawayCard,v21Extras). VariantKey enum (easy/medium/hard/precise/balanced/challenging).
  ChapterVariantContent with the tone-keyed fields. ToneKeyed{gentle,direct,competitive}. v21Extras
  (hook,counterintuition,tryThisNow,keyTakeaway,memorableLines,experiencePlan). Example, ImplementationPlan.
- Progress/state: BookProgress (currentChapterNumber,unlockedThroughChapterNumber,completedChapters,
  bestScoreByChapter,preferredVariant,progressRev). BookUserBookState (currentChapterId,
  completedChapterIds,unlockedChapterIds,chapterScores,chapterCompletedAt,lastReadChapterId) +
  applicationStates:[String:ChapterApplicationState].
- Quiz: QuizClientSession, QuizQuestion (questionId,stem/prompt,choices with the server choiceId
  scheme), QuizAttemptResult (passed,scorePercent,questionResults[{questionId,correctChoiceId,isCorrect}],
  cooldownSeconds,nextEligibleAttemptAt,unlockedNextChapter).
- Entitlement: Entitlement (plan FREE/PRO, proStatus, proSource, freeBookSlots, unlockedBookIds,
  remainingFreeStarts, currentPeriodEnd, cancelAtPeriodEnd), Paywall (price, pricingTiers, benefits).
- KEY LOGIC — ChapterContentResolver: given (chapter, selectedVariant, selectedTone), returns a flat,
  display-ready ResolvedChapter (all tone-keyed fields collapsed to the chosen tone, variant chosen
  with sensible fallback to availableVariants/first). This is the single place tone/variant is resolved.
- EntitlementEvaluator: pure functions isPro(entitlement), canStart(bookId, entitlement),
  isChapterUnlocked(number, progress).
Write thorough decoding tests against REAL sample JSON fixtures (include a Fixtures resource with
captured responses for getBook, getChapter (EMH + PBC, with and without v21Extras), getQuiz,
getEntitlements, getState). Handle the union/optional shapes gracefully (scenario/whatToDo can be
string OR ToneKeyed; explanation string OR ToneKeyed).
Definition of Done: package builds; every fixture decodes without loss; ChapterContentResolver returns
correct strings for each tone/variant combo; EntitlementEvaluator unit tests pass; no force-unwraps.
```

#### P2.2 — Library & Home `[PARALLEL: after P2.1]` · package: LibraryFeature
```
Build Home + Library in LibraryFeature using DesignSystem.
- LibraryRepository: getCatalog() (GET /book/books, cache to SwiftData), getMyProgressOverview
  (GET /book/me/progress), getSaved/toggleSaved (GET|POST /book/me/saved).
- HomeView: a premium home with "Continue reading" (the user's in-progress books with a progress ring
  and last-read chapter), "Your library" (owned/started), and "Discover" (catalog grouped by category).
  Book cards render the emoji+color gradient cover, title, author, progress. Pull-to-refresh.
- LibraryView: full catalog with search (client-side over title/author/tags), category filters, and a
  saved/bookmarked filter. Save/unsave with haptic.
- @Observable HomeModel/LibraryModel calling the repository; loading skeletons, empty states, error toasts.
- Tapping a book → BookDetail route (built next). Long-press → context menu (save, start, share).
Add #Previews with fake repositories for loaded/empty/loading/error.
Definition of Done: builds; Home and Library load real catalog data, search/filter work, covers render
beautifully in light/dark, save persists, and continue-reading reflects real progress.
```

#### P2.3 — Book detail `[PARALLEL: after P2.1]` · package: LibraryFeature
```
Build BookDetailView in LibraryFeature.
- BookDetailRepository: getBook(id) (manifest + metadata), getBookState(id) (GET /book/me/books/{id}/state),
  startBook(id) (POST /book/me/books/{id}/start), getEntitlements for gating.
- The screen: hero (cover, title, author, categories), a "Start"/"Continue" primary action, the chapter
  list showing per-chapter lock/complete/score state (from state.unlockedChapterIds /
  completedChapterIds / chapterScores), reading-time, and the two-axis application badge
  (applicationStates: committed/applied). A depth/tone selector entry point. Show "X of Y chapters" and
  overall progress ring.
- GATING: if the book isn't owned and the user has no free slot and isn't Pro, the Start button opens
  the Paywall (PaywallFeature, stub the call for now via a closure injected from AppFeature). Owned/Pro →
  start → navigate to the reader at the current chapter.
- Tapping an unlocked chapter → Reader route at that chapter; locked chapters show why (finish the prior
  quiz / go Pro).
Add #Previews: free-locked, owned-in-progress, completed.
Definition of Done: builds; real book detail renders, chapter lock/complete states are correct, Start
consumes a free slot or routes to paywall, Continue opens the reader at the right chapter.
```

#### P2.4 — The Reader (MASTER SPEC — build via the granular units P2.4a–P2.4e below) `[SEQUENTIAL — the centerpiece]` · package: ReaderFeature · depends: P2.1
```
Build the Reader — the most important screen in the app. It must feel better than any web reader:
premium typography, buttery 120Hz scrolling, instant depth/tone switching, true themes, haptics.
- ReaderRepository: getChapter(bookId,n,mode) (GET .../chapters/{n}), patchBookState (cursor/last-read),
  postReadingSession heartbeats (POST /book/me/reading-sessions). 
- ReaderModel (@Observable): loads the chapter, resolves content via ChapterContentResolver for the
  current (variant, tone), tracks scroll position + % read, and persists reading position locally +
  PATCHes the cursor (forward-only; gating stays server-truth — never claim unlock here).
- RENDERING: lay out the resolved chapter as a clean reading flow: the v21 HOOK banner at top (if present),
  the chapterBreakdown narrative, keyTakeaways, examples (scenario/whatToDo/whyItMatters), the
  "tryThisNow" callout, memorableLines as pull-quotes, implementationPlan (if-then, 24h challenge), and
  the oneMinuteRecap. Use refined typographic hierarchy (DesignSystem serif body, generous leading,
  measure ~66ch). Render any inline emphasis. NEVER show raw tone/variant keys.
- READING CONTROLS (a clean bottom/contextual toolbar): font-size slider, theme (System/Light/Sepia/Dark/
  Paper), reading DEPTH switcher (availableVariants) and TONE switcher (gentle/direct/competitive) that
  re-resolve INSTANTLY without refetch, line-spacing, and a "focus mode" that hides chrome. Persist all to
  AppPreferences.
- A chapter progress indicator (thin top bar) + estimated time left; haptic tick at chapter end.
- A floating "Take the quiz" CTA once the chapter is substantially read; "Ask about this" entry (AIFeature,
  injected closure); audio "Listen" entry (AIFeature audio, injected closure).
- ProMotion-smooth scrolling; respect Reduce Motion; full Dynamic Type and VoiceOver (each section a
  proper accessibility element; reading order correct).
Add #Previews for EMH and PBC chapters, each theme, with and without v21Extras, at XXL Dynamic Type.
Definition of Done: builds; a real chapter renders gorgeously; switching depth and tone is instant and
correct; themes + font size persist; scroll position restores on reopen; reading session heartbeats post;
VoiceOver reads the chapter in order.
```

> **Build the Reader as the five units below (P2.4a–e), in order.** P2.4 above is the master spec they
> collectively satisfy. Keep each unit to one focused session; do not merge them.

#### P2.4a — Reader content rendering engine `[SEQUENTIAL]` · package: ReaderFeature
```
Build the content rendering engine that turns a ResolvedChapter (from ChapterContentResolver) into a
laid-out reading flow. Define a ReaderBlock model (an ordered enum: heading, paragraph, bullet,
keyTakeaway, example{scenario,whatToDo,whyItMatters}, implementationPlanItem, recap, pullQuote, callout)
and a ReaderContentBuilder that maps a resolved chapter into [ReaderBlock] in the correct reading order.
Build ReaderContentView (a LazyVStack/scroll) that renders each block with the DesignSystem reading
typography and spacing. Pure rendering from sample/fixture data — no networking yet. Handle every
optional block gracefully (absent sections simply omitted).
Definition of Done: builds; given fixture chapters (EMH + PBC, with and without v21Extras), the view
renders all present block types in the right order, beautifully, at all Dynamic Type sizes; #Previews cover both.
```

#### P2.4b — Reading typography & themes `[SEQUENTIAL: after P2.4a]` · package: ReaderFeature/DesignSystem
```
Build the reading appearance system: a refined reading type scale (serif body with ideal measure ~60–70ch,
generous leading, tabular where needed), and themes System/Light/Sepia/Dark/Paper (each a full token set:
page bg, text, accent, quote, separator). Add user controls for font size, line spacing, and theme,
persisted to AppPreferences and applied INSTANTLY (no reflow jank). Add a screen-brightness + true-tone-
friendly sepia and an OLED-true-black dark. Respect Dynamic Type as the floor.
Definition of Done: builds; switching theme and font size restyles the reader instantly and persists across
launches; sepia/dark look premium; text stays readable at the largest accessibility size.
```

#### P2.4c — Reader controls & depth/tone switching `[SEQUENTIAL: after P2.4b]` · package: ReaderFeature
```
Build the reader control surface: a clean, auto-hiding toolbar (tap to toggle) with the reading DEPTH
switcher (availableVariants — easy/medium/hard or precise/balanced/challenging) and the TONE switcher
(gentle/direct/competitive). Both re-resolve content INSTANTLY via ChapterContentResolver with NO refetch
and NO scroll jump (preserve reading position by anchor). Add Focus Mode (hide all chrome), a
scroll-vs-paginate reading mode toggle, and quick access to font/theme (P2.4b). Show the depth
"Recommended for you" hint slot (filled by P6.4). Persist selections per book.
Definition of Done: builds; changing depth or tone updates the visible text immediately while keeping the
reader's place; focus mode and the reading-mode toggle work; selections persist per book.
```

#### P2.4d — Reading progress, position & session hook `[SEQUENTIAL: after P2.4c]` · package: ReaderFeature
```
Wire the reader to live data + tracking:
- Load the chapter (ReaderRepository.getChapter), resolve content, and drive ReaderContentView.
- A thin top progress bar + "% read / time left"; save and RESTORE exact reading position on reopen
  (anchor-based, surviving font/theme changes).
- PATCH the cursor forward-only (never claim unlock) and post reading-session heartbeats every ~30s of
  active reading (full session logic in P2.7).
- A chapter-end state (haptic tick) and a "Take the quiz" CTA that appears once the chapter is
  substantially read. Entry points (injected closures) for "Listen" (audio, P6.2) and "Ask about this" (P6.1).
Definition of Done: builds; a real chapter loads and renders; position restores precisely on reopen even
after changing font/theme; the cursor PATCHes forward-only; heartbeats post; the quiz CTA appears at the right time.
```

#### P2.4e — v21 premium reader chrome `[SEQUENTIAL: after P2.4d]` · package: ReaderFeature
```
Render the v21Extras premium layer that makes the reader special (when present): the HOOK banner at the
top, the COUNTERINTUITION callout, the "TRY THIS NOW" directive block, MEMORABLE LINES as elegant
pull-quotes, the keyTakeaway card, and the experiencePlan — failureRecovery (normalizing line + cue +
options + repair), transferPrompt (apply it elsewhere), and the behaviorLoop "which pattern fits you?"
personalization (readerPatterns → tappable, mapping to a plan/example). Each is all-or-nothing per the
contract (render only complete sub-objects). Beautiful, restrained styling; full accessibility.
Definition of Done: builds; a chapter with v21Extras shows the hook, counterintuition, try-this-now,
pull-quotes, takeaway card, and experience plan correctly; a chapter without them degrades cleanly; previews cover both.
```

#### P2.5 — Highlights, notes & bookmarks `[SEQUENTIAL: after P2.4]` · package: ReaderFeature
```
Add native annotation to the Reader:
- Long-press/drag text selection → a menu to Highlight (color choices), Add note, Copy, Share, and
  "Ask about this" (passes the selection to AIFeature). Highlights render as a tint behind the text and
  persist locally (SwiftData) and to the notebook API (POST /book/me/notebook with type "note"/"bookmark";
  per-chapter UI state via PATCH /book/me/books/{id}/chapters/{n}/state). 
- A bookmark toggle for the chapter. A per-chapter notes affordance and a "my highlights" list for the book.
- Notes/highlights must work OFFLINE (write locally, queue for sync — coordinate with Phase 3 outbox; for
  now write-through with graceful failure).
- Respect that selection/highlight positions must survive font-size/theme changes (anchor on text ranges
  in the resolved content, not pixel offsets).
Definition of Done: builds; I can select text, highlight in a color, add a note, see it persist across
reopen and theme/font changes, and find it in the book's highlights list; offline writes don't crash.
```

#### P2.6 — Quiz `[PARALLEL: after P2.1]` · package: QuizFeature
```
Build the Quiz experience in QuizFeature. The SERVER is the grading authority — never grade locally.
- QuizRepository: getQuiz(bookId,n,tone) (GET .../quiz → client session), submit(answers) (POST
  /book/me/quiz/{bookId}/{n}/submit), check(answer) (POST .../check), postEvents.
- QuizModel (@Observable): present one question at a time (or a scrollable set) using the server's
  choiceId scheme; track selected choiceIds; on submit, send and render the graded QuizAttemptResult:
  per-question correct/incorrect with the correct choice revealed, score %, pass/fail vs passing score.
- PASS → celebratory feedback (haptic.success, confetti from DesignSystem), show "next chapter unlocked"
  if unlockedNextChapter, and offer Continue. FAIL → show score, explanation, and the retry rule
  (cooldownSeconds / nextEligibleAttemptAt) with a live countdown; disable retry until eligible.
- Handle the retryQuestions variant if present. Accessibility: each option a clear, large tap target with
  state announced.
Add #Previews: fresh quiz, passed result, failed-with-cooldown.
Definition of Done: builds; a real quiz loads, submits, and shows correct server-graded results; pass
unlocks/advances; fail shows the cooldown countdown and blocks early retry; no client-side grading.
```

#### P2.7 — Reading sessions & loop completion `[SEQUENTIAL: after P2.4, P2.6]` · package: ReaderFeature/EngagementFeature
```
Tie the loop together:
- Reading-session tracking: start a session when the reader opens, heartbeat every ~30s of active
  reading, end on background/close (POST /book/me/reading-sessions). Pause on inactivity. Drive the
  app's "active reading time" used by streak/dashboard.
- Two-axis completion display: a chapter is "knowledge complete" on quiz pass (server truth) and
  separately shows the APPLICATION axis (none/committed/applied) from applicationStates — surface both
  in the reader/detail without treating application as a gate.
- On loop completion (chapter read + quiz passed), show a tasteful completion moment and refresh
  streak/flow-points/tier from their endpoints (these update server-side via the quiz-pass pipeline).
- Wire "Continue" to advance to the next unlocked chapter.
Definition of Done: builds; reading time accrues and posts; completing a chapter's quiz shows the
completion moment and the next chapter unlocks; application badge reflects commitments.
```

#### P2.8 — Global search `[PARALLEL: after P2.1]` · package: LibraryFeature
```
Build global search powered by GET /book/search-index (+ client filtering). A search experience reachable
from Home/Library: search across book titles, authors, categories/tags, and chapter titles, with grouped
results (Books / Chapters), recent searches, suggested/trending, and instant-as-you-type filtering with
debounce. Tapping a result opens the book or jumps to the chapter. Empty + no-results states. Works on
cached catalog offline.
Definition of Done: builds; typing returns grouped, relevant results quickly; recent searches persist;
tapping navigates correctly; offline search works over cached data.
```

#### P2.9 — Discovery & browse `[PARALLEL: after P2.2]` · package: LibraryFeature
```
Build a Discover/Browse surface: the catalog organized by category, curated shelves (new, popular,
journeys, by goal/topic), and a category-detail list. Premium horizontal shelves with covers, a "for you"
row seeded by the user's categories/onboarding interests, and entry points to Journeys (P5.6) and Events
(P5.7). Pull-to-refresh; skeletons; offline from cache.
Definition of Done: builds; Discover renders curated shelves + category browsing from the real catalog,
"for you" reflects interests, and everything routes into book detail.
```

#### P2.10 — Per-book reading preferences `[PARALLEL: after P2.4c]` · package: LibraryFeature/ReaderFeature
```
Build a per-book preferences surface (from Book Detail and the reader): set the default reading DEPTH
(variant) and TONE for this book, the preferred learning mode, and audio/narration default, persisting to
the book's progress (preferredVariant) + AppPreferences and to the server settings. Show the adaptive
"recommended depth" (P6.4) here too. A global default lives in Settings (P10.2); per-book overrides it.
Definition of Done: builds; setting per-book depth/tone is honored by the reader and persists; the global
default applies when no override; recommended depth is surfaced.
```

#### P2.11 — Chapter navigator & table of contents `[PARALLEL: after P2.4d]` · package: ReaderFeature
```
Build in-reader navigation: a Table of Contents sheet/sidebar listing all chapters with lock/complete/
current state and quick jump to any unlocked chapter; a chapter scrubber/progress slider to move within the
current chapter; previous/next-chapter controls respecting unlock gating; and (iPad) a persistent ToC
sidebar. Show per-chapter reading time and completion.
Definition of Done: builds; the ToC lists chapters with correct states and jumps to unlocked ones; the
scrubber moves within a chapter; next/prev respect gating; iPad shows a persistent ToC.
```

> **Integration checkpoint INT-2:** "End-to-end: open a book → read a chapter (switch depth+tone, change theme, highlight text) → take the quiz → pass → next chapter unlocks → continue. Run on device, confirm 120Hz smoothness and that all state persists. Fix issues."

### Phase 3 — Offline & sync (the "better than web" pillar)

#### P3.1 — Offline schema `[SEQUENTIAL]` · package: Persistence/Models · depends: P2.*
```
Define the SwiftData @Model schema for offline use (registered into the Persistence container):
CachedBook, CachedChapter (full content blob incl. all variants), CachedManifest, CachedProgress,
CachedBookState, CachedQuizState, CachedNotebookEntry, CachedHighlight, CachedReviewCard, and an
OUTBOX model: PendingMutation { id, kind (enum: progressCursor, quizSubmit, notebookWrite,
highlightWrite, reviewGrade, commitment, savedToggle, readingSession), payload (Codable JSON),
createdAt, attemptCount, lastError, status }. Add indexes on userId/bookId/dueAt. Provide mapping
between domain models (Models) and @Model rows. Add a per-user data partition + a wipe-on-signout routine.
Definition of Done: builds; container migrates cleanly; round-trip tests map every domain model ↔ row;
sign-out wipes user-scoped rows.
```

#### P3.2 — Download manager `[SEQUENTIAL: after P3.1]` · package: Persistence/LibraryFeature
```
Build a DownloadManager actor:
- downloadBook(bookId): fetch the manifest + every chapter's full content (all variants) + quiz +
  review cards + (optionally) audio, store in SwiftData/FileStore, report progress via an AsyncStream.
- Manage storage: per-book size accounting, a Settings "Downloads" screen to see/remove downloads, an
  eviction policy + total-cache cap, and a "download over Wi-Fi only" pref.
- Mark books as available offline in Library/BookDetail with a download button + progress ring + checkmark.
- Resume interrupted downloads; background URLSession for large audio.
Definition of Done: builds; I can download a book, watch progress, then enable Airplane Mode and still
open it; downloads list shows sizes and lets me delete; storage cap enforced.
```

#### P3.3 — Offline-first repositories `[SEQUENTIAL: after P3.2]` · all feature packages
```
Make the core repositories OFFLINE-FIRST via read-through caching:
- LibraryRepository, ReaderRepository, QuizRepository (and notebook/reviews) first read from SwiftData,
  then refresh from network when online, updating the cache. When offline, serve cached data and surface
  a subtle "offline" indicator; when content isn't cached, show a clear "download to read offline" state.
- Centralize the online/offline decision behind a Reachability service; never block the UI on the network.
- Ensure the Reader, Quiz, Notebook, and Reviews all function fully from cache for a downloaded book.
Definition of Done: builds; with Airplane Mode on, a downloaded book is fully readable+quizzable+
note-takeable+reviewable; uncached content shows the right empty/CTA state; reconnecting refreshes silently.
```

#### P3.4 — Sync engine `[SEQUENTIAL: after P3.3]` · package: Persistence/CoreKit
```
Build the SyncEngine actor implementing the outbox pattern:
- All user mutations (progress cursor, quiz submit, notebook/highlight writes, review grades, commitments,
  saved toggles, reading sessions) write LOCALLY first (optimistic UI) and enqueue a PendingMutation.
- On reconnect / app foreground / BGAppRefresh, drain the outbox in order with retry + exponential backoff;
  remove on success; surface terminal failures.
- CONFLICTS: server is authority for GATING fields (unlockedThroughChapterNumber, completedChapters,
  bestScoreByChapter — written only by the quiz-pass path). The client must NEVER push unlocks; it pushes
  cursor/notes/grades/sessions and PULLS gating truth. Resolve overlapping writes by updatedAt /
  progressRev; reconcile quiz submissions idempotently (a quiz submitted offline replays; if the server
  already advanced, accept server truth).
- Expose sync status (idle/syncing/error + pending count) for a subtle UI indicator.
Definition of Done: builds; take a quiz + add notes offline, then reconnect → everything syncs, gating
matches the server, no duplicate submissions, and the pending-count returns to zero. Unit-test the
conflict/idempotency logic with fakes.
```

#### P3.5 — Reachability & offline UX polish `[SEQUENTIAL: after P3.4]` · package: CoreKit/DesignSystem
```
Add the cross-cutting offline experience:
- A Reachability service (NWPathMonitor) in an @Observable; a global, tasteful offline banner; per-action
  "queued — will sync" affordances; and a sync indicator in Settings.
- Make every primary flow degrade gracefully: disabled-with-explanation for online-only actions (e.g.
  buying Pro, AI ask without on-device fallback), queued-with-confirmation for writable actions.
Definition of Done: builds; toggling connectivity shows/hides the banner correctly; online-only actions
explain themselves offline; writable actions confirm they're queued; reconnect clears everything.
```

#### P3.6 — Background sync & prefetch `[SEQUENTIAL: after P3.4, uses P0.12]` · package: Persistence/CoreKit
```
Wire the SyncEngine + DownloadManager into the BGTaskScheduler framework (P0.12): drain the outbox and
refresh due reviews/entitlement on BGAppRefresh; prefetch the next chapter of in-progress books and
opportunistically complete interrupted downloads on BGProcessing (Wi-Fi/charging aware). Also sync on app
foreground and on network-regained. Coalesce, respect Low Power Mode + the background-refresh setting, and
surface a "last synced" time in Settings.
Definition of Done: builds; a queued mutation syncs in the background (verify via the debug background
trigger); the next chapter prefetches; downloads resume; "last synced" updates; no work runs when disabled.
```

#### P3.7 — SwiftData schema versioning & migration `[SEQUENTIAL: after P3.1]` · package: Persistence
```
Establish a durable migration strategy for the offline store so app updates never lose user data or crash:
define a VersionedSchema + SchemaMigrationPlan with explicit migration stages, a current-version constant,
and lightweight + custom migration paths. Add a corruption-recovery fallback (rebuild cache from server if
the store can't open) that never loses server-backed data, only the rebuildable cache. Test a v1→v2
migration with seeded data.
Definition of Done: builds; a simulated schema change migrates existing data without loss; an unopenable
store recovers by rebuilding the cache; the migration is unit-tested.
```

> **Integration checkpoint INT-3:** "Full offline test on device: download a book, go offline, read+highlight+quiz+review it, come back online, confirm clean sync with server-authoritative gating and zero duplicates."

### Phase 4 — Monetization (Track C) · depends: P1, P2.1, B3

#### P4.1 — StoreKit 2 service `[PARALLEL: Track C]` · package: PaywallFeature
```
Build a StoreKitService (actor) using StoreKit 2 (async). Apple requires in-app subscriptions to use IAP.
- Define product ids (configure in App Store Connect: a monthly and an annual auto-renewable subscription
  in one subscription group, plus an optional annual-upfront). Read ids from B4 config or AppConfig.
- Load Products, expose displayPrice/period; purchase(product) handling the Transaction result
  (verified/unverified — reject unverified); listen to Transaction.updates for renewals/refunds in the
  background; restorePurchases(); compute current subscription status from Transaction.currentEntitlements.
- On a successful/updated verified transaction, POST the signed transaction JWS to the backend
  (POST /book/me/billing/apple/verify from B3) so the server grants the PRO entitlement; then refresh
  the app Entitlement.
- Handle Ask-to-Buy/pending, grace period, and billing-retry states gracefully.
Definition of Done: builds; in the StoreKit sandbox I can purchase monthly, see PRO reflected after the
backend grants it, restore on a fresh install, and a sandbox renewal/refund updates status via the
transaction listener.
```

#### P4.2 — Entitlement service & gating model `[PARALLEL: Track C, after P4.1]` · package: PaywallFeature/Models
```
Build EntitlementService (@Observable) as the single source of truth for access:
- Merge two inputs: the backend entitlement (GET /book/me/entitlements → plan/proStatus/proSource/
  freeBookSlots/unlockedBookIds/remainingFreeStarts/currentPeriodEnd/cancelAtPeriodEnd) and local
  StoreKit status. Backend is authority once it has processed the Apple transaction; StoreKit gives
  instant local optimism.
- Expose: isPro, canStartNewBook (Pro OR remainingFreeStarts > 0), isBookUnlocked(bookId), and a
  reason for any lock (needsPro / needsFreeSlotOrPro / locked-behind-quiz).
- Cache entitlement locally for offline reads; refresh on foreground and after purchases.
Definition of Done: builds; gating predicates are correct for FREE (with/without free slots) and PRO
users; after purchase, isPro flips immediately and persists; offline reads use the cached entitlement.
```

#### P4.3 — Paywall UI `[PARALLEL: Track C, after P4.2]` · package: PaywallFeature
```
Build a premium Paywall (Apple-Pro restraint; clear value, honest, no dark patterns):
- Pull display copy from GET /book/me/entitlements (paywall.price, paywall.pricingTiers monthly/annual/
  annual_upfront, paywall.benefits). Render plan options with per-period pricing and savings, the benefit
  list, a prominent purchase button (StoreKitService.purchase), a "Restore purchases" link, and links to
  Terms/Privacy + auto-renew disclosure (App Review requires these).
- States: loading products, purchasing (spinner + disabled), success (celebration → dismiss), error,
  already-Pro (manage subscription → open the App Store subscriptions URL).
- Presentation contexts: from BookDetail (out of free slots), from a locked feature, and from Settings.
- Track paywall_viewed / purchase analytics.
Add #Previews for each state and each entry context.
Definition of Done: builds; the paywall shows real tiers/prices, completes a sandbox purchase end to end,
restores, handles errors, shows manage-subscription for existing Pro, and meets App Review's IAP UI rules.
```

#### P4.4 — Gating integration `[PARALLEL: Track C, after P4.3]` · all feature packages
```
Wire EntitlementService gating throughout the app:
- BookDetail Start button: Pro/free-slot → start; else present Paywall. Show "X free starts left."
- Locked chapters/books show the correct reason and CTA. Pro-only advanced features (advanced learning
  modes, unlimited AI ask, etc.) gate to the paywall at natural upgrade moments (not nagging).
- A non-intrusive "Go Pro" entry in Settings/Profile showing current plan + renewal/cancel date
  (currentPeriodEnd, cancelAtPeriodEnd) and manage-subscription.
Definition of Done: builds; a FREE user hits the paywall exactly at the right moments and never for owned
content; a PRO user never sees a paywall; plan/renewal info is accurate.
```

#### P4.5 — Intro offers, free trials & promo codes `[PARALLEL: Track C, after P4.1]` · package: PaywallFeature
```
Add the full StoreKit offer surface: introductory offers / free trials (configured in App Store Connect)
shown correctly on the paywall with accurate eligibility + terms; promotional offers / win-back offers for
lapsed subscribers; and Offer Codes / promo-code redemption (presentCodeRedemptionSheet + Settings entry).
Display all pricing from StoreKit (localized), never hand-rolled. Make trial terms and auto-renew disclosure
explicit (App Review requirement).
Definition of Done: builds; an eligible user sees the trial/intro offer with correct terms; an offer code
redeems and grants Pro; win-back offers appear for lapsed users; pricing is always StoreKit-localized.
```

#### P4.6 — Subscription management & status `[PARALLEL: Track C, after P4.2]` · package: PaywallFeature/SettingsFeature
```
Build a Subscription management screen: current plan, source (Apple/Stripe/license/gift), renewal date
(currentPeriodEnd), auto-renew state (cancelAtPeriodEnd), and the right CTAs — "Manage subscription" (open
the App Store manage URL for Apple subs), and clear guidance for non-Apple sources (e.g. manage Stripe on
web). Handle billing-retry / grace-period / expired / refunded states with honest messaging and a path to
resubscribe. Surface entitlement from gift/license with expiry.
Definition of Done: builds; the screen accurately reflects every entitlement state and source; manage opens
the correct destination; grace/expired/refunded states show correct messaging and recovery paths.
```

#### P4.7 — Cross-platform entitlement reconciliation `[PARALLEL: Track C, after P4.2]` · package: PaywallFeature
```
Make entitlement coherent across web (Stripe) and iOS (Apple): a user who bought Pro on the web must be
recognized as Pro in the app (read from /book/me/entitlements), and a user who buys on iOS gets Pro on web
(backend B3 writes the shared entitlement). On launch + foreground + after any purchase/restore, reconcile
StoreKit currentEntitlements with the backend entitlement, preferring the most recent active source, and
never double-charge: if the user is already Pro via Stripe, the paywall shows "you're already Pro
(via web)" instead of selling again.
Definition of Done: builds; a Stripe-Pro user opens the app and is Pro without an iOS purchase; an
Apple-Pro user is Pro on web; the paywall never sells to an already-Pro user; reconciliation is correct after restore.
```

### Phase 5 — Engagement & gamification (Track D — highly parallel) · depends: P1, P2.1

> Track D is the most parallelizable pod: P5.1–P5.10 are largely independent. Run several Claude sessions
> at once (each its own branch). Shared: a small `EngagementRepository` set; build P5.1 first as it
> establishes the dashboard data layer others reuse.

#### P5.1 — Progress dashboard `[Track D, build first in pod]` · package: EngagementFeature
```
Build the Home/Profile dashboard from GET /book/me/dashboard, GET /book/me/progress, GET /book/me/streak.
Use Swift Charts for: reading-time trend, chapters completed over time, quiz-score trend, and a
category-coverage view. Show current streak, total books/chapters, tier, and flow-points balance as
glanceable stat cards (DesignSystem). Parallel-fetch with async let; skeletons; pull-to-refresh; offline
from cache. This screen defines the shared EngagementRepository (dashboard, streak, points, tier reads).
Definition of Done: builds; dashboard renders real aggregates with smooth charts in light/dark, refreshes,
and reads from cache offline.
```

#### P5.2 — Streak system `[Track D]` · package: EngagementFeature
```
Build the Streak feature from GET /book/me/streak (currentStreak, longestStreak, streakShieldsHeld,
consistencyLast30, milestonesReached). A streak view with a calendar heatmap (last 30 days), shield
count, and milestone progress. A tasteful streak-increment celebration (haptic + animation) when a day's
first activity lands. A "streak at risk" state late in the day (drives a local notification in Phase 9).
Shields: explain and show usage. Respect Reduce Motion.
Definition of Done: builds; streak data renders accurately; celebration fires once per day on first
activity; at-risk state appears correctly; heatmap matches server data.
```

#### P5.3 — Badges & achievements `[Track D]` · package: EngagementFeature
```
Build Badges from GET /book/me/badges (+ achievement tracks: mastery/consistency/exploration/hidden).
A grid of earned + locked badges with progress toward locked ones, a badge-detail sheet (how to earn,
earned date), and an earned-badge celebration moment. Hidden achievements stay mysterious until earned.
Definition of Done: builds; earned/locked badges render with progress; detail sheet is correct; a newly
earned badge animates in.
```

#### P5.4 — Flow points, shop & inventory `[Track D]` · package: EngagementFeature
```
Build the Flow-Points economy UI from GET /book/me/flow-points (balance, ledger), GET /book/me/shop, and
POST /book/me/flow-points/redeem. Show balance + a transaction ledger; a Shop of rewards
(bonus_book_unlock, pro_pass_7d/30d) and cosmetic inventory (themes/frames/seasonal) with buy/equip;
redeem flows with confirmation; equip cosmetics (which feed Profile/Reader theming). Handle insufficient
balance gracefully.
Definition of Done: builds; balance + ledger are accurate; I can redeem a reward and equip a cosmetic;
redemptions reflect immediately and survive refresh.
```

#### P5.5 — Tier system `[Track D]` · package: EngagementFeature
```
Build the Tier display (reader→analyst→synthesizer→polymath→luminary) from the tier data (in dashboard /
POST /book/me/tier). Show current tier, progress to next (loops completed, avg quiz score, categories
explored), and a tier-up celebration. A tier explainer sheet.
Definition of Done: builds; current tier + progress render; tier-up moment fires on advancement.
```

#### P5.6 — Journeys `[Track D]` · package: EngagementFeature
```
Build Journeys (curated multi-book paths) from GET /book/books/journeys, GET /book/me/journeys/{id},
POST /book/me/journeys/{id}/start. List available journeys (title, description, weeks, book sequence,
badge, bonus IP, gradient cover); a journey-detail with the ordered books + reasons + my progress
(currentBookIndex/completedBookIds); start/continue routing into the right book. Completion celebration.
Definition of Done: builds; journeys list + detail render, start works, progress reflects completed books,
and tapping a journey book opens it.
```

#### P5.7 — Seasonal events `[Track D]` · package: EngagementFeature
```
Build Events from GET /book/events/active, POST /book/me/events/{id}/join, GET|POST /book/me/events/{id}/
progress. Show the active event (title, dates, target chapters, daily target, badge, bonus IP), a join
CTA, and daily/total progress with a countdown. Completion + badge award moment.
Definition of Done: builds; active event renders with live countdown; join works; progress updates as
chapters complete; completion awards the badge.
```

#### P5.8 — Saved & Notebook `[Track D]` · package: EngagementFeature/ReaderFeature
```
Build the Notebook + Saved hub from GET /book/me/notebook (entries: note/reflection/bookmark/commitment,
with book/chapter context + tags) and GET /book/me/saved. A unified, searchable, tag-filterable list of
all the user's notes/highlights/bookmarks across books; tap-through to the source chapter; edit/delete;
tag management. Saved-books shelf. Works offline (reads cache; edits queue via the outbox).
Definition of Done: builds; notebook aggregates all entries with search + tag filter; tapping opens the
exact chapter; edits/deletes persist and sync; saved shelf works; offline reads from cache.
```

#### P5.9 — Spaced repetition (FSRS reviews) `[Track D — pairs with P9.3]` · package: EngagementFeature
```
Build the Reviews feature (FSRS spaced repetition) from GET /book/me/reviews (due cards) and
GET|POST /book/me/reviews/{cardId} (grade 1–4). A "Reviews" tab: today's due count, a focused review
session (show card front → reveal back → grade Again/Hard/Good/Easy with the four-button FSRS UI),
progress through the session, and a done state. Cards carry book/chapter context and tone-keyed front/back.
- LOCAL SCHEDULING: cache due cards and the FSRS schedule locally so reviews work OFFLINE and so the app
  can schedule LOCAL NOTIFICATIONS for due cards (coordinate with P9.3). Grades queue via the outbox when
  offline. Implement/port the FSRS interval math in Models (pure, unit-tested) for local due calculation,
  reconciling with the server on sync.
- A streak-friendly, calm review UX with haptics on grade.
Definition of Done: builds; due cards load, a review session grades cards (online + offline), the local
schedule updates, and offline grades sync on reconnect. FSRS math unit-tested against known vectors.
```

#### P5.10 — Commitments (if-then plans) `[Track D]` · package: EngagementFeature
```
Build Commitments from GET|POST /book/me/commitments and GET|PATCH /book/me/commitments/{id}. After a
chapter, let the user set an if-then implementation commitment (3- or 7-day follow-up). Show active
commitments with their follow-up date; on follow-up, prompt a reflection + outcome (helped/partly/didnt).
These feed the chapter "application" axis. A local notification reminds at follow-up time (P9.3).
Definition of Done: builds; I can create a commitment from a chapter, see it active, get reminded at
follow-up, submit a reflection+outcome, and see the chapter's application badge update.
```

#### P5.11 — Scenarios (apply-it submissions) `[Track D]` · package: EngagementFeature
```
Build the Scenarios feature from GET|POST /book/me/books/{bookId}/chapters/{n}/scenarios. After a chapter,
let the user write their own real-world application scenario (title, scenario, whatToDo, whyItMatters,
scope work/school/personal). Show submission status (pending/approved/rejected via AI + moderation) with the
points awarded on approval, the user's past scenarios, and (if exposed) approved community scenarios for the
chapter as inspiration. Calm compose UX with validation; offline submissions queue.
Definition of Done: builds; I can submit a scenario from a chapter, see its moderation status and awarded
points, browse my past scenarios, and offline submissions sync on reconnect.
```

#### P5.12 — Celebrations & insight-spark system `[Track D — build early in pod]` · package: EngagementFeature/DesignSystem
```
Build the cross-cutting reward/celebration layer all features reuse, so wins feel great and consistent:
a CelebrationPresenter that, after the quiz-pass loop pipeline completes, sequences any earned moments —
loop complete, flow-points gained, streak increment/milestone, tier-up, badge earned, and "insight spark"
prompts — into one tasteful, non-spammy sequence (haptics + restrained animation, Reduce-Motion aware,
skippable). Pull the earned events from the post-quiz refresh of streak/tier/badges/points. A single source
of truth so individual features don't each fire competing celebrations.
Definition of Done: builds; completing a chapter that triggers multiple rewards shows ONE coherent
celebration sequence (not several overlapping), respects Reduce Motion, and is skippable; no duplicate confetti.
```

#### P5.13 — Daily goal & habit surface `[Track D]` · package: EngagementFeature
```
Build the daily-goal/habit surface: a "today" ring (chapters or minutes toward the user's daily goal from
onboarding/settings), a simple week view, and a gentle progress nudge. Feed the streak + widgets (P8.1) +
local reminders (P9.3). Let the user adjust the goal. Calm, motivating, never guilt-trippy.
Definition of Done: builds; the daily ring reflects real activity toward the goal, the week view is
accurate, adjusting the goal persists, and the data feeds widgets/reminders.
```

> **Integration checkpoint INT-5:** "Wire the Engagement features into the Home dashboard, Reviews tab, and Profile. Confirm streak/points/badges/tier all update after completing a chapter+quiz. Run on device."

### Phase 6 — AI features (Track E) · depends: P1, P2

#### P6.1 — Ask the book (AI Q&A) `[PARALLEL: Track E]` · package: AIFeature
```
Build "Ask the book" from POST /book/books/{bookId}/ask (returns answer + citations:[chapter numbers],
honors tone, daily-limited → 429 rate_limited). A chat-style sheet accessible from the Reader and Book
Detail: ask a question, show the answer with tappable citation chips that jump to the cited chapter,
remember recent Q&A per book, and show the remaining daily quota / a friendly limit state. Pass selected
reader text as context when launched from a highlight. Render answers cleanly (markdown-ish). Loading +
error + offline states (offline → suggest the on-device fallback from P6.5 if available).
Definition of Done: builds; asking returns a grounded answer with working citation jumps; the daily limit
is handled gracefully; launching from a highlight pre-fills context.
```

#### P6.2 — Audio narration player `[PARALLEL: Track E — large]` · package: AIFeature
```
Build a best-in-class audio narration player (a flagship "better than web" feature) from
GET /book/books/{bookId}/chapters/{n}/audio.
- AudioPlayer (AVPlayer-based) with: play/pause/seek, variable speed (0.75–2x), 15s skip, chapter
  auto-advance, and a sleep timer.
- BACKGROUND AUDIO: enable the background-audio capability; integrate MPNowPlayingInfoCenter (title,
  book, chapter, artwork from the emoji/color cover rendered to an image) and MPRemoteCommandCenter
  (lock screen + Control Center + headphones). AirPlay route picker. CarPlay-ready Now Playing.
- A full-screen Now Playing UI and a persistent mini-player bar above the tab bar that survives navigation.
- OFFLINE: download chapter audio (via the Phase 3 DownloadManager / background URLSession) and play
  offline; show downloaded state.
- Sync listening position with reading position where it makes sense; count audio time toward reading
  sessions/streak.
Definition of Done: builds; audio plays in the background with full lock-screen controls, speed + sleep
timer + AirPlay work, auto-advance works, downloaded audio plays offline, and the mini-player persists.
```

#### P6.3 — Concept graph `[PARALLEL: Track E]` · package: AIFeature
```
Build an interactive Concept Graph from GET /book/books/{bookId}/concept-graph (concepts:[{id,label,
introducedIn,summary}], edges:[{from,to,type:"prerequisite"}], chapterIntroduces/chapterRequires).
Render a clean, interactive node-link graph (a lightweight force-directed or layered layout in
SwiftUI/Canvas): tap a concept for its summary + the chapter that introduces it (jump to it), highlight
prerequisite chains, and show which concepts a given chapter requires/introduces. Pan/zoom; respect
Reduce Motion (static layout fallback). Premium, legible styling.
Definition of Done: builds; the graph renders the book's concepts with prerequisite edges, is pannable/
zoomable, and tapping a node shows its summary and jumps to its chapter.
```

#### P6.4 — Adaptive depth recommendation `[PARALLEL: Track E]` · package: AIFeature/ReaderFeature
```
Surface adaptive depth from GET /book/me/books/{bookId}/depth-recommendation (recommendedDepth, confidence).
When confidence is sufficient, gently suggest the recommended reading depth in the Reader's depth switcher
("Recommended for you") and on Book Detail, with a one-line why. Never force it; the user can always override.
Definition of Done: builds; when the server has enough data, the recommended depth is highlighted in the
switcher with a rationale; low-confidence hides the suggestion.
```

#### P6.5 — On-device intelligence (Apple Foundation Models) `[PARALLEL: Track E — optional flagship]` · package: AIFeature
```
Add on-device AI using Apple's Foundation Models framework (availability-gated to supported devices/OS;
degrade silently elsewhere). A genuine web-impossible feature set:
- "Summarize this chapter" and "Explain this highlight simply" generated fully on-device, offline, private.
- An OFFLINE fallback for "Ask the book" when the network is unavailable: answer from the downloaded
  chapter text using the on-device model, clearly labeled "offline answer."
- Smart highlight suggestions: surface candidate key sentences on-device.
Gate every entry point behind a capability check + a feature flag; never block the UI if unavailable.
Keep prompts grounded in the local chapter content to avoid hallucination; show a privacy note ("runs on
your device").
Definition of Done: builds; on a supported device, chapter summary + offline ask work with no network;
on unsupported devices the features hide cleanly with no errors.
```

#### P6.6 — CarPlay audio `[PARALLEL: Track E, after P6.2]` · target: app (CarPlay)
```
Add a CarPlay audio experience for narration: a CarPlay scene exposing the user's downloaded/in-progress
books and chapters as a now-playing audio list, with play/pause/skip/chapter-advance and the standard
CarPlay Now Playing template. Reuse the AudioPlayer from P6.2. Safe, glanceable, voice-friendly.
Definition of Done: builds; in the CarPlay simulator the app lists books, plays narration with transport
controls, advances chapters, and shows Now Playing; playback continues seamlessly with the phone player.
```

#### P6.7 — AI ask history & saved answers `[PARALLEL: Track E, after P6.1]` · package: AIFeature
```
Add persistence + reuse to "Ask the book": store the user's Q&A per book (locally, offline-readable), let
them revisit, pin/save useful answers into the Notebook (P5.8), copy/share an answer (with attribution),
and re-ask follow-ups with prior context. Show cached answers instantly. Respect the daily quota.
Definition of Done: builds; past questions/answers persist and are browsable offline; saving an answer puts
it in the notebook; follow-ups keep context; sharing works.
```

> **Integration checkpoint INT-6:** "Wire Ask, Audio (mini-player), Concept Graph, and depth suggestion into the Reader. Confirm background audio + offline ask work on device."

### Phase 7 — Social (Track F) · depends: P1, P2.1

#### P7.1 — Profile `[Track F — build first in pod]` · package: SocialFeature
```
Build Profile from GET /book/me/profile (+ dashboard stats). Own-profile: display name, avatar
(initials/emoji), equipped cosmetic frame/theme (from P5.4 inventory), tier, streak, badges preview,
books finished, and an edit-profile entry (PATCH /book/me/settings for display name etc.). A public/
partner-profile variant (read-only) for viewing a reading partner. This establishes SocialRepository.
Definition of Done: builds; own profile renders real stats + equipped cosmetics; editing the display name
persists; a public-profile variant renders for another user.
```

#### P7.2 — Reading partners (pairs) `[Track F]` · package: SocialFeature
```
Build accountability partners from GET /book/me/pairs, POST /book/me/pairs/invite (→ invite code/link),
POST /book/me/pairs/accept/{code}, GET|DELETE /book/me/pairs/{partnerId}, POST /book/me/pairs/{partnerId}/
nudge. Invite a partner (share a chapterflow://pair/accept/{code} Universal Link via ShareLink), accept an
invite (deep-link handled), see the partner's streak/progress, send a nudge, and end a pairing. Handle
pending/expired invites.
Definition of Done: builds; I can invite (share link), accept on another account via the link, see partner
progress, nudge them, and unpair; expired invites handled.
```

#### P7.3 — Gifts `[Track F]` · package: SocialFeature
```
Build gifting from GET /book/me/gifts/{code}, POST /book/me/gifts/{code}/claim (gift a "pro_week" using
flow points; claim a gift code). A "gift Pro" flow (spend IP → generate a shareable gift code/link) and a
"claim gift" flow (open chapterflow://gift/{code} → preview → claim → entitlement updates). Handle
already-redeemed/expired.
Definition of Done: builds; I can create a gift (IP deducted, code/link produced) and claim one on another
account (Pro granted); invalid/expired codes handled.
```

#### P7.4 — Reflections & AI feedback `[Track F]` · package: SocialFeature/ReaderFeature
```
Build chapter Reflections from GET|POST /book/me/reflections/{bookId}/{n} and POST .../feedback. After an
example, let the user write a reflection and request AI feedback on it (POST .../feedback returns
feedbackText). Show past reflections + feedback per chapter; calm, encouraging UX. Offline: queue the
reflection, fetch feedback when online.
Definition of Done: builds; I can write a reflection, get AI feedback, and see history; offline reflections
queue and resolve on reconnect.
```

#### P7.5 — Share cards `[Track F]` · package: SocialFeature
```
Build native Share Cards from POST /book/me/share-events (cardType chapter/badge/streak/book, destination).
Generate a beautiful shareable IMAGE (render a SwiftUI card → UIImage via ImageRenderer) for a completed
chapter, an earned badge, a streak milestone, or a finished book, embedding the user's referral code/link.
Use the system ShareLink/share sheet; log the share event. Premium, on-brand card design (DesignSystem).
Definition of Done: builds; each card type renders a crisp shareable image with referral link, the share
sheet presents it, and the share event posts.
```

#### P7.6 — Referrals `[Track F]` · package: SocialFeature
```
Build the Referral program UI (invite code from the referral profile; rewards on activation/Pro). A
"Invite friends" screen: the user's code/link, how rewards work, and invite stats (pending/activated/pro).
Share via ShareLink (chapterflow://ref/{code} Universal Link). Show earned rewards.
Definition of Done: builds; the referral screen shows the code/link + stats, sharing works, and reward
state reflects the server.
```

#### P7.7 — Safety: blocking, reporting & consent `[Track F — REQUIRED for App Review if social ships]` · package: SocialFeature
```
Because the app has user-to-user contact (reading partners, nudges, gifts, shared content), Apple requires
safety controls (Guideline 1.2). Build: block/unblock a partner, report a user or content (with reasons),
a mute/leave-pairing flow, rate-limiting on nudges to prevent harassment, and a clear consent step before
pairing. Blocked users can't pair/nudge/see your profile. Surface a code-of-conduct + report-handling note.
Wire reports to the backend (use the moderation/report endpoint; if none exists, define the client contract
and flag the backend TODO).
Definition of Done: builds; I can block, unblock, and report a partner; blocked users cannot contact me;
nudges are rate-limited; pairing requires consent; reporting submits. Meets Guideline 1.2.
```

#### P7.8 — Profile privacy controls `[Track F, after P7.1]` · package: SocialFeature/SettingsFeature
```
Give users control over what's shared: toggles for profile visibility (what a partner can see — streak,
progress, books), display-name vs real-name, opt-in/out of leaderboards/social surfaces, and discoverability.
Default to privacy-respecting. Persist via settings. Reflect choices everywhere a profile is shown (P7.1 public variant).
Definition of Done: builds; privacy toggles persist and are honored in the partner/public profile view;
defaults are private-friendly; opting out removes the user from social surfaces.
```

> **Integration checkpoint INT-7:** "Wire Profile, Partners, Gifts, Reflections, Share, Referrals together; verify a full partner invite→accept→nudge loop across two accounts and a chapter-share image."

### Phase 8 — Advanced native showcase (Track G) · depends: data from P2/P5/P6

> This is where the app decisively beats the web. These consume data already built; do them after the
> relevant features land. They share an App Group + a small `SharedState` writer the app updates so
> extensions read current streak/continue-reading/next-review without the network.

#### P8.0 — Shared app-group state writer `[Track G — build first in pod]` · package: Persistence
```
Add a SharedState writer: whenever streak, continue-reading (book+chapter+progress), next-due-review
count, or daily goal changes, write a compact snapshot to the App Group (UserDefaults + a tiny SwiftData
store) so widgets/Live Activities/the watch app read it instantly offline. Provide a typed reader API and
a WidgetCenter reload trigger on changes.
Definition of Done: builds; updating streak/continue/review in the app updates the shared snapshot and
triggers a widget timeline reload.
```

#### P8.1 — Home-screen widgets `[Track G]` · target: Widgets (WidgetKit)
```
Build a WidgetKit extension with several widgets reading the App Group SharedState (no network):
- Streak widget (small/medium): current streak, flame, at-risk indicator.
- Continue-reading widget (medium): current book cover + chapter + progress ring; tap → deep link into
  the reader (chapterflow://book/{id}/chapter/{n}).
- Progress-ring widget (small): today's reading-goal ring.
- Next-review widget (small): due-cards count; tap → Reviews.
Provide Lock Screen (accessory) variants. Use AppIntent-based configuration where useful. Premium,
legible, light/dark.
Definition of Done: builds; widgets render real shared data on the home + lock screen, update when the app
updates state, and tapping deep-links to the right screen.
```

#### P8.2 — Live Activities & Dynamic Island `[Track G]` · target: LiveActivity (ActivityKit)
```
Build Live Activities with ActivityKit:
- Reading-session activity: when a reading/audio session is active, show elapsed time + chapter on the
  Lock Screen and in the Dynamic Island (compact: progress; expanded: book/chapter + controls like
  pause for audio). End when the session ends.
- Streak-at-risk activity (optional, evening): a countdown nudging the user to read before the day ends.
Update via push-less local activity updates (and optionally APNs for the at-risk one).
Definition of Done: builds; starting a reading/audio session shows a Live Activity + Dynamic Island that
updates live and ends cleanly; audio controls in the Island work.
```

#### P8.3 — App Intents & Siri Shortcuts `[Track G]` · package: AppFeature/AIFeature
```
Add App Intents (Shortcuts + Siri + Spotlight) so the app is voice/automation-driven:
- "Start my daily reading" → opens the reader at continue-reading.
- "Review now" → opens a review session.
- "Read with ChapterFlow" audio intent → starts narration of the current chapter.
- An interactive "Log today's reading" intent.
Provide AppShortcutsProvider phrases, donate intents for Spotlight prediction, and make them work from the
Shortcuts app. Where possible, run inline (no app launch) for quick actions.
Definition of Done: builds; each intent appears in Shortcuts and runs via Siri; "Start my daily reading"
opens the right chapter; intents are donated for prediction.
```

#### P8.4 — Spotlight indexing `[Track G]` · package: LibraryFeature/CoreKit
```
Index the user's books + chapters into Core Spotlight (CSSearchableItem) with titles, authors, and a
deep-link identifier, so a system Spotlight search surfaces them and opens the right screen. Keep the
index in sync as the library/progress changes; remove on sign-out.
Definition of Done: builds; searching a book/chapter title in system Spotlight finds it and tapping opens
the app to that book/chapter.
```

#### P8.5 — Universal Links, deep linking & Handoff `[Track G]` · package: AppFeature
```
Complete system linking:
- Universal Links (apple-app-site-association on the web domain — coordinate with the web team) so
  https://chapterflow.app/book/... opens the app to the right screen; plus the chapterflow:// scheme for
  internal links. Centralize in the DeepLinkParser (extend P0.6) covering book/chapter, pair/accept, gift,
  review, paywall, journey, event.
- Handoff (NSUserActivity): start reading a chapter on web, continue on iPhone (and vice versa) via
  Continuity; advertise the current activity.
Definition of Done: builds; tapping a chapterflow web link opens the correct in-app screen; Handoff hands a
reading session between devices; all deep-link types route correctly.
```

#### P8.6 — Quick Actions, context menus, Focus filters `[Track G]` · package: AppFeature
```
Add system-integration polish: Home-screen Quick Actions (long-press the app icon → Continue reading /
Reviews / Ask). Rich context menus + drag-and-drop on book cards. An optional Focus filter ("Reading
Focus" surfaces only reading content / suppresses social). Keyboard shortcuts for iPad.
Definition of Done: builds; quick actions deep-link correctly; context menus + drag work; the Focus filter
toggles behavior.
```

#### P8.7 — Apple Watch companion `[Track G — STRETCH]` · target: WatchApp (watchOS)
```
Build a watchOS companion: a streak-ring complication + glance, today's due-reviews count with a quick
review session (front→reveal→grade) synced via the App Group/WatchConnectivity, and an audio remote
(play/pause/skip) for the narration player. Keep it minimal and glanceable.
Definition of Done: builds; the watch app shows streak + due reviews, can grade a few cards, and remote-
controls audio; complication updates.
```

#### P8.8 — iCloud sync & continuity `[Track G — STRETCH]` · package: Persistence
```
Optionally sync user-private preferences + highlights/notes across the user's devices via CloudKit
(SwiftData + CloudKit), keeping the API as the system of record for progress/entitlement. Resolve
conflicts last-writer-wins for prefs; merge highlights. Gate behind a setting.
Definition of Done: builds; toggling iCloud sync mirrors prefs + highlights to a second device signed into
the same iCloud + app account, without conflicting with server progress.
```

#### P8.9 — Control Center controls & interactive widgets `[Track G]` · target: Widgets
```
Add iOS 18 Controls (Control Center / Lock Screen / Action button): a "Start reading" control, a "Review
now" control, and an audio play/pause control — each backed by an App Intent (P8.3). Make the home-screen
widgets interactive where useful (e.g. mark a review done, start audio) via AppIntent buttons. 
Definition of Done: builds; the controls appear in the Control Center gallery and run their intents; the
Action button can be bound to "Start reading"; interactive widget buttons perform their action without launching the app.
```

#### P8.10 — Share & action extensions `[Track G — optional]` · target: ShareExtension
```
Add a Share Extension so the user can send a selected quote/text or a link INTO ChapterFlow to save as a
note/highlight (routed to the Notebook), and an Action Extension for "Ask ChapterFlow about this." Keep them
lightweight, App-Group-backed, and consistent with the design system.
Definition of Done: builds; selecting text in another app and sharing to ChapterFlow saves it to the
notebook; the action extension launches an ask flow; both respect auth state.
```

### Phase 9 — Notifications (Track H) · depends: P1, B2

#### P9.1 — APNs registration `[Track H]` · package: NotificationsFeature
```
Implement push registration:
- Add the Push Notifications + Background Modes (remote notifications) capabilities. Request authorization
  with a well-timed, explained pre-permission prompt (not on first launch — after the user sees value).
- Register with APNs, get the device token, and POST it to /book/me/devices/register with platform:"ios"
  (per backend change B2). Unregister on sign-out. Handle token refresh + permission changes; reflect
  status in Settings.
Definition of Done: builds; granting permission registers an APNs token with the backend; revoking/sign-out
unregisters; a test push from the backend is received.
```

#### P9.2 — Push handling & notification settings `[Track H, after P9.1]` · package: NotificationsFeature
```
Handle incoming pushes and preferences:
- Define notification categories/actions matching the server types (badge_earned, tier_up, streak_milestone,
  insight_spark, reading_reminder, streak_at_risk, partner_nudge, commitment_followup, event_reminder,
  scenario_approved/rejected). Tapping a notification deep-links to the right screen; add inline actions
  (e.g. "Review now", "Open chapter"). Support rich/mutable content (a Notification Service Extension for
  images) where useful.
- A Notification Settings screen bound to the server prefs (PATCH /book/me/settings: channels, reading
  reminder + time, streak reminder, badge/achievement alerts, weekly digest), plus the OS-level status with
  a deep link to system settings if denied.
Definition of Done: builds; each push type routes correctly on tap; inline actions work; the settings screen
reads/writes server prefs and reflects OS permission state.
```

#### P9.3 — Local notifications `[Track H — pairs with P5.9/P5.10]` · package: NotificationsFeature
```
Schedule LOCAL notifications (work offline, no server needed):
- Daily reading reminder at the user's reminderTimeLocal.
- Streak-at-risk reminder in the evening if no activity yet.
- Spaced-repetition due reminders from the local FSRS schedule (P5.9).
- Commitment follow-up reminders (P5.10).
Manage scheduling/cancellation as state changes (e.g. reading today cancels the at-risk reminder). Respect
the user's notification prefs and quiet hours.
Definition of Done: builds; reminders fire at the right local times, the at-risk reminder cancels once the
user reads, and review/commitment reminders match their schedules; all respect prefs.
```

#### P9.4 — Notification inbox `[Track H]` · package: NotificationsFeature
```
Build an in-app Notification inbox from GET /book/me/notifications and POST /book/me/notifications/read-all.
A list of past notifications (icon by type, title, body, relative time, unread dot), tap-through deep links,
mark-all-read, and an unread badge on the tab/profile. Offline from cache.
Definition of Done: builds; the inbox lists notifications with unread state, tapping deep-links, mark-all-
read works and clears the badge.
```

#### P9.5 — Permission priming & re-engagement strategy `[Track H, before P9.1 prompt fires]` · package: NotificationsFeature
```
Build the notification permission strategy that maximizes opt-in without being pushy: a pre-permission
priming screen shown at a high-value moment (e.g. after the first chapter, or when setting a reminder) that
explains the value before the OS prompt; a provisional-authorization path (quiet notifications) where
appropriate; a re-ask flow that deep-links to Settings if previously denied; and analytics on prompt
outcomes. Never prompt cold on first launch.
Definition of Done: builds; the OS prompt only appears after priming at a value moment; denied users get a
Settings deep link; provisional auth works; opt-in outcome is tracked.
```

#### P9.6 — Rich notifications (Notification Service Extension) `[Track H, after P9.2]` · target: NotificationService
```
Add a Notification Service Extension to enrich pushes: download + attach images (badge art, share-card
imagery, book covers), localize/format content, and decrypt/transform payloads as needed. Add a
Notification Content Extension for a custom expanded UI on key types (e.g. a badge celebration). Keep it
fast (within the extension time budget) with graceful fallback to the plain notification.
Definition of Done: builds; a push with an image renders the image in the banner/expanded view; the custom
content UI shows for the targeted type; failures fall back to the plain notification.
```

#### P9.7 — Notification analytics, quiet hours & coordination `[Track H, after P9.3]` · package: NotificationsFeature
```
Add delivery/engagement analytics (sent/received/opened by type) and a coordination layer so local + push
notifications never spam: per-day caps, quiet hours, de-duplication (don't send a local review reminder if
a push already covers it), and respect of all per-type prefs from P9.2. A "snooze" action on reminders.
Definition of Done: builds; notification opens are tracked by type; quiet hours + daily caps are enforced;
local/push duplicates are suppressed; snooze reschedules correctly.
```

> **Integration checkpoint INT-9:** "Verify a server push (badge earned) deep-links correctly, a local review reminder fires offline, and the inbox + unread badge stay in sync."

### Phase 10 — Quality, settings, onboarding & launch

> Accessibility (P10.3) and testing (P10.5) should be applied **continuously** during all phases, not
> deferred. They're listed here as final hardening passes.

#### P10.1 — Onboarding & first-run `[SEQUENTIAL — early-ish, before launch]` · package: OnboardingFeature
```
Build a premium first-run onboarding (post-sign-up) from POST /book/me/onboarding/progress and
/complete. A short, beautiful flow: welcome value-props, pick interests/categories, choose default
reading DEPTH and TONE (gentle/direct/competitive), set a daily reading goal + reminder time (ties to
P9.3), and optionally request notification permission with context. Persist choices (server + AppPreferences).
Skippable, resumable (progress endpoint). Apple-Pro restraint, big type, smooth transitions.
Definition of Done: builds; a new user completes onboarding, choices persist to server + prefs and shape
the reader defaults, and the flow is resumable if interrupted.
```

#### P10.2 — Settings & account lifecycle `[SEQUENTIAL]` · package: SettingsFeature
```
Build Settings from GET|PATCH /book/me/settings plus account routes. Sections: Account (email, manage
subscription → App Store, plan/renewal info), Reading (default depth, tone, theme, font scale, audio
speed), Notifications (link to P9.2 prefs), Downloads (P3.2 storage management), Privacy & Legal (link to
the legal pages — Privacy/Terms/Refund/Data-rights, mirroring the web /legal/* content), Data (export via
GET /book/me/export; download/share the export), Danger zone (deactivate via POST /book/me/account/
deactivate, delete via POST /book/me/account/delete with confirmation + consequences explained), App lock
(Face ID), and About (version, the B4 message-of-the-day). Sign out.
Definition of Done: builds; every setting reads/writes correctly; export produces a file; deactivate/delete
flows confirm + execute + sign out; legal pages render; manage-subscription opens the App Store.
```

#### P10.3 — Accessibility pass `[CONTINUOUS — final audit]` · all packages
```
Do a full accessibility audit and fix: VoiceOver labels/traits/order on every screen (especially the
Reader, Quiz, and charts — provide audio-graph/summary alternatives for Swift Charts); Dynamic Type up to
the largest accessibility sizes with no clipping or truncation (reflow, don't shrink); color-contrast AA+
in light and dark; Reduce Motion honored for every animation; Reduce Transparency; sufficient tap targets;
Voice Control labels; and correct focus management on navigation + sheet presentation. Add accessibility
snapshot/unit checks where feasible.
Definition of Done: VoiceOver can complete the core loop (find book → read → quiz → review) unaided; the UI
is usable at AX5 text size; an accessibility audit (Accessibility Inspector) reports no critical issues.
```

#### P10.4 — Performance pass `[CONTINUOUS — final audit]` · all packages
```
Profile and optimize: cold-launch time (defer non-critical work; lazy-load), Reader scroll at 120Hz on
ProMotion (no hitches; pre-resolve content; avoid layout thrash), image/cover rendering cost, memory
footprint with large downloaded books, SwiftData query efficiency (batch/index), and main-thread isolation
(no blocking I/O on @MainActor). Use Instruments (Time Profiler, SwiftUI, Hangs). Add a perf budget note.
Definition of Done: cold launch under ~1.5s on a recent device; Reader scrolls at a steady 120Hz with no
hangs in Instruments; memory stays bounded opening several large books; no main-thread stalls flagged.
```

#### P10.5 — Test suite `[CONTINUOUS — final hardening]` · all packages
```
Bring the test suite to a confident baseline: unit tests for all model decoding (every fixture), the
ChapterContentResolver, EntitlementEvaluator, FSRS math, the SyncEngine conflict/idempotency logic, the
Networking error mapping + refresh/retry, and the auth token-refresh decision. UI tests (XCUITest) for the
3 critical flows: sign-in, read→quiz→unlock, purchase (StoreKit test mode). Snapshot tests for the
DesignSystem gallery in light/dark + XXL. Wire it all into a CI workflow (GitHub Actions: build + test on
a simulator) and require green to merge.
Definition of Done: all tests pass locally + in CI; the three XCUITest flows are green; coverage on Models/
Networking/Persistence logic is high; CI blocks red PRs.
```

#### P10.6 — Analytics, crash reporting & observability `[SEQUENTIAL]` · package: CoreKit
```
Finish observability: ensure the AnalyticsClient fires the full funnel (app_open, onboarding steps,
book_started, chapter_opened, quiz_submitted/passed, paywall_viewed, purchase, review_completed, share,
referral) to /book/me/analytics/track + beacon, batched and privacy-respecting. Add crash + non-fatal
reporting (MetricKit for crash/hang/energy diagnostics → your backend, or a lightweight third-party if
preferred). Add a debug menu (shake) to inspect state/flags in non-release builds.
Definition of Done: builds; key events appear server-side; MetricKit diagnostics are captured and uploaded;
the debug menu works in debug only.
```

#### P10.7 — App Store preparation & submission `[SEQUENTIAL — last]` · project
```
Prepare for App Store submission:
- App icon (all sizes) + a polished launch screen. Marketing screenshots (use the Reader, dashboard,
  audio, widgets) for all required device sizes; an App Preview video optional.
- App Store Connect: app record, subscription products (matching P4.1 ids) with localized display names,
  review screenshot, and the subscription group; pricing.
- Privacy: complete the App Privacy "nutrition label" accurately (what's collected: account, usage,
  purchases, identifiers; how used; linked to identity). Add the privacy manifest (PrivacyInfo.xcprivacy)
  declaring API usage + tracking domains. Ensure required-reason APIs are declared.
- App Review notes: a demo account, an explanation that subscriptions use StoreKit IAP and grant the same
  Pro entitlement, and how to test the core loop. Address Guideline 3.1.1 (IAP), 4.2 (this is a full native
  app, not a wrapper), 5.1.1 (account creation + the in-app account deletion you built in P10.2).
- Build with a Release config, archive, validate, upload to TestFlight; run an internal + external beta;
  then submit for review.
Definition of Done: a Release archive validates and uploads; TestFlight build installs and runs the full
loop; the App Privacy + privacy manifest are complete; the app is submitted for review with demo creds + notes.
```

#### P10.8 — In-app review prompt `[SEQUENTIAL]` · package: CoreKit
```
Add a well-timed App Store review request (SKStoreReviewController / RequestReviewAction): trigger only
after a genuine positive moment (e.g. passing a quiz on a 3+ day streak, finishing a book), rate-limited to
Apple's annual cap, never after a failure or error, and never more than once per version. Make the trigger
policy a small testable rule. No custom "rate us?" pre-prompt that violates guidelines.
Definition of Done: builds; the review sheet requests only at positive moments within Apple's limits; the
trigger policy is unit-tested; it never fires after errors.
```

#### P10.9 — What's New / release notes `[SEQUENTIAL]` · package: SettingsFeature
```
Build a "What's New" screen shown once after an app update (compare last-seen version), highlighting new
features with tasteful visuals, plus an always-available entry in Settings/About. Drive content from a
bundled list (or the B4 config message-of-the-day). Skippable, accessible.
Definition of Done: builds; updating the app shows What's New once; it's reachable from Settings; version
tracking prevents re-showing.
```

#### P10.10 — Force-update & maintenance handling `[SEQUENTIAL, uses B4]` · package: AppFeature
```
Use GET /book/config/ios (B4) at launch + foreground to enforce: a hard "update required" gate when below
minSupportedVersion (block with an App Store link), a soft "update available" nudge, and a maintenance-mode
screen when the backend signals downtime. Fail OPEN (never lock users out) if the config can't be fetched.
Cache the last config for offline.
Definition of Done: builds; simulating minSupportedVersion above the build shows the hard gate with a Store
link; a soft nudge is dismissible; maintenance mode shows the downtime screen; a config-fetch failure does NOT lock the app.
```

#### P10.11 — Localization extraction & QA pass `[CONTINUOUS — final]` · all packages
```
Finalize localization: verify every user-facing string is in a String Catalog (no hardcoded text — audit
with a pseudo-locale that reveals untranslated strings and truncation), confirm all dates/numbers/durations/
prices format per locale, validate RTL mirroring on every screen, and prepare the catalogs for translators
(comments/context on ambiguous keys). Decide launch locales (English first) and stub the pipeline for more.
Definition of Done: pseudo-localization shows zero missing keys and no truncation/overflow; RTL is correct
app-wide; formatters respect locale; catalogs are translator-ready.
```

#### P10.12 — Visual QA matrix `[CONTINUOUS — final]` · all packages
```
Run a systematic visual QA across the matrix and fix issues: light + dark mode on every screen; Dynamic
Type from XS to AX5; device sizes (smallest iPhone SE → Pro Max → iPad portrait/landscape/split); high-
contrast + reduce-transparency; and empty/loading/error states. Add snapshot tests (light/dark + a large
type size) for the design system and the top 10 screens to prevent regressions.
Definition of Done: no clipping/overflow/contrast issues across the matrix; snapshot tests cover the key
screens and are green; a documented checklist is completed.
```

#### P10.13 — Security & privacy-manifest review `[SEQUENTIAL — pre-submission]` · repo
```
Final security + privacy audit: complete and verify PrivacyInfo.xcprivacy (required-reason API
declarations: UserDefaults, file timestamp, etc., and any tracking domains), confirm the App Privacy
"nutrition label" matches actual data flows, verify no secrets/keys are in the bundle or git history, that
all traffic is HTTPS (ATS), tokens are correctly protected in Keychain, logs are PII-free, and third-party
SDKs (Amplify, etc.) declare their privacy manifests. Run a dependency/license check.
Definition of Done: the privacy manifest validates and matches the App Privacy label; no secrets in bundle/
history; ATS clean; required-reason APIs declared; third-party manifests present; audit checklist signed off.
```

#### P10.14 — ASO assets & screenshot automation `[SEQUENTIAL — pre-submission]` · repo
```
Produce App Store marketing assets: localized screenshots for every required device size (automate with a
UITest-driven screenshot run / fastlane snapshot hitting the Reader, dashboard, audio, widgets in seeded
states), an optional App Preview video, the app icon, and metadata (name, subtitle, keywords, description,
promo text). Keep copy on-brand (premium, science-led, no competitor names — per brand guidelines).
Definition of Done: a screenshot run generates a full localized set across device sizes; metadata + keywords
drafted; assets meet App Store spec dimensions.
```

#### P10.15 — Compliance: ratings, export, data rights `[SEQUENTIAL — pre-submission]` · repo
```
Complete legal/compliance: set the App Store age rating accurately; declare export-compliance (encryption —
standard HTTPS exemption) in Info.plist/App Store Connect; ensure GDPR/CCPA data-rights are fully honored in-
app (the export from P10.2 + delete + deactivate), with the legal pages (privacy/terms/refund/data-rights)
reachable; confirm the subscription terms + auto-renew disclosures; and verify account-deletion is
discoverable (Guideline 5.1.1(v)).
Definition of Done: age rating + export compliance set; data export/delete/deactivate work and are
discoverable; all legal pages reachable; subscription disclosures present.
```

#### P10.16 — Release runbook & versioning `[SEQUENTIAL — final]` · repo
```
Establish the release process: semantic versioning + build-number automation, a tagged release + changelog
flow, a TestFlight internal→external beta checklist, a crash/feedback triage loop during beta, a phased-
release plan for the App Store rollout, and a rollback/hotfix plan. Document the whole "cut a release"
runbook in the repo.
Definition of Done: a documented, repeatable release runbook exists; version/build numbers auto-increment; a
TestFlight build is distributed to external testers; the phased-release + rollback plan is written down.
```

> **Final integration INT-10:** "Full regression on device from a clean install: onboarding → read/quiz/
> review loop → offline download+read → purchase (sandbox) → widgets/audio/notifications → settings/delete.
> Fix anything before archiving."

---

## 7. App Store submission checklist

- [ ] **In-App Purchase (Guideline 3.1.1):** subscriptions use StoreKit, not Stripe, inside the app. Restore works. Auto-renew disclosure + Terms/Privacy links on the paywall.
- [ ] **Not a wrapper (Guideline 4.2):** native SwiftUI, offline, widgets, audio, notifications — clearly app-like.
- [ ] **Account deletion in-app (Guideline 5.1.1(v)):** the Settings → delete flow (P10.2) is reachable and works.
- [ ] **Sign in with Apple (4.8 / 5.1.1):** offered alongside email auth.
- [ ] **App Privacy label + `PrivacyInfo.xcprivacy`** complete and accurate; required-reason APIs declared.
- [ ] **Permissions** have purpose strings (notifications, Face ID, etc.) with clear, honest copy.
- [ ] **Demo account** + review notes provided.
- [ ] **No private APIs, no hidden features, no placeholder content.**
- [ ] **Apple Developer Program** enrolled ($99/yr); certificates/profiles set; bundle id matches.
- [ ] **Content rights:** confirm the book content licensing is reflected (the corpus is owner-controlled).

## 8. Risks & gotchas

| Risk | Why it matters | Mitigation |
|---|---|---|
| **Apple's 30% / IAP rule** | The biggest one for a subscription content app. | StoreKit (Phase 4) + backend B3; keep Stripe for web only. Consider the "reader app" external-link entitlement as an alternative if you prefer subscribe-on-web. |
| **CSRF guard blocks native writes** | The web API's same-origin guard rejects header-only requests. | Backend B1 exempts Bearer-authed requests. Verify PATCH/POST work from the app early. |
| **Content shape is tone- & variant-keyed** | Naive decoding loses content or crashes on union types. | `ChapterContentResolver` + thorough fixture tests (P2.1). Capture real responses as fixtures. |
| **Gating must stay server-truth** | Client must never grant unlocks (security). | Sync engine pushes cursor/notes only; pulls gating (P3.4). |
| **Two state shapes** (`BookProgress` numbers vs `BookUserBookState` chapterIds) | Easy to mismap chapter number ↔ chapterId. | Map via the pinned manifest exactly as the server does; test it. |
| **Cognito native auth friction** | SRP/refresh/Apple federation are fiddly. | Use Amplify Auth (P1.1); validate against a real test pool early. |
| **Offline sync conflicts / dup quiz submits** | Data integrity. | Idempotent replays keyed on attempt; server authority; tests (P3.4). |
| **Ship-twice tax** | Every new web feature must be rebuilt natively. | Accept it (you chose native); keep the API as the shared contract; consider a feature-flag config (B4) to coordinate. |
| **Large downloaded books / memory** | Perf + storage. | Storage caps + eviction (P3.2); stream where possible; profile (P10.4). |
| **Universal Links need web coordination** | AASA file on the web domain. | Coordinate with the web team; chapterflow:// scheme works meanwhile. |
| **App Review rejection on first try** | Common for payments/privacy. | Follow Section 7; budget 1–2 resubmits. |

---

## Appendix A: Codable model catalog

Build these in `Models` (Section 3.4 explains the content nuances). Names are suggestions; match server JSON keys (server uses lowerCamel). Use `enum VariantKey: String, Codable, CaseIterable`, `enum ToneKey: String` (gentle/direct/competitive).

- **ToneKeyed** `{ gentle, direct, competitive: String }` + a `resolve(_ tone:)`.
- **BookCatalogItem** `{ bookId, title, author, categories:[String], tags:[String], cover:Cover?, variantFamily:VariantFamily, status, latestVersion:Int, currentPublishedVersion:Int?, updatedAt:String }`; `Cover { emoji:String?, color:String? }`.
- **BookManifest / BookManifestChapter** `{ chapterId, number:Int, title, readingTimeMinutes:Int, chapterKey, quizKey }`.
- **Chapter** `{ chapterId, number:Int, title, readingTimeMinutes:Int, activeVariant:VariantKey, availableVariants:[VariantKey], content:ChapterVariantContent, contentVariants:[VariantKey:ChapterVariantContent], examples:[Example], implementationPlan:ImplementationPlan?, reviewCards:[ReviewCard]?, keyTakeawayCard:ToneKeyed?, v21Extras:V21ChapterExtras? }`.
- **ChapterVariantContent** — tone-keyed fields: `{ chapterBreakdown:ToneKeyed?, keyTakeaways:[KeyTakeaway]?, oneMinuteRecap:OneMinuteRecap?, activationPrompt:ToneKeyed?, selfCheckPrompts:[ToneKeyed]?, reflectionPrompts:[ToneKeyed]?, importantSummary:String?, summaryBullets:[String]?, takeaways:[String]?, practice:[String]? }`. `KeyTakeaway { point:ToneKeyed, moreDetails:ToneKeyed? }`. `OneMinuteRecap` = `ToneKeyed` OR `{ retrieve, connect, preview: ToneKeyed }` (decode either).
- **Example** `{ exampleId:String?, title:String?, scenario:StringOrTone, whatToDo:StringsOrTone, whyItMatters:StringOrTone, contexts:[String]?, category:String? }` — note `scenario/whyItMatters` are `String | ToneKeyed`, `whatToDo` is `[String] | ToneKeyed` (write `StringOrTone`/`StringsOrTone` enums that decode either).
- **ImplementationPlan** `{ coreSkill:ToneKeyed?, concreteAction:ToneKeyed?, ifThenPlans:[{context:String, plan:ToneKeyed}]?, twentyFourHourChallenge:ToneKeyed?, weeklyPractice:ToneKeyed?, friction:ToneKeyed?, checkpoint:ToneKeyed? }`.
- **V21ChapterExtras** `{ hook:String?, counterintuition:String?, tryThisNow:String?, keyTakeaway:String?, memorableLines:[{text, location?, why?}]?, experiencePlan:V21ExperiencePlan? }`. **V21ExperiencePlan** `{ failureRecovery:{normalizingLine,cueQuestion,options:[String],repairLine}?, transferPrompt:{prompt,contexts:[String]}?, behaviorLoop:{readerPatterns:[{id,label,mapsToPlanIndex?,mapsToExampleIndex?}]}? }`.
- **ReviewCard** `{ cardId:String?, front:ToneKeyed, back:ToneKeyed, difficulty:String? }`.
- **ConceptGraph** `{ concepts:[{id,label,introducedIn,summary?}], edges:[{from,to,type}], chapterIntroduces:[String:[String]], chapterRequires:[String:[String]] }`.
- **BookProgress** `{ currentChapterNumber:Int, unlockedThroughChapterNumber:Int, completedChapters:[Int], bestScoreByChapter:[String:Int], preferredVariant:VariantKey?, progressRev:Int? }`.
- **BookUserBookState** `{ currentChapterId, completedChapterIds:[String], unlockedChapterIds:[String], chapterScores:[String:Int], chapterCompletedAt:[String:String], lastReadChapterId, lastOpenedAt }` + **applicationStates** `[String:ChapterApplicationState]` (none/committed/applied).
- **QuizClientSession** `{ questions:[QuizQuestion], passingScorePercent:Int?, ...session state }`; **QuizQuestion** `{ questionId, prompt/stem:String, choices:[{choiceId,text}] }` (mirror the server's `buildQuizClientSession` choiceId scheme — capture a real response). **QuizAttemptResult** `{ passed:Bool, scorePercent:Int, correctCount:Int, totalQuestions:Int, cooldownSeconds:Int, nextEligibleAttemptAt:String?, unlockedNextChapter:Bool, questionResults:[{questionId, selectedChoiceId?, correctChoiceId, isCorrect}] }`.
- **Entitlement** `{ plan:Plan(FREE/PRO), proStatus:String?, proSource:String?, freeBookSlots:Int, unlockedBookIds:[String], unlockedBooksCount:Int, remainingFreeStarts:Int, currentPeriodEnd:String?, cancelAtPeriodEnd:Bool, licenseKey:String?, licenseExpiresAt:String? }`; **Paywall** `{ price:String, pricingTiers:[PricingTier], benefits:[String] }`.
- Engagement: **Streak, Tier, Badge, FlowPointsLedgerEntry, ShopItem, Journey, Event, Commitment, NotebookEntry, FsrsCard** — model from the `types.ts` shapes in Section 3 / the repo.

> **Tip for Claude:** capture real JSON by hitting each endpoint once (with a dev token) and save under `Fixtures/`. Decode-test against those — they are the contract.

## Appendix B: Endpoint quick reference

See Section 3.3 for the grouped list of all 74 routes. Build a typed `Endpoint` factory per feature; auth = `Authorization: Bearer <id_token>` on everything except `GET /book/books` (public). Success = raw object; error = `{error:{code,message,requestId}}`.

---

*End of plan. Start with **B1** (web repo), then **P0.1**, and follow the dependency graph in Section 5. Keep this file at `docs/PLAN.md` in the iOS repo so Claude in Xcode can read it on every task.*







