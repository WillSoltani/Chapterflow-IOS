# Current State at Planning Cutoff

Observation cutoff: 2026-07-18, America/Halifax.

## Revision and proof boundary

| Scope | Revision/state | Evidence type |
|---|---|---|
| iOS remote `main` | `22da44d27bc18771f4d7db7681e17c10970ccb13` | GitHub connector plus matching local `HEAD` and cached `origin/main` |
| Backend remote `main` / source baseline | `858d2d7ffd620a7c28cdad5a75007536ccd5b391` | GitHub connector plus matching cached `origin/main`; static source authority only |
| Protected backend checkout | branch `update`, HEAD `04e0ae50b4c1f1722b33a6501e03b79bc8894112`, with untracked prompt/`upgrade/` work | Local preservation evidence; not the program source baseline and never mutated here |
| Backend deployed revision/environment | Unknown | `blocked-evidence`; never infer from source or merge state |
| Frozen release PR | #117, draft/open, head `7bb9b5a88494027832cfe1553cc3c6c464702ab6` | GitHub connector, read-only |
| Planning runtime | Detached clean base before `upgrade/`; local branch creation rejected by policy hook | Local Git/tool evidence |

The codebase contains 19 Swift packages and seven native targets. The app host is thin; `AppFeature`
owns composition and session scope. Package tests and historical exact-head CI are useful evidence,
but no full build, simulator journey, signed device, VoiceOver session, or deployed-backend probe was
run during this plan-only task.

## State model

### Verified complete on current source

These old-plan leads are superseded by integrated work on current `main`, subject to fresh
package validation when their code is touched:

- deterministic development bootstrap, typed privacy-safe observations, and required CI v2;
- authoritative Cognito session identity and account-scoped dependency lifetime;
- stable tab models and exact book/chapter route replay;
- fail-closed read/book-state errors and delete-only-when-applied sync behavior;
- server-bound entitlement verification and explicit offline quiz-draft submission;
- centralized local annotation sync and backend artwork loading/caching;
- public guest facade and account-isolated private persistence boundaries.

Evidence anchors include `AppModel.swift`, `SessionScope.swift`, `AccountPersistence.swift`,
`Endpoint+Reliability.swift`, `SyncEngine`, `LiveQuizRepository.swift`,
`LiveAnnotationRepository.swift`, current tests, and commits `7f7031b` through `22da44d`.

### Partial

- Discover, Home, Library, Book Detail, Search, Reader, Quiz, Reviews, Ask, Audio, Downloads,
  Notifications, Widgets, extensions, engagement, social, auth, and settings have substantial
  implementation and tests, but the complete product loop is not composed or runtime-proven.
- `ReadingFlowView.wireQuizCTA()` wires quiz only; listen, Ask/selection, reflection, preferences,
  chapter transitions, loop completion, progress refresh, and exact durable resume are not composed.
- Account scope preserves ownerless extension/outbox data, but does not attribute, transactionally
  import, persist, and clear it.
- Dynamic Type tokens and local Reduce Motion handling exist, but feature-level adaptation,
  focus/announcement behavior, contrast modes, and non-color differentiation are incomplete.
- CI v2 is authoritative and risk-selective; current workflow security/efficiency must be audited
  before any workflow change rather than assumed complete. At the planning cutoff,
  `actionlint .github/workflows/pr-v2.yml` passes. An offline `zizmor` audit still reports unpinned
  actions in contract-drift, legacy fallback, and release workflows, plus legacy/release permission
  and cache findings; the manual legacy workflow also has two informational shellcheck findings.
  These are current-source inputs to `WP-HARD-01`, not plan-validation success or release work.

### Missing

- Trustworthy visual regression: stored gallery artifacts contain a prohibited placeholder and
  iOS-simulator snapshot helpers do not compare pixels.
- A real localization proof lane: project localizations are English/Base and feature copy is largely
  literal; pseudo-localization/RTL guards are not semantic proof.
- Regular-width/iPad adaptation for most shell, catalog, auth, quiz, engagement, AI, paywall, and
  settings surfaces.
- Equivalent accessible interaction for the pan/pinch Concept Graph.
- Exact central-loop XCUITest/Maestro coverage through durable resume.
- Signed-device proof for Keychain groups, SIWA, APNs, widgets/extensions, audio interruptions,
  background behavior, memory, and real network transitions.

### Broken or incompatible

