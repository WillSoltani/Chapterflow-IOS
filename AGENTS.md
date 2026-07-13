# ChapterFlow iOS — Development Operating Contract

This root file governs work in the ChapterFlow iOS repository. It is **tool-aware but not tool-dependent**: use it in Codex, Xcode, terminal workflows, or another approved environment, actively use the relevant skills, MCP servers, connectors, and repository tools available in the current session, and preserve deterministic fallbacks when a capability is unavailable.

The current objective is to **build, repair, integrate, and test the product**. ChapterFlow is **not in release execution**. App Store, TestFlight, production deployment, and release-attestation work require separate explicit owner authorization.

---

## 1. Instruction priority

Follow instructions in this order:

1. Direct user instructions for the current task.
2. The current work-package or task specification.
3. A more specific nested `AGENTS.md` in the edited subtree.
4. This root file.
5. Current repository documentation and conventions.

Nested instructions may add constraints but may not weaken data integrity, security, privacy, testing, accessibility, or evidence requirements.

When docs conflict with current code, tests, CI, or the verified backend contract, investigate and report the discrepancy. Do not silently pick the easiest source.

---

## 1A. Skills, MCP servers, connectors, and tools

ChapterFlow development is expected to use the strongest relevant capabilities available in the current Codex session. Do not ignore an installed skill or MCP server that can materially improve correctness, speed, evidence quality, or reviewability. Tool availability can differ between sessions, so discover the current inventory rather than assuming a fixed list.

### Discovery at task start

Before choosing an implementation approach:

1. Inventory available repository-local skills, global skills, MCP servers, connectors, and specialized tools.
2. Read the instructions for every skill or MCP workflow that is materially relevant before invoking it.
3. Select a small, explicit tool plan for investigation, implementation, validation, and independent review.
4. Prefer purpose-built structured tools over fragile manual scraping or improvised shell parsing.
5. If a useful capability is unavailable, use the safest supported alternative and state the limitation. Do not fabricate tool access or results.

When available, likely relevant capabilities include, but are not limited to:

- SwiftUI architecture and implementation skills, such as `swiftui-expert-skill`;
- Swift 6 concurrency and actor-isolation skills, such as `swift-concurrency`;
- Swift Testing and XCUITest skills, such as `swift-testing-expert`;
- native iOS product-design and accessibility skills, such as `mobile-ios-design`;
- Xcode-oriented MCP tools for project inspection, builds, tests, previews, simulator/device operations, diagnostics, and Apple documentation search;
- GitHub MCP/connectors for repository, commit, PR, issue, review, and workflow metadata;
- `gh` and local Git for gaps such as Actions log inspection, worktrees, branch operations, and reproducible local diffs;
- backend-repository connectors and code-search tools for route, serializer, auth, schema, storage, and deployment verification;
- official Apple documentation or Documentation Search for current Swift, SwiftUI, StoreKit, AuthenticationServices, UserNotifications, WidgetKit, ActivityKit, accessibility, privacy, and App Store behavior;
- design MCPs such as Figma when the task includes an approved design source or design-system implementation;
- browser or App Store Connect automation only when the task explicitly authorizes the corresponding external action;
- independent review or subagent capabilities for high-risk security, concurrency, migration, contract, or release-sensitive changes.

The examples above are not an exhaustive or guaranteed inventory. Use the tools actually exposed in the current session.

### Tool-selection rules

- Use multiple complementary skills when the task crosses domains. A reader change may require SwiftUI, concurrency, persistence, accessibility, design, and testing expertise together.
- Prefer the connected source of truth. Use the GitHub connector for repository metadata, the backend repository for contracts, Xcode for compilation/runtime evidence, and official Apple documentation for platform requirements.
- Prefer MCP or connector actions over web search when the source is already connected and the action contract supports the request.
- Use direct Xcode or command-line build/test output as the authority for compilation and tests. A skill summary, generated explanation, or historical PR claim is not proof.
- Use tools proactively during investigation, not only after becoming blocked.
- Parallelize read-only investigation when useful, but do not let multiple agents edit overlapping files or mutate the same external state concurrently.
- Keep high-risk implementation and independent verification separate when reviewer/subagent capability is available. The verifier must inspect the actual diff and rerun proportionate validation.
- Do not use an MCP, browser session, connector, or automation to bypass product decisions, credentials, deployment approval, App Store authorization, data-safety rules, or this file's Git boundaries.
- Read-only discovery is normally allowed. File writes, commits, pushes, PR mutations, deployments, App Store Connect changes, labels, purchases, or other external mutations require the authority defined by the current task.
- Inspect tool output for truncation, stale revisions, hidden failures, skipped tests, and environment mismatch before relying on it.
- Record material tools, commands, revisions, environments, and evidence in the final report so another engineer can reproduce the result.

