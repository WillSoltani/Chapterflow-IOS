> You are building the **native iOS app for ChapterFlow**, an AI book-learning product. A production backend already exists on AWS and **does not change**: a REST API (base URL in `Secrets.xcconfig` as `API_BASE_URL`) with ~74 JSON endpoints, **AWS Cognito** auth (JWT `id_token`), DynamoDB, and S3. This app is a **fresh native SwiftUI client** that consumes that API. It must be **more polished and capable than the web app**: offline reading, premium typography, audio narration, widgets, Live Activities. **Design bar: Apple "Pro" restraint** — like Apple's own first-party apps. Calm, typographic, deferential to content. Not flashy.
>
> **Hard conventions (do not deviate):**
> - **Swift 6**, strict concurrency. **SwiftUI** only (no Storyboards/UIKit screens unless wrapping a specific control). **iOS 18.0** minimum target.
> - State via the **Observation framework** (`@Observable`), `@MainActor` on UI models. **async/await** everywhere; avoid Combine.
> - **Modular local SPM packages** (see architecture). Every feature package ships **SwiftUI `#Preview`s**.
> - **API envelope:** a SUCCESS response body is the **raw JSON object** (e.g. `{"books":[...]}`, `{"chapter":{...},"progress":{...}}`). An ERROR response body is `{"error":{"code":"...","message":"...","requestId":"...","details":?}}` with the matching HTTP status. Decode both shapes.
> - **Auth:** send the Cognito `id_token` as **`Authorization: Bearer <token>`**. Never cookies.
> - **Never hardcode** colors, spacing, fonts, radii — always use `DesignSystem` tokens.
> - Write **unit tests** for all non-trivial logic. Verify UI with **Previews**.
> - **Definition of Done (every task):** the package builds, tests pass, previews render, acceptance criteria met. Keep going until done; don't hand back partial work.
Prompts are tagged **[SEQUENTIAL]** (must follow its dependency) or **[PARALLEL: Track X]** (can be built concurrently on its own branch by a separate Claude session). The parallelization map in Section 5 tells you exactly which tracks can run at once. When running parallel tracks, give each its own git branch off the latest `main`, and integrate via PRs in the order the map suggests.
- **Naming:** Types `UpperCamel`; properties/functions `lowerCamel`. Models suffix UI state types `…Model` (e.g. `ReaderModel`), data boundaries `…Repository`, network `…Endpoint`. Match server field names in Codable via `CodingKeys` (server uses `lowerCamel` already, so default decoding mostly "just works").
- **Errors:** one `AppError` enum in `CoreKit` (`.unauthenticated`, `.reauthRequired`, `.verifierUnavailable`, `.rateLimited(retryAfter:)`, `.offline`, `.server(code:message:requestId:)`, `.decoding`, `.notFound`). `Networking` maps the error envelope → `AppError`. Views render errors via a shared `ErrorView`/`Toast`.
- **Async:** every I/O method is `async throws`. No completion handlers. Cancel tasks on view disappear where relevant.
- **Testing:** `swift-testing` (the `Testing` framework) for unit tests; XCUITest for 3–4 critical end-to-end flows; snapshot tests for the design system. Repositories are protocols with in-memory fakes for fast tests.
- **Previews:** every view has a `#Preview` using fake repositories + sample data fixtures (a `Fixtures` module/target with canned JSON decoded into models).
- **Git:** one branch per prompt (`feat/p2-4-reader`), PR titled with the prompt id. Keep PRs small. `main` always builds.
- **Secrets:** `Secrets.xcconfig` (gitignored) holds `API_BASE_URL`, Cognito pool/client ids, APNs/StoreKit ids. A `Secrets.example.xcconfig` is committed.
- **Accessibility from day one:** every interactive element has an accessibility label; the reader supports Dynamic Type; respect Reduce Motion.
**Slot-fill convention:** `<ID>` and `<prompt title>` come from the `####` header; `<PACKAGE>` from the `· package:`/`· target:` tag; `<DEPENDS>` from the `depends:` tag (plus the Foundation packages, which are always available). Example for **P2.6**: `<ID>=p2-6`, `<PACKAGE>=QuizFeature`, `<DEPENDS>=Models (P2.1), Networking, DesignSystem`, `<BASE>=origin/main`.
## Repository layout

```
ChapterFlow.xcodeproj      App project (target: ChapterFlow, bundle id com.chapterflow.ios)
ChapterFlow/               App shell sources, assets, Info.plist, entitlements
Packages/                  Local Swift Package workspace (17 modules)
  AppFeature/              Composition root — depends on all other modules
  CoreKit/ ...             Foundation & feature modules
docs/PLAN.md               Plan & shared context (mirrors this preamble)
Secrets.example.xcconfig   Template for build secrets (committed)
Secrets.xcconfig           Real secrets (gitignored)
.swiftlint.yml             Optional lint config
```

**Module graph.** The app target links **only** `AppFeature`. `AppFeature`
depends on every other module and assembles them into the tab shell
(`AppRootView`). Foundation modules: `DesignSystem`, `CoreKit`, `Networking`,
`Persistence`, `Models`, `AuthKit`. Feature modules: `LibraryFeature`,
`ReaderFeature`, `QuizFeature`, `PaywallFeature`, `EngagementFeature`,
`AIFeature`, `SocialFeature`, `NotificationsFeature`, `OnboardingFeature`,
`SettingsFeature`. Config flows `Secrets.xcconfig` → app `Info.plist` →
`CoreKit.AppConfig`. App Group `group.com.chapterflow` is enabled for future
widgets.

## Build & Test

```sh
# App (simulator, no signing required)
xcodebuild -project ChapterFlow.xcodeproj -scheme ChapterFlow \
  -destination 'generic/platform=iOS Simulator' build

# A single package
cd Packages/<Name> && swift build && swift test
```

## Working in Xcode

Developed inside Xcode with the `xcode-tools` MCP server. Prefer those tools
(BuildProject, DocumentationSearch, etc.) over command-line equivalents. Use
`DocumentationSearch` for new Apple APIs (Liquid Glass, FoundationModels, latest
SwiftUI).

