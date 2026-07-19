# Run WP-LEARN-01

You are the sole implementation owner for **WP-LEARN-01 — Unify server-graded quiz and durable review mutations**. Complete this one package through its guarded development Git lifecycle, or stop with precise evidence. Do not implement another package.

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

1. Define one durable owner and stable identity for quiz/review submissions; migrate or quarantine the other path.
2. Keep correctness, pass, cooldown, unlock, FSRS scheduling, rewards, and progress server-authoritative.
3. Represent offline work as saved/pending grading, never a synthetic result, and require explicit replay where idempotency is unknown.
4. Reject stale attempts/results and repeated taps; refresh canonical progress/review state after accepted authority.
5. Provide accessible, localized quiz/review states across compact/iPad, AX text, offline, error, and resume.
6. Generate candidate-head real-locale/pseudo-long/RTL/VoiceOver/keyboard/contrast/motion evidence for quiz and review states.
7. Register/populate `EngagementFeature/Resources/Review.xcstrings` and prove quiz account A → sign
   out → account B cancellation, cache clearing, and durable-state isolation.

Establish deterministic red evidence first for confirmed defects when feasible. Edit only `package.json.ownership.allowedPaths`; stay within the time/file/root envelope. Stop and split/replan before scope, authorization, contract, migration, or lock expansion. Preserve server authority, account isolation, cancellation, accessibility, localization, privacy, and the release exclusion.

## Validate and review

Run pre-commit intended-path/secret checks and `git diff --check`, then create local candidate commit(s). Run every applicable command/evidence lane in `VALIDATE.md` on those immutable exact heads and classify each as `passed`, `failed`, `skipped`, `blocked`, or `not run`; compilation does not substitute for tests. Give an independent risk-proportionate reviewer the same exact candidate head(s). Resolve all P0/P1/P2 findings; every change creates a new head and reruns invalidated validation and review. One exact retry is allowed only for a diagnosed transient with both results retained.

## Publish, merge, and clean

Push each exact reviewed candidate head on one focused branch and open/update one focused PR per affected repository. Apply declared compatibility and merge order. Enable auto-merge only when every predicate in `package.json.mergePredicate` is true on every affected exact PR head. Monitor all GitHub-recorded merges and affected post-merge required CI; a backend source merge is not deployment. Cleanup only after every `cleanupPredicate` holds, including atomic-claim release by its recorded owner, using `git worktree remove` and deleting only package-owned merged branches. Never bypass protection or touch PR #117.

## Final handoff

Report outcome, exact revisions, diff/paths, contracts/migrations, AC evidence, commands/results, review findings, PR/checks/merge/post-merge status, device/runtime evidence, remaining risks, preservation fingerprints, cleanup, and the next ready package. Do not claim deployment or release readiness.