Skills and MCP servers accelerate the work; they do not replace engineering judgment, repository evidence, deterministic tests, or owner authority.

---

## 2. Current checkpoint and deferred release branch

Revalidate this checkpoint before substantial work.

Known state on **2026-07-13**:

- iOS repo: `WillSoltani/Chapterflow-IOS`
- iOS `main`: `03747305819eccc8bb3c738a21e79d78a82d587d`
- Backend repo: `WillSoltani/ChapterFlow`
- Deferred iOS branch: `codex/wp-rel-01`
- Deferred iOS PR: `#117`
- PR `#117` checkpoint head: `7bb9b5a88494027832cfe1553cc3c6c464702ab6`
- Backend PR `#400` is merged in source. **Merged does not mean deployed.**

### PR #117 is frozen

Unless the owner explicitly changes this decision:

- Do not base new development on `codex/wp-rel-01`.
- Do not merge, close, relabel, force-push, rewrite, or continue PR `#117`.
- Do not continue its App Store Connect, TestFlight, Sandbox-attestation, evidence, production-deployment, or release sequence.
- Do not weaken its CI gate.
- Treat it as read-only reference material.
- Reconstruct useful code on focused branches from current green `main`; do not cherry-pick the entire branch blindly.

Release work resumes only after the app is functionally complete, stable, tested, accessible, and explicitly moved into release preparation by the owner.

---

## 3. Product mission and quality bar

ChapterFlow is a native AI-assisted book-learning product. The app should be calm, editorial, content-first, and recognizably native to iOS.

The central loop is:

```text
Discover → Book Detail → Start/Continue → Read or Listen
→ Note/Highlight/Bookmark/Ask → Quiz or Review
→ Durable Progress → Accurate Resume
```

A change is not complete when only the happy path compiles. Cover all applicable states:

- first use;
- populated;
- loading;
- cached or partial;
- empty;
- error and retry;
- offline/degraded network;
- cancellation and repeated actions;
- expired authentication;
- background/foreground;
- relaunch;
- account A → sign out → account B;
- Light/Dark Mode;
- Dynamic Type and VoiceOver;
- Reduce Motion/Transparency;
- compact iPhone and iPad where supported.

Non-negotiable outcomes:

- No known crash, data loss, wrong-account exposure, or silent mutation loss.
- No visible control that is unwired.
- No false success message.
- No client-side grant of Pro, unlocks, quiz passes, rewards, or moderation authority when the backend is authoritative.
- No invented endpoint, field, runtime result, or product decision.
- No claim of passing tests that were not run on the reported final revision.

---

## 4. Repository map and platform baseline

```text
ChapterFlow.xcodeproj/     Xcode project
ChapterFlow/               Main app host and app-only integrations
Packages/                  Local Swift packages
ChapterFlowUITests/        Deterministic and smoke UI tests
ChapterflowWidgets/        Widgets and Live Activities
NotificationService/       Notification service extension
NotificationContent/       Notification content extension
ShareExtension/            Share extension
ActionExtension/           Action extension
SharedExtensionKit/        Extension-safe shared helpers
Config/                    Plists, entitlements, xcconfig
scripts/                   CI and validation scripts
docs/                      Architecture, contracts, QA and plans
Secrets.example.xcconfig   Non-secret template
Secrets.xcconfig           Local ignored secrets
```

Foundation/platform packages include `Models`, `CoreKit`, `Networking`, `Persistence`, `DesignSystem`, `Fixtures`, `AuthKit`, and `SyncEngine`.

Feature packages include `AppFeature`, `LibraryFeature`, `ReaderFeature`, `QuizFeature`, `PaywallFeature`, `EngagementFeature`, `AIFeature`, `SocialFeature`, `NotificationsFeature`, `OnboardingFeature`, and `SettingsFeature`.

Reinspect `Packages/`, package manifests, the Xcode project, and CI before relying on the list.

Platform rules:

