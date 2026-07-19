# Skill and Capability Routing Index

This is a verified routing index, not authority. At every lane start, rediscover the live inventory,
rehash/read the complete selected `SKILL.md`, read only its routed required references, and record
the exact path/version. Current user/repository instructions and executable evidence override skill
advice. If a skill is missing, stale, ambiguous, writes outside the package, or conflicts with
current official guidance, use the fallback and report the limitation.

## Planning and coordination skills verified in this session

| Skill ID | Exact source / version | Route | Required references used or required at lane start | Limitation / fallback |
|---|---|---|---|---|
| `ios-skills:project-skill-audit` | iOS Skills Collection 1.0.0, `/Users/radinsoltani/.codex/plugins/cache/ios-skills-collection/ios-skills/1.0.0/skills/dimillian--project-skill-audit/SKILL.md` | Planning discovery only | Complete skill | Do not let audit tools mutate repository skills; fallback is explicit inventory with `find`/`rg`. |
| `ios-skills:ios-skills-router` | iOS Skills Collection 1.0.0, `/Users/radinsoltani/.codex/plugins/cache/ios-skills-collection/ios-skills/1.0.0/skills/_router/SKILL.md` | Select one narrow framework skill only when imports prove the domain | Complete skill, then selected framework skill | Router output is a candidate, not proof. |
| `engineering-skills:senior-prompt-engineer` | Claude engineering skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-skills/2.9.0/skills/senior-prompt-engineer/SKILL.md` | Shared prompts and semantic evals | `prompt_engineering_patterns.md`, `llm_evaluation_frameworks.md`, `agentic_system_design.md` | Static scores are advisory; semantic cases and reviewers decide. |
| `engineering-advanced-skills:agent-workflow-designer` | Claude advanced skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-advanced-skills/2.9.0/skills/agent-workflow-designer/SKILL.md` | Bounded lane/handoff/recovery workflow | `workflow-patterns.md` | No mutable event ledger or another runtime's command syntax. |
| `engineering-advanced-skills:spec-driven-workflow` | Claude advanced skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-advanced-skills/2.9.0/skills/spec-driven-workflow/SKILL.md` | Package contracts and traceability | `spec_format_guide.md`, `acceptance_criteria_patterns.md`, `bounded_autonomy_rules.md` | Repository evidence overrides generic spec patterns. |
| `engineering-skills:senior-architect` | Claude engineering skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-skills/2.9.0/skills/senior-architect/SKILL.md` | Only cross-owner composition/interface packages | `architecture_patterns.md`, `system_design_workflows.md` | Does not authorize broad redesign. |
| `agent-teams:task-coordination-strategies` | Agent Teams 1.0.3, `/Users/radinsoltani/.codex/plugins/cache/claude-code-workflows/agent-teams/1.0.3/skills/task-coordination-strategies/SKILL.md` | Ready-set, dependencies, locks, stalled-lane recovery | Complete skill | Apply through current collaboration tools. |
| `agent-teams:team-composition-patterns` | Agent Teams 1.0.3, `/Users/radinsoltani/.codex/plugins/cache/claude-code-workflows/agent-teams/1.0.3/skills/team-composition-patterns/SKILL.md` | Smallest risk-appropriate team | Complete skill | Maximum four active agents including root; children do not spawn. |
| `agent-teams:parallel-feature-development` | Agent Teams 1.0.3, `/Users/radinsoltani/.codex/plugins/cache/claude-code-workflows/agent-teams/1.0.3/skills/parallel-feature-development/SKILL.md` | At most two disjoint editors | Complete skill | One owner per path; unique scratch/DerivedData. |
| `agent-teams:multi-reviewer-patterns` | Agent Teams 1.0.3, `/Users/radinsoltani/.codex/plugins/cache/claude-code-workflows/agent-teams/1.0.3/skills/multi-reviewer-patterns/SKILL.md` | Distinct-dimension final reviews | Complete skill | Deduplicate overlap; do not vote on severity. |
| `agent-teams:team-communication-protocols` | Agent Teams 1.0.3, `/Users/radinsoltani/.codex/plugins/cache/claude-code-workflows/agent-teams/1.0.3/skills/team-communication-protocols/SKILL.md` | Only while multiple agents are active | Complete skill | Compact evidence handoffs, 12 KiB maximum. |

## Native implementation skills

