# Expected Prompt Behaviors

All 20 cases in [prompt-cases.json](prompt-cases.json) are critical. A pass requires the expected outcome and every artifact assertion; a marker mention alone is insufficient.

## Universal semantics

- Reverify live instructions, remote base, protected owner state, frozen PR #117, backend source/deployed provenance, package dependencies/decisions/paths/locks, and exact head before mutation.
- Preserve user work; unknown ownership fails closed.
- One package and one writer; exactly one branch/worktree/focused PR per affected repository; at most two disjoint editors program-wide.
- Deterministic failures block; one diagnosed transient may receive one exact retained retry.
- Contract/authority/deployed evidence is never invented; product decisions and external authority stop explicitly.
- Review findings are evidence-adjudicated; unresolved P0/P1/P2 blocks even with green CI.
- Merge requires one exact head across acceptance, local validation, review, required checks, protection, and authority.
- Cleanup begins only after GitHub-recorded merge and post-merge success, and only for clean inactive package-owned resources.
- Backend source integration is not deployment. Release/App Store/TestFlight/signing remains excluded.

## Evaluation method

1. Freeze prompt sources by SHA-256.
2. Run the bundled static prompt analyzer for structure/clarity signals.
3. Evaluate each case against prompt behavior and referenced policies with a named evaluator and evidence anchor.
4. Revise only one supported failure cluster at a time; never relax expected behavior.
5. Rerun every case and independent reviewers after the final prompt diff.

Static semantic evaluation proves instruction coverage, not that an implementation agent will behave correctly. Package evidence, independent review, tests, GitHub checks, and runtime/device validation remain the real gates.
