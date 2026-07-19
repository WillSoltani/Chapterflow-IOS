# WP-ANNOTATE-01 — Align notes, highlights, and bookmarks with one durable contract

## Problem and verified root cause

Current iOS generic notebook CRUD and identifiers differ from the backend highlight-centric collection contract. Local annotation sync is centralized, but compatibility, offline state, and server ownership are not end-to-end proven.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Resolve D-ANNOTATION-01 against WP-CONTRACT-02: use a source-proven supported capability or an
   explicitly local-only truthful policy; a new backend capability requires split/replan before edits.
2. Keep one account-scoped local journal and one mutation identity per user action.
3. Represent queued, syncing, failed, conflict, and synchronized states truthfully; preserve failed/unknown work.
4. Map server evolution deliberately and encode only the canonical cache shape.
5. Prove privacy, selection context, editing/deletion, relaunch, offline/reconnect, and account switching.
6. Add package-local annotation strings and run the complete candidate-head native matrix.

## Acceptance criteria

### AC-ANNOTATE-01-01

- Given canonical backend notebook capability is pinned
- When a note/highlight/bookmark mutation is built
- Then method/path/body/identifier/envelope match exact evidence or the unsupported action is absent

### AC-ANNOTATE-01-02

- Given a user saves offline and relaunches
- When the account returns and reconnects
- Then the exact mutation remains durable, displays pending, and is submitted at most once

### AC-ANNOTATE-01-03

- Given a mutation is malformed, unknown, or receives uncertain delivery
- When the drain runs
- Then the item is quarantined/retained and never deleted as successful

### AC-ANNOTATE-01-04

- Given account A has pending annotations and signs out before B signs in
- When B opens the same book
- Then B cannot see or drain A's content

### AC-ANNOTATE-01-05

- Given edit/delete conflicts or auth expiry occur
- When the UI recovers
- Then context and private text remain intact, status is announced, and no false success appears

### AC-ANNOTATE-01-06

- Given every mandatory native dimension and a real translated locale
- When note/highlight/bookmark edit, pending, conflict, error, and auth-recovery states render
- Then content, status, focus, announcements, targets, motion/transparency, and non-color meaning remain usable

## Lifecycle and adverse states

Cover selection loss, overlapping notes, rapid save/delete, offline, retryable/terminal/uncertain failure, auth expiry, sign-out, A→B, relaunch, server alias evolution, and malformed cached data.

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
- **Domain:** LiveAnnotationRepository/journal is the sole mutation owner; Reader composes UX but does not duplicate persistence.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** WP-CONTRACT-02 notebook evidence is mandatory; unsupported server capability is not simulated in production.
- **Decision:** D-ANNOTATION-01 must name cross-device supported capability or an explicitly local-only
  user contract. Existing private data is preserved/quarantined while blocked; no silent deletion.
- **Compatibility:** Canonical-first decoding; only source-proven aliases; no lossy decoding for private mutation authority.
- **Migration:** Journal/envelope changes require versioned migration/quarantine tests from every supported prior shape.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Rollback preserves pending private items and cannot restore silent-success deletion.

## Explicit non-goals and release boundary

- A second outbox
- Invented generic backend CRUD
- Adding a new backend capability without a reviewed successor package
- Logging selections/user text
- Unrelated Reader redesign
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. swift test --package-path Packages/ReaderFeature --parallel.
2. swift test --package-path Packages/Networking --parallel.
3. swift test --package-path Packages/Persistence --parallel.
4. deterministic offline/relaunch/A-to-B annotation integration tests.
5. targeted annotation accessibility UI tests.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