Repository-local skills are intentionally read from the protected owner checkout when absent from a
clean worktree. Their path is evidence, not permission to copy the untracked skill directory.

| Skill ID | Exact source | Use when | References to route | Limit / fallback |
|---|---|---|---|---|
| `repo:mobile-ios-design` | `/Users/radinsoltani/Chapterflow-IOS/.agents/skills/mobile-ios-design/SKILL.md` | Information architecture, adaptive layout, native interaction, visual hierarchy | Only task-relevant references named by the skill | Official current HIG wins; no universal 8-point grid or checker-based readiness score. |
| `repo:swiftui-expert-skill` | `/Users/radinsoltani/Chapterflow-IOS/.agents/skills/swiftui-expert-skill/SKILL.md` | SwiftUI state, layout, navigation, accessibility, rendering, performance | Read `latest-apis.md` first, then task-specific state/layout/navigation/accessibility/performance refs | Verify SDK/toolchain symbols; iOS 26 requires iOS 18 outcome fallback. |
| `repo:swift-concurrency` | `/Users/radinsoltani/Chapterflow-IOS/.agents/skills/swift-concurrency/SKILL.md` | Actors, cancellation, task lifetime, Sendable, strict Swift 6 issues | First inspect actual package/project concurrency settings; then smallest relevant task/actor/testing/performance ref | No blanket MainActor, detached task, unchecked Sendable, or unsafe isolation escape. |
| `repo:swift-testing-expert` | `/Users/radinsoltani/Chapterflow-IOS/.agents/skills/swift-testing-expert/SKILL.md` | Swift Testing design, deterministic async tests, isolation, parameterization | `fundamentals.md` plus only relevant expectations/parallelization/async/performance/migration refs | XCTest remains for XCUITest and XCTest metrics; fix isolation before serializing. |
| `apple-hig-expert:apple-hig-expert` | plugin distribution 2.9.0, skill metadata 1.1.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/apple-hig-expert/2.9.0/skills/apple-hig-expert/SKILL.md` | Native/HIG review | `platform-specifics.md`, `visual-design.md`, `accessibility.md`; official linked Apple pages live | Skill/checker is advisory measurement only. |
| `accessibility-compliance` | `/Users/radinsoltani/.agents/skills/accessibility-compliance/SKILL.md` | Accessibility implementation/review | Mobile accessibility and current WCAG/HIG references applicable to the surface | Does not replace VoiceOver/Inspector/device evidence. |
| `ios-skills:swiftui-performance-audit` | iOS Skills Collection 1.0.0, `/Users/radinsoltani/.codex/plugins/cache/ios-skills-collection/ios-skills/1.0.0/skills/dimillian--swiftui-performance-audit/SKILL.md` | Measured SwiftUI hot paths or trace-backed jank/memory | `code-smells.md`, `profiling-intake.md`, `report-template.md` | Code suspicion is not a metric; use Instruments/device before claiming improvement. |

For ActivityKit, WidgetKit, notifications, authentication, StoreKit, AVKit/audio, and other Apple
frameworks, invoke `ios-skills:ios-skills-router` at lane start and select exactly one current
framework skill only if changed imports require it. Record the live ID/path then; do not pre-load a
catalog.

## Delivery and proof skills

| Skill ID | Source / version | Route | References / caveats |
|---|---|---|---|
| `engineering-advanced-skills:git-worktree-manager` | Claude advanced skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-advanced-skills/2.9.0/skills/git-worktree-manager/SKILL.md` | Isolation and safe cleanup | Use repository-native worktrees; ignore its web-server port/env-copy advice for iOS. Never force-remove dirty work. |
| `engineering-advanced-skills:ci-cd-pipeline-builder` | Claude advanced skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-advanced-skills/2.9.0/skills/ci-cd-pipeline-builder/SKILL.md` | Detect/audit CI stack before workflow edits | `pipeline-design-notes.md`, `deployment-gates.md`; deployment generation remains excluded. |
| `github-actions-efficiency` | `/Users/radinsoltani/.codex/skills/github-actions-efficiency/SKILL.md` | Evidence-backed CI cost/latency changes | `references/actions.md`; do not reduce coverage or claim savings without runs. |
| `github-actions-hardening` | `/Users/radinsoltani/.codex/skills/github-actions-hardening/SKILL.md` | Any workflow change | Trigger/privilege, permissions/token, injection, and supply-chain refs as applicable; use `actionlint` and `zizmor`. |
| `minimalist` | Claude advanced distribution 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-advanced-skills/2.9.0/minimalist/SKILL.md` | Final YAGNI/consolidation pass | Repository safety/quality overrides brevity; stdlib validator, no extra plan framework. |
| `verification-before-completion` | OpenAI curated Superpowers snapshot `2f1a8948`, `/Users/radinsoltani/.codex/plugins/cache/openai-curated/superpowers/2f1a8948/skills/verification-before-completion/SKILL.md` | Before pass/complete/merge claims | Fresh full command and read output; agent reports are not proof. |

