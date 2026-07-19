# Validation Policy

## Evidence states

Every command/lane is reported exactly as `passed`, `failed`, `skipped`, `blocked`, or
`not run`, with exact revision, environment/toolchain, command, exit status, test/failure/skip
counts, and privacy-safe artifact. A build is not a test. Historical green evidence is not current
proof after a relevant diff.

## Validation sequence

1. Establish deterministic red evidence for a confirmed defect when feasible.
2. Run focused tests while implementing.
3. Freeze the final diff; verify intended paths, secrets/privacy, warnings/settings, and
   `git diff --check`, then create the local candidate commit.
4. Run the full package matrix from `VALIDATE.md` against that immutable exact candidate head.
5. Run affected dependent tests discovered from live manifests.
6. Run app build/UI/device lanes required by risk and changed behavior.
7. Obtain independent review of the same exact candidate commit.
8. Resolve every P0/P1/P2; any remediation creates a new head and reruns all invalidated gates/review.
9. Verify the exact PR head equals the validated/reviewed head and every applicable required GitHub
   check passes.
10. After merge, verify target ancestry/content and post-merge required CI.

Every AC has one or more atomic evidence rows with unique assertion IDs, literal commands/selectors,
expected oracles, and named privacy-safe `results/` artifacts. Multiple rows are required only when
one criterion needs independently executable repository or behavior proofs; no row may bundle
substitutable evidence. A required selector passes only with `matched >= 1`,
`failed = 0`, and `skipped = 0`; zero matches, disabled tests, or known-issue waivers fail closed.

Relative `results/...` names resolve under the external, package-owned
`CHAPTERFLOW_EVIDENCE_ROOT`, defaulting to
`/private/tmp/chapterflow-upgrade-results/<package-id>/<head-set-digest>/attempts/<attempt-id>/`.
The digest is SHA-256 of
the canonical sorted `repository=full-candidate-SHA` tuples, so coordinated iOS/backend evidence can
never be mislabeled by one head. This root is outside every
source worktree, is never committed, and is retained through
handoff, merge, post-merge verification, and any failure diagnosis. Record its absolute path and
artifact digests; cleanup follows the package evidence-retention disposition, not source-worktree
path ownership.

Every invocation supplies a unique stable attempt ID such as `attempt-01` or `retry-02`. The runner
creates that attempt directory with exclusive-create semantics and refuses an existing ID instead of
overwriting it. Its manifest records `attemptId`, optional `retryOf`, a required retry `reason`, the
head-set digest, assertion ID, owner, and retention disposition. Attempts are append-only: a retry
creates a sibling directory and retains both the original and retry manifests/artifacts.

A row that consumes an earlier row's artifact must use an immutable
`attempt://<attempt-id>/results/<path>` input reference, never a bare `results/...` input. The runner
resolves that reference only within the same package and head-set digest, verifies the referenced
attempt manifest and artifact digest, records both as inputs, and rejects a missing, ambiguous,
cross-package, cross-head, path-escaping, or output-position reference. Bare `results/...` remains an
output path under the current attempt. This makes dependencies explicit without a mutable “latest”
alias and permits retries to select the exact retained attempt they consume.

Execute each row's literal command through the WP-REC-01 standard wrapper:

```sh
python3 scripts/validation/run_evidence.py \
  --root "$CHAPTERFLOW_EVIDENCE_ROOT" \
  --package <PACKAGE_ID> \
  --assertion <ASSERTION_ID> \
  --attempt <ATTEMPT_ID> \
  --repo-head ios=<IOS_CANDIDATE_SHA> \
  --repo-head backend=<BACKEND_CANDIDATE_SHA_WHEN_APPLICABLE> \
  --cwd <PACKAGE_WORKTREE> \
  --artifact results/<declared-primary-artifact> \
  -- <declared command and selector>
```

The runner canonicalizes the repeatable repository/head set, preserves the declared command, executes it from the source worktree, rewrites every
`results/...` argument to the external root, captures stdout/stderr/exit status/match/failure/skip
counts and digests, and emits a manifest repeating every repository name/full head. It fails on
missing artifacts or any repository-local `results/` write. Tool-native artifacts such as
`.xcresult` remain required where declared; plain test/lint rows use the wrapper manifest plus
captured output as their named primary artifact. Use its
declared shell mode only for a row that explicitly contains a compound command. The wrapper is
execution infrastructure, not an alternate test or permission to change undeclared source paths.

Before any command matching a trigger in `program/resource-locks.json.commandScopedLeasing`, the
runner must atomically acquire the `simulator-device` capacity lease for that assertion attempt. A
same-owner package-level claim is reentrant and recorded as the parent claim. Missing or colliding
command-scoped leases fail `LOCKED` before execution. The wrapper releases an attempt lease in a `finally` path after
manifest finalization; it never releases another owner or a parent long-lived claim.

