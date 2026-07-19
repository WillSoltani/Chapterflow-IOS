# Upgrade Planning Checkpoint

Updated: `2026-07-19T00:46:56Z`

## Program state

- Phase: `PHASE_D_VALIDATION_AND_REVIEW`
- Planning status: `VALIDATED_REVIEWED_READY_FOR_PUBLICATION`
- Product implementation status: `NOT_STARTED`
- Sole write set: `upgrade/**`
- Next action: create the exact reviewed planning commit, verify its tree and `upgrade/**`-only diff,
  then attempt the authorized Git/GitHub publication, required-check, guarded auto-merge, post-merge,
  and safe-cleanup lifecycle.

## Verified planning base

- Repository: `WillSoltani/Chapterflow-IOS`
- Remote target branch: `main`
- Exact remote head: `22da44d27bc18771f4d7db7681e17c10970ccb13`
- Commit: `WP-COVER-01A: Render cached backend book artwork (#139)`
- Remote evidence: GitHub connector recent-commit/open-PR query refreshed immediately before final
  review closure on `2026-07-19`; remote `main`, local cached `origin/main`, task-worktree `HEAD`, and
  connector result agree, while PR #117 remains the only open PR.
- Local planning worktree: `/Users/radinsoltani/.codex/worktrees/d6dc/Chapterflow-IOS`
- Initial local state: clean, detached at the verified base, with no pre-existing `upgrade/` path.
- Intended planning branch: `codex/upgrade-program-plan`
- Local branch limitation: the environment policy hook rejected the explicitly authorized `git switch -c`; do not treat a detached worktree as a published branch. Continue local plan authoring and retry publication only through supported, authorized Git/GitHub mechanisms.

## Preservation fingerprint

Owner checkout: `/Users/radinsoltani/Chapterflow-IOS`

- Branch: `Pro`
- HEAD: `7291e8c3d43b37d3e63f732ffc3a6cc9a8c832d1`
- Protected status SHA-256: `e25d240ffa191ef227b5798947d3f59a8dd59789f01cdb31f51a823047d7157d`
- Tracked diff SHA-256: `2281f515b42154b92524b39adf3ce2d5814b86212cadf5574207525cf6868d2e`
- Fingerprint observation: `2026-07-19T00:32:59Z`. Status input is the exact stdout bytes of
  `git -C /Users/radinsoltani/Chapterflow-IOS status --porcelain=v2 --branch`, piped only to
  `shasum -a 256`; diff input is the exact binary patch bytes from
  `git -C /Users/radinsoltani/Chapterflow-IOS diff --binary`, piped only to `shasum -a 256` and not
  persisted. HEAD and branch were independently read with `rev-parse HEAD` and
  `branch --show-current`.
- Dirty paths observed and protected: `ChapterFlow.xcodeproj/project.pbxproj`, `.agents/`, `AGENTS.md`, `ChapterFlow-S-Tier-Plan/`, `S_TIER_PLAYBOOK_REBUILD_PROMPT/`, and `docs/ios/CHAPTERFLOW_IOS_FULL_SESSION_SUMMARY_2026-07-12.md`.
- Owner `AGENTS.md` SHA-256: `cf9f435745593215cbca036c74fc274b355ee073c48fb6c59c04f72863a0289a`
- The owner checkout is read-only evidence for this task. No normalization, copying, stashing, reset, or cleanup is authorized.

Backend checkout: `/Users/radinsoltani/ChapterFlow`

- Branch: `update`
- Protected checkout HEAD: `04e0ae50b4c1f1722b33a6501e03b79bc8894112`
- Cached `origin/main`: `858d2d7ffd620a7c28cdad5a75007536ccd5b391`
- Protected untracked paths: `CODEX_WAVE2_ARCHITECTURE_COMPLETION_PROMPT.md` and `upgrade/`.
- Program backend source baseline: remote/cached `main` at `858d2d7ffd620a7c28cdad5a75007536ccd5b391`; the protected `update` checkout is preservation evidence, not the baseline.
- Evidence type: static source only so far.
- Deployed revision/environment: unknown; do not infer deployment from source or merge state.