- Swift 6 and strict concurrency.
- SwiftUI for screens; UIKit only for a specific unavailable SwiftUI capability or Apple delegate bridge.
- iOS 18.0 minimum unless changed by an explicit compatibility decision.
- Xcode 26 toolchain for the current SDK symbols.
- Observation framework: `@Observable`; UI models are `@MainActor`.
- `async`/`await` for I/O; do not introduce Combine without a documented need.
- The app host stays thin; `AppFeature` is the composition layer.

Never lower language, concurrency, warning, or deployment settings merely to make a change compile.

---

## 5. Evidence and source-of-truth order

Use this order when investigating behavior:

1. Reproduced runtime behavior on the exact revision/environment.
2. Current executable tests and contract fixtures.
3. Current iOS source.
4. Relevant backend route, validation, serializer, and storage source.
5. Verified deployed backend captures or probes, when available.
6. Current CI/build configuration.
7. Current docs.
8. Historical audit, playbook, PR, or issue text.

Historical findings are leads. Revalidate before editing.

For backend-dependent work, record separately:

- backend source revision inspected;
- environment being discussed;
- deployed revision, if verified;
- whether evidence is static, fixture-based, or runtime.

Never equate backend `main` with the deployed service.

---

## 6. Start-of-task protocol

Before editing:

1. Read this file and any nested `AGENTS.md` files in scope.
2. Read the task, relevant playbook package, and active development-status docs.
3. Inventory the skills, MCP servers, connectors, and specialized tools available in the current session; load the relevant instructions and choose a proportionate tool plan.
4. Inspect repository state:

   ```sh
   git status --short
   git branch --show-current
   git worktree list
   git log -1 --oneline --decorate
   git diff --stat
   ```

5. Confirm the latest intended base and open PR dependencies.
6. Identify the user problem, finding IDs, acceptance criteria, affected repos, and non-goals.
7. Inspect current implementation, tests, fixtures, relevant backend code, and current platform documentation where behavior may have changed.
8. Reproduce the issue or add the smallest deterministic failing test when feasible.
9. Classify the task as iOS-only, backend-only, coordinated, product-decision-dependent, or validation-only.
10. State a concise implementation plan, including which skills/tools will be used, before broad changes.
11. Use a clean branch/worktree for edits.

Do not ask the owner to decide ordinary implementation details. Stop only for a genuine product decision, credential, destructive migration, deployment authority, or incompatible contract choice.

---

## 7. Git and worktree discipline

### Protect user work

- Never reset, clean, overwrite, discard, or stash unrelated user changes without permission.
- Treat an existing dirty checkout as valuable.
- Prefer an isolated worktree from the verified base.
- Record starting commit and dirty files.
- Confirm only intended files changed before handoff.

### Branch rules

- Never develop directly on `main`.
- One coherent work package or vertical slice per branch.
- Branch from latest verified green `main`, unless an explicit predecessor branch is required.
- Do not branch from unrelated open PRs.
- Document stacked dependencies and integration order.
- Do not combine release machinery, broad formatting, feature work, and unrelated refactors.
- Do not force-push a shared branch without explicit authorization.

Suggested names:

```text
codex/wp-dev-00-baseline
codex/wp-auth-01-session
fix/cover-image-loading
feat/reader-loop
```

Committing, pushing, opening/closing/merging a PR, applying labels, or changing external systems requires explicit task authorization. Default to a reviewed local change set plus report.

Before handoff or publication:

```sh
git diff --check
```

---

## 8. Scope and change philosophy

- Prefer targeted incremental changes over rewrites.
- Use a larger architectural change only when evidence shows the current structure prevents correctness, testing, isolation, or quality.
- Prefer complete vertical slices across state, networking, persistence, UI, accessibility, analytics, and tests when needed.
- No placeholder production data, fake success, dead controls, or mock implementations in live paths.
- Do not move a TODO and call it complete.
- Do not fix unrelated code unless it blocks the scoped outcome; report it separately.
- Do not duplicate repositories, token stores, outboxes, navigation owners, or state machines.
- Delete obsolete paths only after proving migration and behavior safety.
- Preserve backward compatibility unless a breaking change is explicitly coordinated.

---

## 9. Architecture invariants

### Composition and dependencies

- Production dependencies are assembled at the composition root.
- Feature views/models depend on protocols or narrow collaborators, not ad hoc production singletons.
- Feature packages do not instantiate `APIClient`, token stores, persistence containers, or unrelated repositories.
- Shared state has one authoritative owner.
- UI state does not depend directly on transport models when a domain mapping is required.
- Navigation has one authoritative owner per flow.
- Extensions are separate processes and must not open the main app SwiftData store.

