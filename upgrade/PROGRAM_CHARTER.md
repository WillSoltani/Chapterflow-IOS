# ChapterFlow Upgrade Program Charter

## Mission

Complete the native iOS learning loop on verified current `main`:

```text
Discover → Book Detail → Start or Continue → Read or Listen
→ Note, Highlight, Bookmark, or Ask → Quiz or Review
→ Durable Progress → Exact Resume
```

The outcome is a calm, editorial, content-first iOS product whose correctness, accessibility,
reliability, privacy, and performance are demonstrated on the exact revision being integrated.
The program is development work, not a release program.

## Controlling authority

At every lane start, read the current user instruction, the root and nested `AGENTS.md` files,
this charter, the selected package, and live repository evidence. Current code, tests, backend
routes/serializers/storage, CI, and official Apple documentation outrank historical plan text.
Backend source and deployed backend evidence are always recorded separately.

## In scope

- iOS and, only where a verified contract requires it, additive backend source work in separate
  repository-owned branches and worktrees.
- Product-loop correctness, contract repair, account isolation, offline truth, native UI,
  accessibility, localization, iPhone/iPad adaptation, deterministic validation, observability,
  performance, security, CI, and development device proof.
- Focused commits, PRs, exact-head CI, guarded auto-merge, and safe package-owned cleanup under the
  authority restated in [DELIVERY_POLICY.md](DELIVERY_POLICY.md).

## Explicitly out of scope

- Backend deployment, infrastructure mutation, data seeding/migration, production probes without
  specific authority, and external service configuration.
- App Store Connect, TestFlight, release signing/certificates/profiles, pricing, purchases,
  submission, release evidence, or release attestation.
- Any mutation or continuation of PR #117 or `codex/wp-rel-01`.
- Broad rewrites, duplicated state owners, invented contracts, hidden test skips, or plan-control
  ledgers unrelated to product evidence.

## Program principles

1. Revalidate before editing; a historical finding is only a lead.
2. One vertical outcome, one owner lane, one focused PR per affected repository, and one coordinated safe rollback unit.
3. Server authority fails closed for identity, account state, entitlements, unlocks, grading,
   rewards, and moderation.
4. Private durable data is explicitly account-scoped; ownerless data is quarantined until policy
   is approved.
5. Native UI and accessibility are acceptance criteria in every visible package.
6. Deterministic red proof is preferred before a confirmed fix; compilation is never a test.
7. Two editors maximum, only with disjoint write sets and no shared lock.
8. Every completion claim is bound to the exact reviewed head and fresh evidence.
9. Unknown deployed behavior remains `blocked-evidence`; a source merge is not deployment.
10. Fewer artifacts are preferred when they preserve the same safety and evidence.

## Completion milestones

| Milestone | Meaning | Required evidence |
|---|---|---|
| Feature complete | Every declared in-scope control and central-loop transition is wired, truthful, and covered for applicable lifecycle/adverse states. | Package acceptance criteria, focused tests, central-loop integration tests, no visible dead control. |
| Development-quality complete | Architecture, contracts, account isolation, migrations, accessibility, localization, offline behavior, security, performance budgets, CI, and maintainability meet [COMPLETION_RUBRIC.md](COMPLETION_RUBRIC.md). | Exact-head package and dependent tests, app build, lint/static checks, independent final-diff review, required CI. |
| Device validated | Simulator-insufficient behaviors are demonstrated on approved physical devices and a nonproduction environment without personal data in evidence. | Signed-device matrix for Keychain, SIWA, APNs, extensions/widgets, audio/interruption/background, memory, and real network transitions. |
| Release ready — deferred | Release configuration, production deployment, TestFlight, App Store submission, and release evidence are separately authorized and complete. | Not part of this program; no package may claim it. |

## Owner-decision register

| Decision | Why it cannot be safely inferred | Blocks | Recommended default |
|---|---|---|---|
| `D-IA-01` top-level information architecture | Five tabs, duplicated Home/Library/Discover affordances, and an unwired richer Discover surface create multiple reasonable structures. | `WP-SHELL-02` | Preserve current tabs until a short evidence-backed IA choice is approved; fix dead/blank states without pre-empting it. |
| `D-DATA-01` ownerless legacy private data | Assigning, deleting, or exposing legacy rows/outbox items can lose data or cross accounts. | `WP-EXT-01` | Retain/quarantine; never assign to the current account or report success. |
| `D-SURFACE-01` unsupported social/moderation and journey/event surfaces | iOS declares backend-TODO safety routes and some deep links fall back to Home. Completing backend scope and removing/hiding unsupported UI have different product consequences. | `WP-ENGAGE-01`, `WP-SOCIAL-01` | Hide or disable unsupported production entry points truthfully until a coordinated contract is approved. |
| `D-LOCK-01` App Lock product policy | Settings exposes App Lock but production enforcement is absent; threat model, recovery, and timeout behavior are product/security policy. | `WP-ACCOUNT-02` | Remove or label unavailable unless a complete enforcement and recovery policy is approved. |
| `D-ANNOTATION-01` annotation durability and sync authority | Notes, highlights, and bookmarks exist locally while the canonical notebook/write contract is incomplete; silently choosing local-only, destructive migration, or cross-device sync changes user expectations and data ownership. | `WP-ANNOTATE-01` | Preserve and quarantine existing durable data; do not claim cross-device sync or remove a control until the owner selects a source-derived additive contract or an explicitly local-only product policy. |