## Frozen release work

- PR `#117`: open, draft, unmerged, head `7bb9b5a88494027832cfe1553cc3c6c464702ab6`.
- Frozen branch: `codex/wp-rel-01`.
- Action: read-only reference only; no mutation, continuation, merge, or release activity.

## Skills and tools selected so far

- Read: `project-skill-audit` from iOS Skills Collection 1.0.0.
- Read: `ios-skills-router` from iOS Skills Collection 1.0.0.
- Read: Agent Teams 1.0.3 `task-coordination-strategies`, `team-composition-patterns`, `parallel-feature-development`, `multi-reviewer-patterns`, and `team-communication-protocols`.
- Verified local owner skills: `mobile-ios-design`, `swiftui-expert-skill`, `swift-concurrency`, and `swift-testing-expert`; route only when their audited domain is active.
- Verified connector: GitHub, used read-only for repository metadata, current commits, open PRs, and PR #117.
- Verified local tools used: `rg`, `git` read-only commands, `shasum`, `diff`, `find`, and stdlib shell utilities.
- Capability status at `2026-07-19T00:32:59Z`: `git worktree list --porcelain` passed and recorded
  eight entries including this detached planning worktree and frozen `wp-rel-01`; no cleanup was
  attempted. Earlier `git fetch` and local branch creation were rejected by a policy hook and were
  not re-probed during this read-only fingerprint refresh. No result is fabricated; the GitHub
  connector remains the remote source of truth.

## Material evidence found

- The v02 catalog contains 39 packages, 87 findings, 28 exclusive-style locks, 300 files, repeated four-role prompts, and mutable ledger/event/hash machinery. The comparison corpus has grown to 19 MiB and 315 files in draft v04 without entering implementation. It must be audited, not inherited.
- Current `main` already contains recent integrated slices for covers, annotations, entitlements, quiz draft submission, design-system states, exact navigation, sync safety, session scope, networking reliability, auth, and observability. Old-plan claims must be reconciled against these exact revisions.
- The primary `AGENTS.md` is intentionally untracked and differs from the clean-worktree tracked copy at its dated checkpoint; the owner copy controls under the user request.
- Product/contract audit: 19 Swift packages and seven native targets retain a thin host and account-scoped session graph, but static source proves an account-delete request mismatch, a likely signed Keychain entitlement/access-group mismatch, incompatible Ask/audio/annotation contracts, an incomplete reader-loop composition, preserved-but-never-imported extension data, duplicate review-mutation ownership, and a fail-open backend account guard. Signed-device and deployed-runtime proof are absent.
- Native audit: nested interactive controls, blank loaded-empty Home, invalid visual baselines, broad iPad adaptation gaps, an inaccessible custom concept graph, and English-only localization are P1 planning inputs. Cross-flow evidence must start with a deterministic visual/accessibility harness rather than finish as cosmetic polish.
- Quality/recovery evidence verified directly by the primary: `.github/workflows/pr-v2.yml` is the current required CI workflow; `pr.yml` is manual legacy fallback; PR #117 remains the only open PR; multiple old-plan implementation claims are superseded by commits already on `main`; and an unrelated active `codex/upgrade-planning-handoff` worktree contains untracked owner work and live processes, so it is protected.
- The delegated quality/recovery auditor did not return a usable evidence handoff after the single bounded status/recovery request and was interrupted. No evidence from that lane is treated as proof; the primary's cited live repository evidence is the fallback.

## Phase B/C synthesis and authored program

- Current state is separated into verified-complete, partial, missing, broken/incompatible,
  in-flight/protected, blocked-decision, blocked-evidence/authority, superseded, and
  release-deferred categories.
- Four distinct milestones and a fail-closed development-quality rubric cover correctness,
  contracts, architecture/concurrency, native UI, accessibility, localization, reliability,
  performance, privacy/security, testing, CI, and maintainability.
- The lean artifact is 134 files/988 KiB: 11 outcome workstreams, 24 packages, five owner decisions,
  seven declared resource locks, three shared prompts, and 20 critical evaluation cases. The old
  v02 corpus was 300 files and grew to 315 files/19 MiB in draft v04.
