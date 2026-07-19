# Validate WP-<DOMAIN>-<NN>

Record every command or scenario as `passed`, `failed`, `skipped`, `blocked`, or `not run`. A required
selector passes only with `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching selectors,
disabled tests, and known-issue waivers fail closed.

## Acceptance mapping

| AC | Assertion ID | Exact command and selector | Expected oracle | Required artifact |
|---|---|---|---|---|
| AC-... | DOMAIN-NN-KIND-NN | `exact command/selector` | one atomic behavior oracle | `results/<package>/<artifact>` with exact head and counts |

## Required lanes

List exact owning/dependent tests, build, UI, visual/accessibility/localization, security/privacy,
performance, device, review, intended-path/secret, `git diff --check`, and exact-head GitHub gates.
Bind every result to the immutable candidate commit created before final validation and review.

## Failure semantics

No blind retry, expected failure, skip, waiver, threshold/coverage weakening, or compilation-as-test.
One exact retry only for a diagnosed transient. Unresolved P0/P1/P2, missing required evidence, or
head drift blocks merge.
