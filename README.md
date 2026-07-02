# ChapterFlow iOS

Native SwiftUI app for ChapterFlow — AI-powered book learning. Swift 6, iOS 18+, modular SPM architecture.

## Prerequisites

- Xcode 16+ (macOS 15+)
- SwiftLint (`brew install swiftlint`)
- A copy of `Secrets.xcconfig` (see below)

## Local setup

```sh
# Clone the repo
git clone https://github.com/WillSoltani/Chapterflow-IOS
cd Chapterflow-IOS

# Copy secrets template — fill in real values before building
cp Secrets.example.xcconfig Secrets.xcconfig
```

Open `ChapterFlow.xcodeproj` in Xcode. The first open resolves all SPM packages automatically (this can take several minutes for the Amplify dependency tree).

## Build

```sh
# App target — iOS Simulator (no signing required)
xcodebuild build \
  -project ChapterFlow.xcodeproj \
  -scheme ChapterFlow \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

Flags explained:
- `-skipPackagePluginValidation` — bypasses Xcode's interactive trust prompt for Amplify's `SmithyCodeGenerator` build-tool plugin (required in headless environments).
- `-skipMacroValidation` — bypasses the Swift macro sandbox trust prompt.

## Test

All local packages declare `.macOS(.v14)` support so their unit tests run directly on the host toolchain without a booted simulator.

```sh
# Test a single package
swift test --package-path Packages/Models --parallel

# Test all packages (bash loop)
for pkg in Models CoreKit Networking Fixtures DesignSystem \
           AIFeature AuthKit EngagementFeature LibraryFeature \
           NotificationsFeature OnboardingFeature PaywallFeature \
           Persistence QuizFeature ReaderFeature SettingsFeature \
           SocialFeature; do
  echo "── $pkg ──"
  swift test --package-path "Packages/$pkg" --parallel
done
```

> **Note:** `AppFeature` requires the macOS 15 Swift stdlib (for the SwiftUI `Tab {}` API) and is excluded from the local loop above. It is fully covered by the Xcode build step and its dependencies are tested individually.

## Lint

```sh
swiftlint lint --strict
```

The project uses `.swiftlint.yml` at the repo root. Fix all violations before opening a PR; the `Lint` CI job runs `--strict` and fails on any violation.

## Contract-drift check (local)

Refresh fixture JSON from the live API and run the RF2 evolution tests:

```sh
CF_CI_TOKEN=<your-token> API_BASE_URL=https://api.chapterflow.com \
  bash scripts/refresh-fixtures.sh

swift test --package-path Packages/Models --filter "Evolution"
swift test --package-path Packages/Fixtures
```

See [docs/ios/SIGNING-AND-RELEASE.md](docs/ios/SIGNING-AND-RELEASE.md) for token setup.

## CI

| Workflow | Trigger | Purpose |
|---|---|---|
| **PR — Build, Test & Lint** | Every PR + push to `main` | Required merge gate |
| **Release — Archive & TestFlight** | Tag `v*` or manual | TestFlight upload (secret-gated) |
| **Contract Drift** | Weekly Sunday 02:00 UTC | RF2 schema regression |

The PR workflow is a required status check for merging to `main`. See [docs/ios/SIGNING-AND-RELEASE.md](docs/ios/SIGNING-AND-RELEASE.md) for how to configure branch protection and how to activate the signing/TestFlight and drift jobs.

## Architecture

See [docs/PLAN.md](docs/PLAN.md) for the full architecture, roadmap, and prompt library.

### Module graph

```
App target
  └── AppFeature (composition root)
        ├── Feature modules: LibraryFeature, ReaderFeature, QuizFeature,
        │   PaywallFeature, EngagementFeature, AIFeature, SocialFeature,
        │   NotificationsFeature, OnboardingFeature, SettingsFeature
        └── Foundation modules: DesignSystem, CoreKit, Networking,
            Persistence, Models, AuthKit
```

Each module is a self-contained local SPM package under `Packages/`.
