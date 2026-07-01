# ChapterFlow — Plan & Shared Context

This document is the source of truth for shared context and conventions. The
repo-root [`CLAUDE.md`](../CLAUDE.md) mirrors the preamble and conventions below;
keep the two in sync.

## Shared Context Preamble

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

## Conventions

- **Naming:** Types `UpperCamel`; properties/functions `lowerCamel`. Models suffix UI state types `…Model` (e.g. `ReaderModel`), data boundaries `…Repository`, network `…Endpoint`. Match server field names in Codable via `CodingKeys` (server uses `lowerCamel` already, so default decoding mostly "just works").
- **Errors:** one `AppError` enum in `CoreKit` (`.unauthenticated`, `.reauthRequired`, `.verifierUnavailable`, `.rateLimited(retryAfter:)`, `.offline`, `.server(code:message:requestId:)`, `.decoding`, `.notFound`). `Networking` maps the error envelope → `AppError`. Views render errors via a shared `ErrorView`/`Toast`.
- **Async:** every I/O method is `async throws`. No completion handlers. Cancel tasks on view disappear where relevant.
- **Testing:** `swift-testing` (the `Testing` framework) for unit tests; XCUITest for 3–4 critical end-to-end flows; snapshot tests for the design system. Repositories are protocols with in-memory fakes for fast tests.
- **Previews:** every view has a `#Preview` using fake repositories + sample data fixtures (a `Fixtures` module/target with canned JSON decoded into models).
- **Git:** one branch per prompt (`feat/p2-4-reader`), PR titled with the prompt id. Keep PRs small. `main` always builds.
- **Secrets:** `Secrets.xcconfig` (gitignored) holds `API_BASE_URL`, Cognito pool/client ids, APNs/StoreKit ids. A `Secrets.example.xcconfig` is committed.
- **Accessibility from day one:** every interactive element has an accessibility label; the reader supports Dynamic Type; respect Reduce Motion.

## Architecture

- App target `ChapterFlow` is a thin `@main` shell. It links **only** against
  `AppFeature`, the composition root. Bundle id `com.chapterflow.ios`.
- `AppFeature` depends on every other module and assembles them into the tab
  shell (`AppRootView`): Home, Library, Reviews, Profile, Settings.
- **Foundation modules:** `DesignSystem`, `CoreKit`, `Networking`,
  `Persistence`, `Models`, `AuthKit`.
- **Feature modules:** `LibraryFeature`, `ReaderFeature`, `QuizFeature`,
  `PaywallFeature`, `EngagementFeature`, `AIFeature`, `SocialFeature`,
  `NotificationsFeature`, `OnboardingFeature`, `SettingsFeature`.
- **Configuration:** `Secrets.xcconfig` → app `Info.plist` → `CoreKit.AppConfig`.
- **App Group:** `group.com.chapterflow` on the app target (future widgets).

## Build & Test

```sh
# App (simulator, no signing required)
xcodebuild -project ChapterFlow.xcodeproj -scheme ChapterFlow \
  -destination 'generic/platform=iOS Simulator' build

# A single package
cd Packages/<Name> && swift build && swift test
```

## Status

**Scaffold stage.** Every module is empty but compiling, with a placeholder
public symbol and a passing test target. The app launches to a 5-tab
placeholder shell. Feature work replaces placeholders module by module.