### Account/session scope

Every user-owned repository, row, cache key, snapshot, outbox item, task, and observer is account-scoped or explicitly public.

Do not use `"anon"`, `"local"`, or an empty user ID for authenticated durable data.

### Swift concurrency

- UI models are `@MainActor @Observable`.
- Mutable networking/sync/cache coordination is actor-isolated.
- Cross-actor values are `Sendable`.
- `@unchecked Sendable` requires a documented synchronization invariant and tests.
- Do not add `nonisolated(unsafe)` as a convenience escape.
- Retain and cancel tasks when lifetime matters.
- Check cancellation before expensive work and before committing stale results.
- Handle `CancellationError` separately from user-facing failures.
- Do not block the main actor with database, file, JSON, image, or network work.
- Durable writes, auth transitions, purchases, deletion, and imports are never unstructured fire-and-forget tasks.
- Token refresh, transaction processing, and sync drains remain single-flight where duplicate execution is dangerous.

---

## 10. Networking and backend contracts

### Requests

- Base URLs come from validated configuration, never feature hardcodes.
- Authenticated REST calls use the Cognito JWT `id_token`:

  ```text
  Authorization: Bearer <token>
  ```

- Never use browser cookies.
- Encode path/query values safely.
- Respect cancellation and bounded timeouts.
- Retry only transient failures and operations safe to retry.
- Preserve idempotency identities for writes.

### Responses

Success is the route's raw JSON object, for example:

```json
{"books": [...]}
```

Errors normally use:

```json
{
  "error": {
    "code": "...",
    "message": "...",
    "requestId": "...",
    "details": {}
  }
}
```

Map transport, HTTP, auth, rate-limit, decoding, and cancellation failures into the shared app error model. Preserve safe request IDs for diagnostics.

### Endpoint-change checklist

1. Inspect the iOS endpoint and caller.
2. Inspect backend route, auth, validation, serializer, errors, and storage.
3. Confirm method, path, auth, request keys, optionality, enums, dates, pagination, and response envelope.
4. Add/update contract fixtures from real output or exact serializer-derived shapes.
5. Add canonical and deployed-compatible tests.
6. Confirm missing/unknown data cannot grant access.
7. Define compatibility, rollout order, and rollback.

Do not invent contracts.

### Server authority

Backend truth controls:

- Pro/subscription status;
- book/chapter access and unlocks;
- quiz correctness/pass;
- points, rewards, badges, tier;
- moderation/safety;
- account status;
- cross-device reconciliation.

Presentation defaults may fail soft. Authority defaults must fail closed.

---

## 11. Codable and server-evolution rules

- Server enums preserve unknown raw values, normally via `.unknown(String)`.
- Every switch handles unknown values deliberately; do not hide owned cases with `@unknown default`.
- Use established canonical-first helpers such as `decodeFirst`, `decodeRequiredFirst`, and envelope adapters.
- Require only the minimum stable identity needed for a meaningful item.
- Accept only verified aliases; always encode the canonical cache shape.
- Independent item arrays may decode lossily when one malformed item must not destroy the response.
- Never use lossy decoding for entitlements, identity, blocklists, transactions, or safety-critical authority.
- Optional server fields remain optional.
- Unknown extra JSON keys are ignored.
- Never force unwrap decoded server data.
- Use shared `JSONCoding` date behavior, including ISO-8601 with and without fractional seconds.
- New enum values, alternate keys, envelope adapters, lossy arrays, and authority fallbacks require evolution/contract tests.
- Hand-authored fixtures alone are insufficient for high-risk contracts.

---

## 12. Authentication, privacy, and security

- Maintain one authoritative session state.
- Sign in with Apple and email/Cognito must converge on the same durable session/refresh model.
- Token refresh remains single-flight.
- Tokens live only in the approved Keychain store/access group.
- Never store or expose tokens in UserDefaults, logs, analytics, fixtures, screenshots, or errors.
- Step-up/recent-auth requirements flow through the shared auth state machine.
- Sign-out stops account-owned background work before another account starts.
- Account deletion/deactivation must match the verified backend body, reauth, subscription, and sign-out semantics.
- Test relaunch, expiry, verifier outage, reauth, sign-out, and account switching.

Never commit or print secrets, JWS/receipt data, transaction IDs, private URLs, emails, device IDs, credentials, or raw user content.

