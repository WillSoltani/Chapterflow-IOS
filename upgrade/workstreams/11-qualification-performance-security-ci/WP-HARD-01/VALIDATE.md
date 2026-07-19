# Validate WP-HARD-01

Validation binds to one exact candidate commit. Record every command/evidence lane as `passed`,
`failed`, `skipped`, `blocked`, or `not run`; a lint result never substitutes for behavior.
A required selector passes only with `matched >= 1`, `failed = 0`, and `skipped = 0`; zero matching
selectors fail, and disabled or known-issue waivers are prohibited.

## Acceptance mapping

| Criterion | Assertion ID | Atomic assertion | Literal command | Named results artifact |
|---|---|---|---|---|
| AC-HARD-01-01 | HARD-01-PLAN-01 | The supported event/path matrix selects required lanes or an asserted safe skip reason. | `python3 -m unittest scripts.tests.test_ci_plan.CIPlanTests.test_supported_event_path_matrix` | `results/wp-hard-01/ac-hard-01-01-planner-matrix.txt` |
| AC-HARD-01-02 | HARD-02-SEC-01 | Fork and same-repository threat models retain least privilege with no unresolved high finding. | `python3 -m unittest scripts.tests.test_ci_checks.WorkflowSecurityTests.test_fork_and_same_repo_threat_models` | `results/wp-hard-01/ac-hard-01-02-threat-model.txt` |
| AC-HARD-01-03 | HARD-03-PIN-01 | Every retained action ref is immutable and checkout credential persistence is justified or disabled. | `python3 -m unittest scripts.tests.test_ci_checks.WorkflowSecurityTests.test_action_refs_and_credentials` | `results/wp-hard-01/ac-hard-01-03-action-pins.txt` |
| AC-HARD-01-04 | HARD-04-PROV-01 | Planner errors, cancellation, cache misses, and absent optional secrets preserve explicit failure or skip provenance. | `python3 -m unittest scripts.tests.test_ci_plan.CIPlanTests.test_required_failure_and_skip_provenance` | `results/wp-hard-01/ac-hard-01-04-failure-provenance.txt` |
## Required commands and evidence

1. `python3 -m unittest scripts.tests.test_ci_plan scripts.tests.test_ci_checks`.
2. `actionlint .github/workflows/pr-v2.yml .github/workflows/contract-drift.yml .github/workflows/pr.yml`.
3. `zizmor --offline --no-progress --color never --min-severity medium .github/workflows/pr-v2.yml .github/workflows/contract-drift.yml .github/workflows/pr.yml`.
4. repository secret/private-data scan and exact intended-path check.
5. `git diff --check <base>..<candidate>` and `git show --check <candidate>`.
6. independent exact-candidate differential/Git/CI review with P0/P1/P2 disposition.
7. read-only release-workflow audit with findings deferred; do not edit or dispatch release.

## Post-publication delivery evidence

After the four package ACs pass on the immutable commit, DELIVERY_POLICY verifies local/PR head
identity, required checks, check-name stability, absence of release dispatch, merge ancestry, and
post-merge `main` CI. This external lifecycle evidence cannot substitute for a package AC.

## Manual and GitHub evidence

Inspect fork and same-repository trust, merge queue, cancellation, planner error, cache miss/hit,
optional-secret absence, and check-name stability. Record a blocked external protection query as
`blocked` and do not merge; run all unaffected local tests.

## Failure semantics

- Any deterministic planner/actionlint/zizmor/required-check failure blocks the package.
- One exact retry is allowed only for a diagnosed transient with both results retained.
- Any changed candidate head invalidates validation and review.
- No threshold reduction, ignored high finding, permission broadening, coverage reduction, release
  dispatch, backend deployment, App Store/TestFlight action, or PR #117 mutation is permitted.
