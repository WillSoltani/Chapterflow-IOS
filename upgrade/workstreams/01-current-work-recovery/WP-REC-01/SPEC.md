# WP-REC-01 — Reconcile live work and install external evidence capture

## Problem and verified root cause

Historical status text and branch names no longer distinguish merged, stale, novel, frozen, dirty-owner, or actively used work. Current main already contains many formerly planned slices, while unrelated worktrees remain protected.

Evidence is static at iOS `22da44d27bc18771f4d7db7681e17c10970ccb13` and backend source `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; deployed backend remains unknown. Revalidate every anchor on the lane's exact base before editing.

## Functional and non-functional requirements

1. Inventory live worktrees, branches, open PRs, heads, dirty paths, and live PIDs from supported sources.
2. Compare every candidate diff with verified remote main and classify it as merged, stale, novel, frozen, active, or unsafe-to-touch.
3. Record only evidence-backed successor package links; never copy or cherry-pick during recovery.
4. Re-fingerprint the dirty primary checkout and frozen PR #117 before and after the package.
5. Update the existing development execution status instead of creating a competing ledger.
6. Add the standard evidence runner that executes declared commands in the source worktree while
   resolving every relative `results/...` output into a unique external evidence root and proving no
   repository-local results were written.
7. Build the normalized recovery inventory deterministically from named worktree, PR, and branch
   captures, and emit explicit equality comparators for protected before/after fingerprints and PR
   #117 rather than relying on prose or operator judgment.
8. Store every assertion attempt append-only under its own exclusive attempt ID; a retry links to and
   retains the original, and command-scoped simulator/device consumers cannot run without a lease.
9. Resolve every cross-row recovery input through an explicit same-package/head-set
   `attempt://<attempt-id>/results/...` reference with referenced-manifest and artifact-digest proof;
   there is no mutable latest-attempt alias.

## Acceptance criteria

### AC-REC-01-01

- Given the verified remote main and protected fingerprints are recorded
- When the recovery inventory is recomputed
- Then every observed worktree, branch, and PR has one evidence-backed disposition and exact head

### AC-REC-01-02

- Given an active or dirty worktree is encountered
- When its novelty cannot be proven safely
- Then it is marked unsafe-to-touch and no cleanup/extraction occurs

### AC-REC-01-03

- Given a historical package claim is already present on main
- When its old branch or plan is evaluated
- Then it is marked superseded with the integrating commit rather than scheduled again

### AC-REC-01-04

- Given PR #117 or codex/wp-rel-01 appears in the inventory
- When the package completes
- Then the item remains frozen and no GitHub or Git mutation targets it

### AC-REC-01-05

- Given the final recovery report is reviewed
- When the exact diff and fingerprints are checked
- Then the diff contains exactly the existing status document, standard evidence runner, and its unit
  test while owner state is byte-for-byte preserved

### AC-REC-01-06

- Given a declared validation command, candidate SHA, package ID, and external evidence root
- When the standard evidence runner executes it from the source worktree
- Then every `results/...` argument is rewritten externally, output/counts/digests are captured, and a repository-local results write fails

## Lifecycle and adverse states

Handle stale local main, blocked worktree-list tooling, active PIDs, untracked guidance, branch-name collisions, interrupted inventories, and head drift. Unknown state is unsafe, not clean.

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
- **Domain:** Recovery is read-only until the final status-document edit; it never grants ownership of product files.

## Contract, compatibility, migration, rollout, and rollback

- **Verified contract:** Git object ancestry, canonical diffs, GitHub PR metadata, working-tree state, and PID/open-file checks are the contract.
- **Compatibility:** No source or schema compatibility change.
- **Migration:** No migration.
- **Rollout:** Merge source only after exact-head gates. Backend deployment and external configuration remain unauthorized and separately evidenced.
- **Rollback:** Revert the three-file status/runner/test commit; no owner worktree or branch is mutated.

## Explicit non-goals and release boundary

- Product implementation
- Cleanup of any active/unowned worktree
- PR #117 mutation
- Creating a new mutable orchestration ledger
- App Store, TestFlight, production deployment, signing/release action, and PR #117 mutation.

## Test plan

1. git status --short and git diff --check.
2. git log --oneline --decorate -25.
3. supported worktree inventory plus PID/open-file checks.
4. GitHub open-PR and exact-head query.
5. primary-checkout fingerprint comparison.
6. evidence-runner unit tests for path rewriting, command failure, zero matches, artifact absence, and repository-local write rejection.
7. inventory builder and exact-comparison tests, including malformed/truncated input rejection.
8. append-only attempt collision, retry retention/metadata, immutable cross-attempt reference, and
   command-scoped lease lifecycle tests.

## Definition of done

All acceptance criteria and applicable invariants map to fresh evidence in [VALIDATE.md](VALIDATE.md); required local lanes and independent final-diff review pass on the same head; the focused PR satisfies branch protection and required CI; merge and post-merge verification succeed; only then may package-owned clean resources be removed. A blocked decision, device, credential, deployed revision, test, or P0/P1/P2 finding remains a blocker, never a completion claim.