Use privacy-aware logging. Network diagnostics may include method, safe path, status, timing, and request ID; never bodies or auth headers.

Do not overwrite an existing `Secrets.xcconfig`. If a clean compile-only worktree lacks it, `Secrets.example.xcconfig` may be copied locally, but report that live integration was not tested.

---

## 13. Persistence, offline, and synchronization

- Private durable data is account-scoped.
- Cached data is not represented as freshly synchronized.
- Corrupt cache data degrades safely and remains diagnosable.
- Schema changes require a migration or explicitly approved reset strategy, with tests from supported prior versions.
- Offline writes use complete versioned payloads and stable mutation IDs.
- Preserve ordering and idempotency.
- Unknown/malformed mutations are quarantined or surfaced, never deleted as successful no-ops.
- Authentication failure pauses a drain; it is not success.
- Do not discard writes after an arbitrary small retry count without a terminal-error policy.
- UI distinguishes queued, syncing, failed, and synchronized where users need to know.
- Extension outbox order is: read → validate → import → persist → clear.
- A failed import leaves recoverable data.
- Quiz answers are never graded locally; pending grading remains truthful and replay includes required server identity.

---

## 14. UI, design-system, and accessibility rules

Design direction: restrained, editorial, content-first, and native.

- Use semantic `DesignSystem` colors, typography, spacing, radii, materials, motion, and haptics.
- Avoid raw UI literals when an appropriate token exists.
- Extension-only mirrored values must be minimal and documented.
- Prefer system controls and behavior where they meet the product need.
- Loading controls prevent duplicates.
- Success follows real success.
- Errors are actionable and privacy-safe.
- Destructive actions explain consequences and require proportional confirmation.
- Preserve context across retry and reauthentication.

Every screen/flow defines applicable loading, partial, empty, error, offline, cancellation, auth-expiry, and recovery behavior.

Accessibility is part of implementation:

- Dynamic Type through accessibility sizes;
- VoiceOver names, values, hints, traits, order, focus, and announcements;
- sufficient contrast and increased-contrast behavior;
- Reduce Motion and Reduce Transparency behavior;
- no color-only status;
- minimum comfortable touch targets, normally 44×44 pt;
- accessible equivalents for progress/charts;
- logical focus after errors, sheets, navigation, and destructive actions;
- localized accessibility strings.

Provide deterministic previews/render guards for meaningful states. Cover light/dark, compact iPhone, accessibility type, and iPad when supported. Pixel-snapshot only deterministic surfaces; do not create flaky snapshots around OS-dependent materials or navigation chrome.

---

## 15. High-risk feature invariants

### Home, Library, Search

- Valid cached content is not erased by a transient failure.
- Independent sections may degrade independently.
- Search cancels stale work and returns stable results.
- Saved state is account-scoped and rolls back/reconciles truthfully.

### Book covers

- Metadata remains usable when artwork fails.
- Use verified remote cover URLs when available.
- Implement loading, fallback, failure, retry, caching, cancellation, memory, and accessibility behavior.
- Reused cells never show another book's image.

### Navigation

- Deep links, widgets, notifications, Spotlight, Handoff, quick actions, and App Intents retain full destination identity.
- Selecting a tab is insufficient when a link names a detail destination.
- Auth-gated replay opens the intended destination exactly once.

### Reader, Quiz, Review

- Reader state has one owner and cancels stale chapter/preference work.
- Progress/session events are truthful and idempotent.
- Scroll persistence is debounced and account/book/chapter scoped.
- Notes, highlights, bookmarks, Ask, audio, quiz, and next chapter form a coherent loop.
- The server grades quizzes; repeated taps cannot double-submit.
- Offline quiz submission shows pending grading, not a synthetic result.
- Background review/quiz write failures are observable and recoverable.

### AI

- Answers use intended book/chapter context.
- Citations route to valid exact sources.
- Quota/rate-limit/offline states are explicit.
- On-device answers are labeled and not represented as server-grounded citations.
- Questions and selections are private user content.

### Audio and downloads

- Handle interruption, route changes, background playback, cancellation, and expired asset URLs.
- Media state has one owner.
- Do not mark download complete before all required durable assets/records are committed.
- Test resume, deletion, eviction, storage accounting, and memory.
- Media failure never blocks text reading.

### Notifications

- Mark an APNs token registered only after backend acknowledgement.
- Failed register/unregister remains retryable and truthful.
- Unknown push types degrade safely.
- Notification actions route exactly.

