# WP-ASK-01 — Make Ask streaming, privacy, and citations exact

## Problem and verified root cause

iOS models a JSON Ask response and question/answer history while the current backend route accepts role/content history and emits SSE. Reader composition does not wire selection/Ask end to end, and citation validity/cancellation are unproven.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Adopt the canonical WP-CONTRACT-02 Ask transport without a parallel client path.
2. Bind every request to intended account/book/chapter/selection/tone history and cancel superseded streams.
3. Validate citations against exact book/chapter/source identity before enabling navigation.
4. Expose explicit offline, quota/rate-limit, moderation, stream-interrupted, retry, and on-device-label states.
5. Keep questions, selections, answers, and citations out of logs/analytics/evidence.
6. Make Ask usable across compact/iPad, AX text, keyboard, a real locale, pseudo-long text, RTL, VoiceOver, contrast, and motion settings.
7. Keep every stream, cached thread, retry context, and citation owner-bound across account A → sign out → account B; unknown ownership restores nothing.

## Acceptance criteria

### AC-ASK-01-01

- Given the exact backend Ask route is pinned
- When a canonical request and SSE response are exercised
- Then history/framing/error/terminal semantics decode without the old JSON assumption

### AC-ASK-01-02

- Given question A is superseded by B or the view closes
- When A emits late events
- Then A is cancelled and cannot append text, citations, quota, or error state

### AC-ASK-01-03

- Given a citation arrives
- When identity and bounds are validated
- Then valid citations route to the exact source and invalid ones remain non-navigable with safe diagnostics

### AC-ASK-01-04

- Given offline, rate-limited, moderated, interrupted, and on-device fallback cases occur
- When the Ask surface updates
- Then each state is localized, accessible, truthful, and preserves the question/context where safe

### AC-ASK-01-05

- Given privacy-safe logging is captured
- When Ask is exercised
- Then no question, selection, answer, citation text, auth header, or private identifier appears

### AC-ASK-01-06

- Given compact iPhone, resizable iPad, AX text, keyboard, a real locale, pseudo-long text, RTL, VoiceOver, contrast, and Reduce Motion
- When Ask input, streaming, citations, errors, and recovery render
- Then the question and all actions remain present, ordered, focused, comfortably targetable, and localized

### AC-ASK-01-07

- Given account A has an active or cached Ask conversation
- When account A signs out and account B starts
- Then A's question, selection, answer, citations, retry, and stream state are absent for B

## Lifecycle and adverse states

Cover empty/long questions, rapid resubmit, partial SSE, malformed event, disconnect/reconnect, cancellation, backgrounding, auth expiry, quota, moderation, offline, relaunch, and account switch.

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
- **Domain:** AskTheBookModel owns stream state; Reader provides explicit context; Networking owns transport.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** WP-CONTRACT-02 canonical SSE and request history shape; server citations are validated, not trusted blindly.
- **Compatibility:** If a verified deployed JSON compatibility path exists, isolate it behind one adapter with tests; do not maintain two authorities.
- **Migration:** Cached Ask threads remain account-scoped and need versioned shape migration/quarantine if changed.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Rollback disables incompatible Ask rather than restoring a false JSON success path.

## Explicit non-goals and release boundary

- Inventing server citations
- Sending private content to analytics
- On-device output labeled as server-grounded
- Reader-wide rewrite
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/AIFeature --parallel.
2. swift test --package-path Packages/Networking --parallel.
3. swift test --package-path Packages/ReaderFeature --parallel.
4. deterministic SSE/cancellation/privacy tests.
5. targeted Ask/citation XCUITest and accessibility evidence.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