| Finding | Current source evidence | Required disposition |
|---|---|---|
| `F-CONTRACT-DELETE` account delete | iOS sends an empty body; backend requires `{confirm:"DELETE"}` plus recent auth. | Coordinate exact contract and a production-completable reauth path; fail closed. |
| `F-KEYCHAIN-GROUP` signed Keychain configuration | Main entitlement lacks the declared access group while token queries use `group.com.chapterflow`; extensions declare a prefixed group. | Inspect compiled entitlements, correct configuration, and prove on signed device. |
| `F-CONTRACT-ASK` Ask | iOS expects JSON/history question-answer shape; backend accepts role/content and emits SSE. | Pick the verified canonical transport, add fixtures/evolution tests, coordinate rollout. |
| `F-CONTRACT-AUDIO` narration plan | iOS expects an envelope and segment `kind`; backend returns raw plan and `type`. | Align additively or add a verified compatibility adapter. |
| `F-CONTRACT-NOTEBOOK` annotations | iOS generic note/bookmark/highlight CRUD differs from backend highlight-centric collection contract. | Define canonical ownership and compatibility before mutation. |
| `F-BE-ACCOUNT-GUARD` backend account status | Backend source allows requests on status-store failure outside a short deleted-account cache. | Backend source fix must fail closed; deployment remains separately unauthorized. |
| `F-UI-NESTED` catalog/search controls | Save/remove buttons are nested in row buttons. | Separate interactions and verify touch/VoiceOver ownership. |
| `F-HOME-EMPTY` loaded-empty Home | All conditional sections disappear, leaving a blank loaded view. | Provide intentional empty/recovery action without erasing cached content. |

The contract findings are high-impact static evidence. They remain P0/P1 publication blockers for
the affected implementation packages until exact tests and runtime evidence adjudicate them; this
plan does not claim a production incident.

### In flight and protected

- The primary checkout on branch `Pro` is dirty with owner work and untracked guidance/plans.
- An unrelated `codex/upgrade-planning-handoff` worktree has untracked handoff artifacts and live
  processes. It is not this program's worktree and must not be cleaned.
- Historical package branches/worktrees and the draft v04 plan are evidence only. Reinspect them
  package-by-package; do not cherry-pick or resume based on names.
- PR #117 and `codex/wp-rel-01` are frozen.

### Blocked decision

- `D-IA-01`: top-level shell/Discover/Profile/Settings structure.
- `D-DATA-01`: ownerless legacy private-data recovery/discard policy.
- `D-SURFACE-01`: complete versus truthfully remove unsupported social/moderation and
  journey/event surfaces.
- `D-LOCK-01`: App Lock enforcement/recovery policy.
- `D-ANNOTATION-01`: source-derived cross-device annotation sync versus explicitly local-only truth.

### Blocked evidence or authority

- Deployed backend revision and effective nonproduction configuration.
- Signed development entitlements, device access, credentials, and provider configuration.
- Backend deployment, external configuration, production data, App Store, TestFlight, release,
  signing/certificates, and release evidence.
- Local planning branch/commit operations currently rejected by an environment policy hook;
  local plan authoring remains safe.

### Superseded

The v02 plan's 39-package queue, 87-finding register, 28-lock map, repeated per-role prompts, and
mutable event/hash ledger no longer describe the minimal path. Many of its package claims are now
on `main`; its exact-base assumptions and line anchors drifted; its orchestration added hundreds
of artifacts without improving product proof. The 19 MiB comparison corpus reached 315 files in
draft v04 and still paused implementation behind control-plane genesis and unresolved decisions.

Requirements retained from that corpus: fail-closed authority, exact-base verification, protected
owner work, deterministic tests, independent review, bounded remediation, account scoping,
contract/deployment provenance, physical-device truth, and frozen release boundaries.

### Release deferred

Release configuration, deployment, TestFlight, App Store Connect, signing/certificates, pricing,
submission, production flags, and release attestation are not part of this program. “Merged” means
source integration only.

## Central-loop truth table

| Transition | Static implementation | Exact runtime proof at cutoff | Program owner |
|---|---|---|---|
| Discover → Detail | Present; navigation and covers integrated | Stubbed detail only; richer Discover unwired | `WP-CATALOG-01` |
| Detail → Start/Continue | Present | No full live-account/deployed proof | `WP-CATALOG-01` |
| Read | Substantial Reader implementation | No complete current-main UI journey | `WP-READER-01` |
| Listen | Audio implementation exists | Contract mismatch; no background/interruption proof | `WP-AUDIO-01` |
| Note/Highlight/Bookmark | Local journal integrated | Backend notebook contract mismatch | `WP-ANNOTATE-01` |
| Ask | UI/model exists | Transport mismatch; citation routing not end-to-end proven | `WP-ASK-01` |
| Quiz/Review | Quiz draft/server authority improved; Reviews separate | Duplicate review mutation owner and no loop transition proof | `WP-LEARN-01` |
| Durable progress/resume | Components exist | Loop completion/progress refresh/exact resume unwired | `WP-LOOP-01` |

## Planning implications

- Start with recovery truth, contract/security blockers, and a deterministic native evidence
  foundation.
- Keep the graph wide: catalog, reader, auth/account, review, engagement, and CI hardening can
  progress on disjoint roots once their explicit dependencies clear.
- Do not use a broad `AppModel` rewrite. Compose the missing loop in focused integration files.
- Visible unsupported controls are either completed under a verified contract or removed/disabled
  truthfully after the owner decision; no fake success or invented endpoint remains.