External signing, Cognito/Apple provider configuration, credentials, backend deployment, and
physical-device access are authority/evidence gates, not product decisions.

## Change discipline

Package metadata owns allowed paths and interfaces. If the final implementation needs more than 20
files, more than three primary roots, another high-contention lock, an undeclared backend change,
or a materially different outcome, stop and split/replan before editing. Do not move a TODO or add a
fake path and call the package complete.

`primaryRoots` counts production implementation roots. A package may additionally declare one
`validationSupportRoots` entry only for its exact file under the NATIVE-created
`ChapterFlowUITests/UpgradeEvidence` group. That file still counts toward `maxFiles`, has one owner,
and participates in collision checks; broad UI-test globs and later `project.pbxproj` edits are
forbidden. This exception cannot be used for production source, shared fixtures, or another test root.

For the reviewed NATIVE/EXT/READER ownership revision, `estimate.rootAccounting` is mandatory and
machine-validated. It preserves every ordered `(repo, glob)` claim exactly once, rejects malformed
repositories, traversal, noncanonical paths, catch-alls, duplicate assignments, and broad validation
support, and assigns each claim to a named primary group or an exact reviewed non-primary class. Its
planned-file allocations must sum exactly to `plannedFiles`. WP-NATIVE-01 additionally binds its
parked immutable candidate base, head, tree, canonical binary-diff digest, and sorted exact path
manifest with a mandatory `known-red-scope-only-not-runtime-approved` disposition; the binding proves
scope and identity only, never runtime correctness or approval. The validator's `--package-diff` mode
verifies those paths against each group allocation and the unchanged file/root maxima. A primary group normally resolves to one filesystem implementation
root. The sole approved multi-directory group is WP-EXT-01's `extension-transaction-boundary`, containing exactly
`SharedExtensionKit/**`, `ShareExtension/ShareViewController.swift`, and
`ActionExtension/ActionViewController.swift`. Those controllers are thin production adapters for
the same result-bearing durable-capture contract; this grouping grants no ownership of either
extension view, catalog, or another target file. The validator rejects every other cross-root group,
unclassified path, duplicate assignment, catch-all, candidate drift, or file-allocation mismatch. This is a bounded
reconsolidation inside WP-EXT-01's unchanged three-root and twenty-file maxima, not a general root
exception or permission to widen another package.

The paired performance manifest is also fail closed. Every reviewed budget entry has a canonical
semantic fingerprint; source-backed numeric ceilings may not relax, and Reader/Graph paired budgets
carry distinct structured order, sample, device-class, trace-template, and fixture joins. The
NATIVE-owned runner exposes one canonical worktree-and-expected-HEAD interface and must self-test the
complete Reader and Graph consumer plans. Missing, duplicate, legacy, cross-wired, candidate-first,
or semantically changed inputs fail before measurement. A fingerprint update is itself a reviewed
planning revision, including when a later lane proposes a tighter budget.

## Qualification remediation lifecycle

Package source metadata is immutable planning intent; live state is derived from Git and evidence as
`planned`, `active`, `integrated`, `reopened`, `verified-complete`, `superseded`, or `blocked`. A
JOURNEY/DEVICE defect never creates an anonymous repair lane. The root scheduler writes one immutable
external `reopen.json` under the configured evidence root, naming the stable package ID, exact failing
candidate head set, finding and artifact anchors, declared-versus-observed scope, invalidated gates,
owner/lock disposition, and observation time. Package lanes cannot edit `upgrade/**` or that record.

A valid record reopens the same package and invalidates its prior integration proof plus every affected
downstream JOURNEY/DEVICE gate. The package may change only its original envelope. Extra paths, roots,
locks, contracts, migrations, authorization, or a materially different outcome require the ordinary
split/replan and reviewed plan-revision path before any edit. Once the remediated package integrates,
the scheduler reruns every named invalidated gate on the new exact head set. Superseded packages are
never reopened.

## Package-count hard cap and consolidation test

The program uses a **24-package hard cap**. Independent review required separate onboarding and
paywall packages because their authority, validation, and rollback differ; the count remains capped by
consolidating Home/Library/Search with Discover/Book Detail into one LibraryFeature catalog-to-detail
vertical. Concept Graph and final signed-device/performance qualification remain separate because they
have distinct write roots and evidence environments. Further consolidation would exceed the
120-minute/20-file envelope or mix simulator, physical-device, backend-authority, and feature outcomes
that invalidate at different heads. No additional package may be added unless an existing package is
consolidated without weakening ownership, evidence, or rollback, or the charter and full review are
explicitly revised.

`WP-DEVICE-01` is the transparent qualification-only exception to the default focused-work estimate:
it discloses 390 total minutes across four independently resumable authorization domains, each capped
at 120 uninterrupted minutes. One evidence owner prevents competing device writers and candidate
drift; each sublane has an independent checkpoint/block state, unaffected sublanes continue, and the
package completes only when every criterion passes. This is not a hidden 120-minute total estimate.

## Terminal semantics

A merged package is not deployed and does not make the app release ready. The program reaches
development-quality completion only when all in-scope packages are merged or truthfully superseded,
every blocked decision/evidence item is resolved or explicitly deferred without a live false
surface, and the exact final `main` revision passes the program gates. Release remains deferred.