### Share/Action extensions

- Claim saved only after durable outbox write.
- Main app imports content before clearing.
- Signed-out/expired states are truthful.

### Subscription/paywall

- StoreKit alone does not grant server-backed Pro.
- Authoritative verification precedes transaction finish when required.
- Pending, cancelled, unavailable, restore, network, and already-Pro states are truthful.
- StoreKit test fixtures never ship in production artifacts.
- App Store Connect, Sandbox attestation, TestFlight, and release evidence remain out of normal development scope.

---

## 16. Testing and evidence

### Evidence rules

Report each command as **passed, failed, skipped, blocked, or not run**. Compilation is not a passing test suite. Old green evidence is invalid after relevant source changes.

Prefer a failing deterministic test before a confirmed bug fix when feasible.

### Package tests

At minimum, run the changed package:

```sh
swift test --package-path Packages/<PackageName> --parallel
```

Run affected dependents after shared API/behavior changes.

Audited main CI package suites:

```text
Models CoreKit Networking Fixtures DesignSystem AIFeature AuthKit
EngagementFeature LibraryFeature NotificationsFeature OnboardingFeature
PaywallFeature Persistence QuizFeature ReaderFeature SettingsFeature SocialFeature
```

Reinspect `.github/workflows/pr.yml`; it is authoritative.

### App build

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

Use `set -o pipefail` in piped scripts.

### UI tests

For composition, navigation, critical user-flow, or wiring changes, run relevant deterministic XCUITests. Baseline full lane:

