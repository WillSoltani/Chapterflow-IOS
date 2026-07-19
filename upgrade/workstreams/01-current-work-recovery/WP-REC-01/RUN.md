# Run WP-REC-01

You are the sole implementation owner for **WP-REC-01 — Reconcile live work and install external evidence capture**. Complete this one package through its guarded development Git lifecycle, or stop with precise evidence. Do not implement another package.

## Required reads

1. Current user instruction and every applicable `AGENTS.md`.
2. `upgrade/README.md`, `upgrade/PROGRAM_CHARTER.md`, `upgrade/SKILLS.md`, `upgrade/DELIVERY_POLICY.md`, and `upgrade/VALIDATION_POLICY.md`.
3. This directory's `package.json`, `SPEC.md`, and `VALIDATE.md`.
4. Live source/tests/backend/CI and current official platform documentation for changed behavior.

## Start gate

- Reverify remote `main`, exact iOS/backend source/deployed evidence, open PRs, worktrees, primary-checkout fingerprint, and frozen PR #117.
- Confirm every `blockedBy`, owner-decision gate, write-set owner, interface contract, and resource lock from `package.json`.
- Revalidate each selected skill ID/path and read its complete current `SKILL.md` plus only the routed references. Missing/conflicting capability uses the recorded fallback; never fabricate it.
- As root scheduler, atomically claim `package-<ID>` and every declared resource lock under `program/resource-locks.json`; capacity locks claim one numbered slot. Stop `LOCKED` on collision. Then create or reuse exactly one package-owned isolated worktree/branch per affected repository declared in `package.json`, each from its verified base. Record every branch, worktree, start SHA, status, intended path set, unique DerivedData/SwiftPM scratch where applicable, and claim metadata.
- Stop `BLOCKED_USER_WORK` on overlap; never reset, clean, stash, overwrite, or copy owner work.

## Implement

1. Inventory live worktrees, branches, open PRs, heads, dirty paths, and live PIDs from supported sources.
2. Compare every candidate diff with verified remote main and classify it as merged, stale, novel, frozen, active, or unsafe-to-touch.
3. Record only evidence-backed successor package links; never copy or cherry-pick during recovery.
4. Re-fingerprint the dirty primary checkout and frozen PR #117 before and after the package.
5. Update the existing development execution status instead of creating a competing ledger.
6. Implement `scripts/validation/run_evidence.py` and its declared unit test. Accept repeatable
   `--repo-head repository=fullSHA`, canonicalize a sorted head-set digest, rewrite every relative
   `results/...` argument under the external root, capture command/output/exit/match/fail/skip and
   artifact digests, and fail on zero matches, missing artifacts, or repository-local results writes.
   Include deterministic `--classify-recovery-inventory` and `--check-exact-paths` modes so the
   recovery lane never expands prose such as “for each candidate” into ad hoc shell behavior. Also
   implement `--build-recovery-inventory` from the named worktree/PR/branch captures and
   `--compare-artifacts` with declared comparison schemas for owner status, owner diff digest, and PR
   #117. Attempt directories are exclusive and append-only; retries require `retryOf`/reason and keep
   both attempts. Matching simulator/device commands acquire and release the command-scoped lease,
   with same-owner parent-claim reentrancy and deterministic collision tests. Cross-row inputs use
   only `attempt://<attempt-id>/results/...`; verify same package/head-set manifests and digests and
   reject bare-result inputs, mutable aliases, ambiguity, path escape, or cross-head/package reads.

Establish deterministic red evidence first for confirmed defects when feasible. Edit only `package.json.ownership.allowedPaths`; stay within the time/file/root envelope. Stop and split/replan before scope, authorization, contract, migration, or lock expansion. Preserve server authority, account isolation, cancellation, accessibility, localization, privacy, and the release exclusion.

## Validate and review

Run pre-commit intended-path/secret checks and `git diff --check`, then create local candidate commit(s). Run every applicable command/evidence lane in `VALIDATE.md` on those immutable exact heads and classify each as `passed`, `failed`, `skipped`, `blocked`, or `not run`; compilation does not substitute for tests. Give an independent risk-proportionate reviewer the same exact candidate head(s). Resolve all P0/P1/P2 findings; every change creates a new head and reruns invalidated validation and review. One exact retry is allowed only for a diagnosed transient with both results retained.

## Publish, merge, and clean

Push each exact reviewed candidate head on one focused branch and open/update one focused PR per affected repository. Apply declared compatibility and merge order. Enable auto-merge only when every predicate in `package.json.mergePredicate` is true on every affected exact PR head. Monitor all GitHub-recorded merges and affected post-merge required CI; a backend source merge is not deployment. Cleanup only after every `cleanupPredicate` holds, including atomic-claim release by its recorded owner, using `git worktree remove` and deleting only package-owned merged branches. Never bypass protection or touch PR #117.

## Final handoff

Report outcome, exact revisions, diff/paths, contracts/migrations, AC evidence, commands/results, review findings, PR/checks/merge/post-merge status, device/runtime evidence, remaining risks, preservation fingerprints, cleanup, and the next ready package. Do not claim deployment or release readiness.