## Risk tiers

| Tier | Examples | Minimum independent evidence |
|---|---|---|
| R1 | Narrow pure logic or low-risk isolated UI | Owning tests, focused UI/render evidence if visible, independent reviewer. |
| R2 | State, navigation, networking reads, shared UI foundation | Owning + affected dependent tests, unsigned app build, targeted UI/accessibility evidence, independent reviewer. |
| R3 | Auth/account/entitlement, writes/sync, migration, security, backend contract, CI, device-only media/extensions | Deterministic tests across both sides of contract, dependent/full gates as declared, specialist differential/security review, exact-head CI, and required physical-device evidence. |

## Standard command shapes

Use the current workflow and package manifest as authority.

```sh
swift test --package-path Packages/<PackageName> --parallel
```

```sh
xcodebuild build \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

```sh
xcodebuild test \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination 'platform=iOS Simulator,id=<BOOTED_SIMULATOR_UDID>' \
  -only-testing:ChapterFlowUITests \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

```sh
swiftlint lint --strict --reporter github-actions-logging
swiftformat --lint .
git diff --check
```

Use `set -o pipefail` for piped commands. Use unique package-owned DerivedData and SwiftPM scratch
paths during concurrent work. Do not run broad auto-fix as validation.

## Native evidence

- `scripts/visual/native-matrix.json` is the executable scenario authority. Every changed visible
  package must select Light, Dark, compact iPhone, regular iPad, accessibility Dynamic Type,
  VoiceOver semantics, increased contrast/non-color status, Reduce Motion, Reduce Transparency, one
  real non-English locale, pseudo-long text, RTL, and keyboard/pointer when applicable. The runner
  fails if a required dimension is absent and records catalog/table/key plus a non-English value
  digest; changing only the launch locale is not localization evidence.
- Deterministic visual tests bind data, locale, clock, animation, appearance, dimensions, runtime,
  and revision. Pixel comparisons cover stable content only.
- Light/Dark, compact iPhone, regular-width iPad, accessibility Dynamic Type, long/pseudo text, and
  RTL are mandatory for changed visible flows.
- Accessibility evidence covers VoiceOver names/values/traits/order/focus/announcements, contrast,
  non-color status, Reduce Motion/Transparency, and default 44-point controls or documented
  current-HIG exceptions.
- XcodeBuildMCP/simulator screenshots supplement, not replace, assertions.
- XCUITest and unit assertions may prove exposed names, values, traits, geometry, and deterministic
  focus targets, but not actual spoken order/announcements. Final qualification therefore includes
  an Accessibility Inspector plus physical-device VoiceOver central-journey scenario with OS/device
  class, operator gestures, expected/observed focus order and announcements, and a privacy-safe
  report. Missing actual VoiceOver proof is `blocked`, never inferred from semantic unit tests.

## Physical-device boundary

Physical-device proof is required when Simulator cannot prove signed Keychain/access groups, SIWA,
APNs, widgets/Live Activities, extensions/App Groups, background audio/interruption/routes,
background transfer, memory/energy, or real network transitions. Record model class, OS,
configuration, exact revision, steps, and outcome without device IDs or personal/private data.
A missing required device/credential is `blocked`, not `skipped` and not completion.

## Flake and retry policy

- Diagnose; never blind-rerun.
- One exact retry is allowed only for a diagnosed transient. It uses a new attempt ID, declares
  `retryOf` and a privacy-safe reason, and must retain both append-only attempts.
- Attempt-ID collision, missing retry metadata, or any overwrite is a deterministic runner failure.
- If the same blocker/failure repeats twice without new evidence, stop that route and use
  [RECOVERY_AND_RESUME.md](prompts/RECOVERY_AND_RESUME.md).
- No `XCTSkip`, expected failure, retry wrapper, tolerance, threshold, warning suppression, or
  coverage reduction merely to obtain green.

## Review finding adjudication

Reviewers report impact, likelihood, evidence, and severity. Root deduplicates only identical
finding/root-cause/remediation pairs, retains co-located distinct issues, and resolves conflicting
severity from evidence rather than voting. Any unresolved P0, P1, or P2 blocks publication.

## Plan validation

Before this plan or any material revision is published:

1. parse all JSON;
2. run `python3 upgrade/scripts/validate_upgrade_plan.py`;
3. run prompt static analysis and semantic eval cases;
4. validate DAG cycles, inverse blocks, locks, paths, and internal links;
5. run up to three distinct independent reviews;
6. run `git diff --check`;
7. confirm the diff is exactly `upgrade/**`.