```sh
xcodebuild test \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination "platform=iOS Simulator,id=<BOOTED_SIMULATOR_UDID>" \
  -only-testing:ChapterFlowUITests \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

Iterate with targeted tests, then run the required broader lane before completion.

### Lint

CI baseline:

```sh
swiftlint lint --strict --reporter github-actions-logging
```

Do not run broad auto-fix in a dirty checkout. In an isolated worktree, review every auto-fix diff.

### Required breadth

| Change | Minimum validation |
|---|---|
| Model/algorithm | Owning package tests plus edge/evolution tests |
| API contract | Networking/model/caller tests plus backend tests or verified evidence |
| Persistence/schema | Migration, account-isolation, relaunch tests |
| Shared foundation | Owning tests, affected packages, app build |
| Navigation/composition | App build and targeted XCUITest |
| Screen/component | Model tests, previews/render guards, accessibility check |
| Offline/sync | Unit + deterministic integration + offline/reconnect/relaunch check |
| Auth/account | Expiry, reauth, sign-out, account-switch validation |
| Media/image | Cancellation, failure, cache, memory/device checks |
| Broad/cross-cutting | Full package suite, app build, full deterministic UI lane, lint |

### Physical-device validation

Use a real device when Simulator cannot prove APNs, background audio, interruptions, widgets/Live Activities, Keychain groups, Sign in with Apple, memory/performance, or real network transitions.

Record device model, OS, build configuration, revision, steps, and outcome without identifiers or personal data.

### Flaky or blocked tests

- Diagnose; do not rerun blindly.
- Do not use retries, `XCTSkip`, expected failure, `continue-on-error`, or waivers merely to get green.
- If an Apple/runtime defect blocks one test, preserve it, run unaffected validation, capture exact evidence, and report the blocker.
- A release waiver is a separate owner decision.

Always finish with:

```sh
git diff --check
```

---

## 17. CI, backend, and external-action boundaries

### CI

- Read the current workflow before changing it.
- Test workflow syntax and scripts locally where possible.
- Keep deterministic development CI separate from release-only gates.
- Do not make normal development depend on App Store metadata, release credentials, or human attestation.
- Do not silently skip required checks when a secret is absent.
- Do not reduce coverage in the name of speed.
- Inspect failing jobs/logs before rerunning.

### Backend

Before backend edits, identify route, schema, validation, storage, auth, all clients, compatibility, tests, rollout, and rollback.

Prefer additive backward-compatible contracts. Coordinate breaking changes through versioning or staged migration.

Do not deploy staging/production, seed data, change infrastructure, rotate secrets, or modify external service configuration without explicit authorization for that exact action.

### External/release actions prohibited by default

Without explicit owner authorization, do not:

- change App Store Connect metadata/pricing/availability;
- upload TestFlight or submit for review;
- deploy backend or infrastructure;
- seed/migrate production data;
- change APNs/App Store Server Notification configuration;
- alter certificates/profiles/keys;
- create release attestation/evidence or labels;
- merge the deferred release PR;
- change production feature flags or kill switches.

---

## 18. Documentation and traceability

When present, read and update the relevant documents:

- `docs/ios/CHAPTERFLOW_IOS_S_TIER_IMPLEMENTATION_PLAYBOOK.md`
- `docs/ios/DEVELOPMENT_EXECUTION_STATUS.md`
- `docs/ios/PR117_EXTRACTION_MATRIX.md`
- contract, auth, architecture, performance, visual-QA, and signing docs under `docs/`

Do not create duplicate status documents.

For completed work, record:

- work-package and audit finding IDs;
- starting/final revisions;
- implemented scope;
- API or persistence changes;
- compatibility/migrations;
- exact tests/commands;
- manual validation;
- remaining risk;
- deployment dependency;
- unresolved product decisions.

Historical line numbers are hints. Reinspect current symbols before editing.

---

## 19. Stop and escalate conditions

Stop and report evidence when:

- a material product choice lacks authority;
- iOS/backend contracts conflict in a way that would break another client;
- a destructive/irreversible migration is required;
- credentials, signing, deployment, or external-account authority is required;
- the work would overwrite unrelated user changes;
- passing requires weakening tests, security, privacy, data integrity, or server authority;
- available tools cannot establish correctness and static evidence is insufficient.

A blocker report includes:

- what was attempted;
- exact evidence;
- why safe progress cannot continue;
- options/tradeoffs;
- recommended default;
- what remains unchanged.

Do not stop for ordinary debugging difficulty. Investigate proportionately and return the best verified result.

---

## 20. Required final response

End implementation work with:

1. **Outcome** — completed user-visible/technical result.
2. **Changed files** — grouped by iOS, backend, tests, config, docs.
3. **Contracts/migrations** — compatibility, rollout, rollback.
4. **Validation** — exact commands and passed/failed/skipped/blocked results.
5. **Runtime/manual checks** — device/simulator, OS, configuration, flows.
6. **Accessibility/privacy/performance** — verified and remaining.
7. **Risks/blockers** — concrete only.
8. **Deviations** — from scope or criteria and why.
9. **Repository/external actions** — commits, push, PR, merge, labels, deployment, App Store actions; explicitly state when none occurred.
10. **Skills and tools used** — material repository/global skills, MCP servers, connectors, simulator/device tools, fallback commands, and any capability limitation that affected confidence.

Never claim a merge, deployment, release, external change, skill invocation, MCP result, or device validation unless it actually occurred and the exact target is identified.

---

## 21. Definition of done

A task is complete only when all applicable items are true:

- Problem and root cause revalidated.
- Scoped behavior fully implemented, not stubbed.
- Architecture and state ownership coherent.
- iOS/backend contracts agree.
- Applicable loading/partial/empty/error/offline/cancellation/auth states handled.
- Account isolation and data integrity preserved.
- Accessibility implemented.
- Security/privacy constraints preserved.
- Migrations/rollback defined and tested.
- Proportionate unit, integration, contract, UI, visual, performance, and manual validation run.
- Strict lint passes.
- Affected targets/app build.
- `git diff --check` passes.
- No unrelated changes, secrets, generated artifacts, or debug code.
- Docs/traceability updated.
- Remaining limitations stated honestly.

Partial progress may be valuable, but must be reported as partial.

### Pre-handoff checklist

```text
[ ] Correct base and isolated worktree confirmed
[ ] Available skills, MCP servers, connectors, and specialized tools inventoried
[ ] Relevant skill/MCP instructions read before use
[ ] Material tools and capability limitations recorded for handoff
[ ] PR #117 left untouched unless explicitly authorized
[ ] Current iOS and backend code inspected
[ ] No invented contract, runtime result, or product decision
[ ] No unrelated user changes modified
[ ] No secret/private data added or logged
[ ] Account isolation and offline integrity considered
[ ] Tests added/updated
[ ] Required tests passed on final revision
[ ] App build passed when applicable
[ ] Targeted/full XCUITest passed when applicable
[ ] Previews/render guards/accessibility checked
[ ] SwiftLint strict passed
[ ] git diff --check passed
[ ] Device checks recorded where required
[ ] Docs/status updated
[ ] Release/deployment/external actions reported as none or explicitly authorized
```
