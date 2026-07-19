# WP-AUDIO-01 — Align narration and harden background playback

## Problem and verified root cause

iOS expects AudioNarrationResponse with a plan envelope and segment kind while backend source returns a raw plan with segment type. Reader does not compose Listen, and background/interruption/route-change/device behavior lacks exact proof.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Align the narration request/response with WP-CONTRACT-02 through one canonical adapter and exact fixtures.
2. Keep one media-state owner for queue, position, rate, route, interruption, remote controls, and background lifecycle.
3. Cancel stale plan/audio work and refresh expired asset URLs without losing text reading or position.
4. Wire Listen into the exact reader context with accessible now-playing, controls, and truthful failure/offline states.
5. Add privacy-safe scenario hooks and bounded metrics so WP-DEVICE-01 can measure long playback, memory, energy, buffering, routes, and interruptions on the exact final candidate.
6. Localize every package-owned playback label/status and prove the surface across the complete native matrix.
7. Cancel and clear queue, position, artwork, route, errors, downloads, and cached plan across account A → sign out → account B.

## Acceptance criteria

### AC-AUDIO-01-01

- Given the canonical narration route returns a plan
- When the iOS decoder runs
- Then the exact envelope/discriminator succeeds and mismatched/unknown segments fail or degrade deliberately

### AC-AUDIO-01-02

- Given chapter A audio is superseded by chapter B or playback closes
- When late work completes
- Then A cannot replace B's queue, artwork, position, or error state

### AC-AUDIO-01-03

- Given an interruption, route change, lock, background, or expired URL occurs
- When playback lifecycle runs
- Then state and remote controls reconcile truthfully and text reading remains available

### AC-AUDIO-01-04

- Given Listen is invoked from Reader
- When the session opens and closes
- Then book/chapter/segment/position identity remains exact and no second media owner appears

### AC-AUDIO-01-05

- Given the final-device audio scenario and metrics schema
- When package instrumentation is exercised in deterministic tests
- Then required state/timing/memory fields are revision-bound, privacy-safe, behavior-neutral, and ready for WP-DEVICE-01

### AC-AUDIO-01-06

- Given every required native matrix dimension and a real translated locale
- When Reader Listen, now playing, lifecycle, and recovery states render
- Then controls/status remain localized, ordered, focused, comfortably targetable, and non-color-only

### AC-AUDIO-01-07

- Given account A has active or cached audio state
- When account A signs out and account B starts
- Then A's queue, position, artwork, route, errors, downloads, and plan cannot appear for B

## Lifecycle and adverse states

Cover no plan, partial/unknown segments, offline, slow stream, expired URL, cancellation, rapid chapter switch, headphone/Bluetooth route change, call/Siri interruption, lock/background, relaunch, auth expiry, and memory pressure.

## Invariant matrix

- **Architecture:** Use the existing composition/domain owners and narrow protocols; do not introduce a production singleton, duplicate repository, router, session, or outbox.
- **Navigation:** Preserve exact destination identity and one replay; if this package has no navigation, prove it does not alter route ownership.
- **Concurrency:** Honor Swift 6 isolation, structured task lifetime, cancellation, stale-result rejection, and Sendable boundaries; no unsafe escape without a tested invariant.
- **Account:** Explicitly distinguish public from account-private state; no empty, anonymous, or fallback owner for authenticated durable data.
- **Authority:** Identity, account status, entitlements, unlocks, grading, rewards, and moderation remain server-authoritative and fail closed.
- **Privacy:** No secrets, tokens, private user content, identifiers, receipts, or raw URLs in logs, analytics, fixtures, screenshots, or evidence.
- **Accessibility:** All changed UI covers VoiceOver semantics/focus, AX Dynamic Type, contrast/non-color status, Reduce Motion/Transparency, and comfortable targets.
- **Localization:** All changed user/accessibility copy is localized and tested with long text and RTL where visible.
- **Performance:** Do not block the main actor with file/JSON/image/network work; measure before making a performance claim and retain cancellation.
- **Observability:** Use fixed privacy-safe events and request IDs where diagnostic value exists; instrumentation failure cannot change product behavior.
- **Domain:** AudioPlayerModel or the established media coordinator is sole owner; Reader supplies context and observes narrow state.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** WP-CONTRACT-02 narration shape and verified asset authorization/expiry behavior are mandatory.
- **Compatibility:** One source-proven adapter may accept a deployed legacy envelope; canonical encode/cache remains current.
- **Migration:** Persisted audio position/plan changes require account/book/chapter/version migration or safe invalidation without progress loss.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Disable incompatible audio while preserving text Reader and position; never mark failed media complete.

## Explicit non-goals and release boundary

- Blocking text reading on audio
- Multiple AVAudioSession owners
- Guessing asset URL lifetime
- Release background-mode/signing action
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/AIFeature --parallel.
2. swift test --package-path Packages/Networking --parallel.
3. swift test --package-path Packages/ReaderFeature --parallel.
4. targeted Reader-to-Listen XCUITest.
5. scenario-hook/privacy tests; final interruption/route/background/memory evidence runs in WP-DEVICE-01.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
