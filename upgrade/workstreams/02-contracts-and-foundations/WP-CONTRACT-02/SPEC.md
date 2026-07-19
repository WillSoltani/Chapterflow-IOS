# WP-CONTRACT-02 — Pin executable contracts for the broken central-loop operations

## Problem and verified root cause

Static source proves four incompatible operations: account delete body/reauth, Ask JSON versus SSE and history shape, narration envelope/discriminator, and notebook CRUD shape. Existing tests encode client assumptions without one source-derived executable comparison.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Derive canonical request, success, error, auth, and storage shapes from exact backend routes and serializers.
2. Add deterministic fixtures/canaries for account delete, Ask streaming, narration plan, and notebook operations.
3. Make each mismatch fail explicitly before feature packages change production callers.
4. Preserve canonical versus deployed-compatible evidence separately and keep deployed revision unknown until proven.
5. Regenerate twice and prove byte-identical output without hand-massaging counts.
6. Acquire or reuse a detached read-only backend inspection worktree at
   `858d2d7ffd620a7c28cdad5a75007536ccd5b391`, prove its exact head, and run the repository's
   `npm run contract:native:check` there; deployed revision remains independently unknown.

## Acceptance criteria

### AC-CONTRACT-02-01

- Given backend account-delete validation requires confirm and recent auth
- When the native contract bundle is generated
- Then the exact body and reauth failure shapes are asserted and the empty-body assumption fails

### AC-CONTRACT-02-02

- Given the Ask route emits SSE with role/content history
- When fixtures are generated and consumed
- Then event framing, terminal/error events, cancellation, and request history shape are executable

### AC-CONTRACT-02-03

- Given backend narration returns a raw plan with a type discriminator
- When the audio fixture is decoded
- Then the canonical envelope/discriminator mismatch is explicit and cannot pass through an invented alias

### AC-CONTRACT-02-04

- Given backend notebook collection semantics are inspected
- When mutation fixtures are checked
- Then note/highlight/bookmark capability and identifiers are classified without inventing CRUD support

### AC-CONTRACT-02-05

- Given the generator is run twice on the same exact revisions
- When outputs and manifests are compared
- Then bytes match and source/deployed provenance remains separate

## Lifecycle and adverse states

Cover malformed JSON/SSE, unknown enum values, optional fields, extra keys, expired auth, rate limits, cancellation, partial arrays only where safe, and unavailable backend checkout.

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
- **Domain:** Fixtures expose truth; they do not decide or implement the vertical transport.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Backend method/path/auth/validation/serializer/error/storage source at the recorded SHA is canonical static evidence.
- **Compatibility:** Only source-proven compatibility aliases may be represented; encoding remains canonical.
- **Migration:** No persistence migration.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Revert fixture/generator changes; no runtime contract is changed.

## Explicit non-goals and release boundary

- Production caller repair
- Backend deployment or probing
- Hand-authored authority fixtures without serializer/route provenance
- Treating backend main as deployed
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. python3 scripts/contracts/test_generate_ios_native_inventory.py.
2. python3 scripts/contracts/test_verify_ios_incremental_contract_drift.py.
3. swift test --package-path Packages/Models --parallel.
4. swift test --package-path Packages/Networking --parallel.
5. `git -C /private/tmp/ChapterFlow-wp-contract-02-inspect rev-parse HEAD` equals the declared backend
   source SHA.
6. `npm run contract:native:check` in that exact detached backend inspection worktree.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
