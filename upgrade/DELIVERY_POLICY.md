# Development Delivery Policy

## Authority and boundaries

The owner authorizes package-owned isolated worktrees/branches, declared source edits, local commits,
focused pushes/PRs, guarded auto-merge, and safe post-merge cleanup. This does not authorize branch
protection bypass, force-push, deployment, infrastructure/data mutation, external configuration,
App Store/TestFlight/release/signing work, production flags, or any PR #117/frozen-branch mutation.

## Start predicate

Before an editor starts:

1. verify current remote target, exact base, open PRs, required checks, live instructions, backend
   source/deployed evidence, and protected-checkout fingerprints;
2. prove every dependency is merged or declare an exact stacked dependency;
3. resolve owner-decision gates;
4. create/reuse exactly one package branch and isolated worktree per affected repository declared in
   package metadata;
5. as the root scheduler, atomically claim `package-<ID>` and every declared resource lock
   under the protocol in `program/resource-locks.json`; a capacity lock claims one numbered slot;
   stop `LOCKED` on any collision;
6. record start SHA, worktree, branch, status, paths, toolchain, unique DerivedData/scratch, and
   rollback;
7. stop on any user-work or active-lane overlap.

Maximum two concurrent editors, with disjoint write sets, disjoint atomic claims, and no common
high-contention lock. If atomic claims are unavailable or hosts differ, use one editor. Simulator/
device capacity and Xcode-project changes are serialized. The standard evidence wrapper acquires the
command-scoped `simulator-device` lease before every matching assertion attempt, reuses a same-owner
declared package claim, fails `LOCKED` before unleased execution, and releases only its attempt lease
in a `finally` path.

## Local completion predicate

- Acceptance criteria and invariants pass on the final candidate diff.
- Required focused/dependent/build/UI/device/security/performance lanes are fresh.
- The candidate is committed locally, and independent risk-proportionate review inspects that exact
  immutable commit head. Any remediation creates a new head and invalidates affected gates/review.
- No unresolved P0/P1/P2 exists.
- Diff contains only declared paths; no secret/private evidence or undeclared contract/migration.
- `git diff --check` passes.
- The reviewed head/tree equals the candidate that passed validation; no post-review amend exists.

## Publication and automatic merge

Push one focused branch and open/update one focused PR per affected repository. A coordinated
iOS/backend package must record both exact heads, compatibility/merge order, and rollback; a backend
source merge is never deployment. Enable auto-merge only when, on every affected exact PR head:

1. every AC/invariant passes;
2. every required local lane passes;
3. independent review has no unresolved P0/P1/P2;
4. every applicable required GitHub check concludes successfully;
5. PR is mergeable/conflict-free and satisfies branch protection/review;
6. base/head drift is reconciled and invalidated gates rerun;
7. no undeclared path, dependency, migration, contract, or generated artifact exists;
8. backend source/deployed/rollout state is truthful;
9. no owner/device/credential/external/release blocker remains for the package;
10. PR/branch is not #117/`codex/wp-rel-01`.

Green CI alone is insufficient. Never use admin merge, protection bypass, test weakening, or a blind
retry. After auto-merge is enabled, monitor until GitHub records merge or a blocker.

## Post-merge verification

- Record PR, reviewed head, merge SHA, final target SHA, required CI run/checks.
- Verify target ancestry/tree contains the reviewed change.
- Verify required post-merge `main` CI is green.
- Re-open package entrypoints from target and check no stale branch/stack dependency remains.
- If post-merge CI fails, retain evidence/worktree, diagnose through recovery, and do not
  automatically revert without a new authorized package.

## Safe cleanup

Only after merge and post-merge success:

1. run `lsof +D <worktree>` or equivalent and verify no PID has a working directory/open file;
2. verify clean worktree and no unmerged commit;
3. remove with `git worktree remove`, never `rm -rf`;
4. delete the merged local branch;
5. delete the package-owned remote branch only when no stack depends on it;
6. prune only stale package-owned worktree metadata;
7. reverify worktree list, branch state, target ancestry, and primary-checkout fingerprint.

Never delete another task's worktree, branch, cache, evidence, or uncommitted files.

## Recovery/anti-spin

- Material checkpoint at each stage and no silent work period over 60 seconds.
- One bounded status request after 20 minutes without material evidence.
- Interrupt/reassign only untouched disjoint work; never run two writers on the same files.
- Maximum two remediation rounds; one exact transient retry only after diagnosis.
- Same blocker/failure twice without new evidence routes to
  [RECOVERY_AND_RESUME.md](prompts/RECOVERY_AND_RESUME.md).
- Scope expansion, contract conflict, decision, credential/device/authority need, user-work
  collision, or required-test weakening stops truthfully.
- A qualification defect may reopen only its existing non-superseded owner package through the root
  scheduler's immutable external evidence record. Reopening invalidates prior integration and every
  named downstream gate; it never grants new paths, roots, locks, contracts, migrations, or authority.
