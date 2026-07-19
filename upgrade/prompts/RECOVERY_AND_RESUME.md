# Recovery and Resume

Use after interruption, head drift, diagnosed transient, stalled lane, failed validation, failed
post-merge CI, or repeated blocker. This prompt repairs evidence/state; it does not weaken a gate.

## Input

```text
PACKAGE_PATH=
LAST_VERIFIED_BASE=
LAST_VERIFIED_HEAD=
LAST_DIFF_DIGEST=
FAILED_OR_BLOCKED_STAGE=
EVIDENCE_PATHS=
```

## Recovery protocol

1. Re-read current user/instructions, `LANE_RUNNER.md`, `VALIDATION_POLICY.md`,
   `DELIVERY_POLICY.md`, program/package, and live repository/GitHub state.
2. Verify whether worktree, branch, base/head, diff, dependencies, decisions, atomic claim metadata,
   locks, toolchain,
   required checks, and protected fingerprints still match the checkpoint.
3. Preserve every log/result and classify the interruption:
   `transient`, `deterministic-failure`, `head-drift`, `scope-drift`, `user-work-collision`,
   `owner-decision`, `evidence/credential/device/authority`, or `unknown`.
4. Reuse a stage only when its exact base/head/diff/command/toolchain/environment and required
   artifacts still match. Rerun every invalidated stage.
5. One exact retry is permitted only for a diagnosed transient. If the same condition repeats twice
   without new evidence, stop that route.
6. If a lane stalled 20 minutes without material evidence, request one bounded handoff, then
   interrupt. Reassign only untouched disjoint work; never add a concurrent writer.
7. If a PR head drifted, disable merge, reconcile safely, refreeze, re-review, and rerun invalidated
   local/CI gates. If post-merge CI failed, retain the worktree/branch evidence and diagnose; do not
   auto-revert.
8. Never reset/clean/stash/overwrite owner work, delete active worktrees, alter PR #117, relax tests,
   or expand into deployment/release.
9. If exact JOURNEY/DEVICE evidence identifies an owner-package defect, the root scheduler writes the
   immutable external `reopen.json` defined by `program/backlog.json`. Reopen the same package ID,
   invalidate its integration proof and named downstream gates, and preserve the original envelope;
   otherwise stop for split/replan. Package lanes never mutate `upgrade/**` or that record.

## Recovery evidence ledger

Retain and reissue every applicable mandatory ledger item from `LANE_RUNNER.md`. At minimum record
checkpoint base/head/diff/stage, preserved failing command/output, diagnosis and environment, both
attempts for a transient retry, protected fingerprints/owners/locks, and an explicit reusable-versus-
invalidated disposition for every gate. If cleanup or post-merge recovery is involved, also record
PID/open-file/clean/ancestry checks and final worktree/branch state. Missing evidence remains blocked.

## Output format

```markdown
## Classification
## Verified current state
## Preserved evidence
## Invalidated and reusable gates
## Smallest safe next action
## Blocker and required authority
```

Only resume the implementation lane when the smallest safe next action is within the same package,
write set, authority, and lock contract.