- The dependency graph is built before lane assignment. `WP-REC-01` is the sole initial ready node;
  maximum editors is two; path claims are narrowed to concrete roots/files; shared monolithic
  Networking endpoint changes serialize through `contract-inventory`; each package claims at most
  one high-contention lock.
- Static prompt baseline: old v02 passes 15/20 and draft-v0 passes 19/20. The second/final bounded
  revision closes ownership, lock, recovery, and evidence-lifecycle gaps without relaxing any
  expectation. Independent evaluator `phase-d-semantic-final-independent` passes all 20 critical
  cases and all 40 exact artifact assertions at the hash-bound final sources.

## Phase D evidence so far

- `python3 -B upgrade/scripts/validate_upgrade_plan.py` — `passed` at `2026-07-19T00:44:59Z`:
  `PASS: upgrade plan validated (11 workstreams, 24 packages, 20 eval cases)`. The machine gate
  covers package/backlog/DAG/path/ownership/lock/atomic-evidence/attempt-reference/recovery/
  backend-inspection/native-state/performance/reopen/static-analysis and semantic hash contracts.
- Prompt static analysis — `passed` on the current hash-bound prompts: 2097/764/763 tokens,
  clarity 77/78/86, structure 100/90/90. The 6/5/3 repetition/few-shot advisories are recorded,
  not hidden; safety-critical nouns and exact evidence schemas remain explicit.
- Independent semantic evaluation — `passed`: 20/20 critical cases and 40/40 exact artifact
  assertions, evaluator `phase-d-semantic-final-independent`, revision rounds `2`.
- `actionlint .github/workflows/pr-v2.yml` — `passed` on the authoritative required workflow.
- Combined legacy comparison `actionlint` — `failed` only on two pre-existing informational SC2012
  findings in `.github/workflows/pr.yml`; no workflow was changed in this plan task.
- Offline `zizmor --min-severity medium .github/workflows` — `failed` with current-source hardening
  findings (11 medium, 11 high), including unpinned actions outside authoritative `pr-v2`, legacy or
  release permissions, and a release cache risk. `WP-HARD-01` owns bounded development remediation;
  release execution remains excluded.
- `git diff --check` — `not applicable/vacuous before publication`: all 134 plan files are untracked,
  so Git inspects none of them. `validate_text_integrity()` in the plan validator is the current
  newline/conflict/trailing-whitespace authority; rerun real `git diff --check` after the candidate is
  staged/committed. `git status --short` shows only untracked `upgrade/`; no product, backend,
  workflow, or protected-checkout file changed.
- Final independent traceability review initially found two direct REC runner rows missing mandatory
  attempt identity and this checkpoint's stale Phase D state. Both were remediated in the same final
  bounded cluster; the validator now inspects every direct runner invocation. The fresh traceability
  re-review is `PASS` with no remaining P0/P1/P2.
- Final independent native/product/accessibility re-review is `PASS` with no remaining P0/P1/P2; it
  verified localization ownership, adverse/A→B coverage, pagination/Graph performance, exact-final
  physical VoiceOver inventory, AUTH anchors, package envelopes, and DAG mirrors.

## Blockers and decisions

- `BLOCKED_TOOLING` (non-terminal): earlier local Git branch creation/fetch operations were blocked
  by an environment policy hook; read-only worktree listing now passes. Local planning can proceed
  safely; publication will use only a supported authorized Git/GitHub path, and cleanup remains
  conditional on a recorded merge and post-merge success.
- `BLOCKED_EVIDENCE`: deployed backend revision remains unknown. Packages that depend on deployed behavior must encode this as a gate, not assume source equals deployment.
- Candidate owner decisions now requiring explicit gates: top-level information architecture;
  treatment of ownerless legacy private data; unsupported social/moderation and journey/event
  surfaces; App Lock policy; and annotation sync/local-only authority. External signing, provider
  configuration, deployment, and credentials are authority/evidence gates rather than invented
  product decisions.

## Preservation rule

Refresh this checkpoint after each phase. Before publication and after any external mutation, recheck both protected checkouts and confirm that only `upgrade/**` changed in this task worktree.