## Independent review skills

| Skill ID | Source | Use | Required route / limitation |
|---|---|---|---|
| `engineering-skills:code-reviewer` | Claude engineering skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-skills/2.9.0/skills/code-reviewer/SKILL.md` | Ordinary Swift final-diff review | Always load `rules/universal.md` and `languages/swift.md`; repository thresholds and behavior outrank generic scoring. |
| `engineering-advanced-skills:pr-review-expert` | Claude advanced skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-advanced-skills/2.9.0/skills/pr-review-expert/SKILL.md` | Blast radius, scope, tests, breaking change, merge review | Avoid credential/ticket integrations unless explicitly configured/authorized; report evidence, not a numeric approval shortcut. |
| `engineering-advanced-skills:api-design-reviewer` | Claude advanced skills 2.9.0, `/Users/radinsoltani/.codex/plugins/cache/claude-code-skills/engineering-advanced-skills/2.9.0/skills/api-design-reviewer/SKILL.md` | Contract package only if a machine API spec exists | Its OpenAPI tools are inapplicable when no OpenAPI artifact exists; fallback to route/serializer/storage source, fixtures, backend tests, and differential review. |
| `differential-review:differential-review` | Trail of Bits 1.1.1, `/Users/radinsoltani/.codex/plugins/cache/trailofbits/differential-review/1.1.1/skills/differential-review/SKILL.md` | Security-relevant auth/account/contract/persistence diffs | Load methodology; add adversarial/reporting refs for high-risk/final report. Output must stay inside the package's allowed evidence path. |
| `insecure-defaults:insecure-defaults` | Trail of Bits 1.0.1, `/Users/radinsoltani/.codex/plugins/cache/trailofbits/insecure-defaults/1.0.1/skills/insecure-defaults/SKILL.md` | Auth/config/authority fail-open review | Trace production reachability; exclude explicit tests/examples; fail-secure behavior is not a finding. |

## Verified tools and connectors

- GitHub connector: live commits, PR metadata, checks, branch/PR mutations when authorized.
- XcodeBuildMCP: project/scheme/build/test/simulator/screenshot/UI capabilities; call session defaults
  before build/run/test and use shell `xcodebuild` as the deterministic fallback.
- CLIs observed: `git`, `gh`, `xcrun`, `xcodebuild`, `swift`, `swiftlint`,
  `swiftformat`, `periphery`, `xcbeautify`, `semgrep`, `actionlint`, `zizmor`,
  `maestro`, `renovate`, `rg`, Node/npx, and Python 3. Revalidate path/version/auth before use.
- Official Apple documentation: web fallback used because no Apple documentation MCP was exposed.
- No verified Figma, AWS, Serena, or browser-design source was available. Do not install/request a
  connector without an approved source and a package need.

## Explicitly rejected or conditional

- `engineering-advanced-skills:ship-gate`: release/pre-production oriented; this development
  program must not claim ship/App Store readiness.
- Generic `performance-profiler`: Node/Python/Go oriented and not the iOS runtime authority;
  use Instruments plus `ios-skills:swiftui-performance-audit` for iOS. It may be selected later
  only for measured backend Node work.
- `agentic-actions-auditor`: only if a package actually introduces or changes an agentic Action;
  none is planned.
- Property-based testing, sharp-edges, supply-chain audit, writing-for-interfaces, and a framework
  skill are conditional candidates only. Route one after evidence proves the need; they are not
  pre-authorized boilerplate.
- App Store/ASC/ASO/TestFlight/release, web/React/Playwright/Chrome, AWS deployment,
  prompt-governance, mutation-testing, and self-evaluation skills are outside the planned core.
