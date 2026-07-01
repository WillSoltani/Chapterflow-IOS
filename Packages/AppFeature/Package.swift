// swift-tools-version: 6.0
import PackageDescription

// AppFeature is the composition root: it depends on every other module in the
// workspace and is the single dependency the app target links against.
let modules = [
    "DesignSystem",
    "CoreKit",
    "Networking",
    "Persistence",
    "Models",
    "AuthKit",
    "LibraryFeature",
    "ReaderFeature",
    "QuizFeature",
    "PaywallFeature",
    "EngagementFeature",
    "AIFeature",
    "SocialFeature",
    "NotificationsFeature",
    "OnboardingFeature",
    "SettingsFeature",
]

let package = Package(
    name: "AppFeature",
    // macOS is declared only so the SwiftUI composition root builds and tests on
    // the host toolchain (`swift build`/`swift test`). The shipping target is iOS.
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    dependencies: modules.map { .package(path: "../\($0)") },
    targets: [
        .target(
            name: "AppFeature",
            dependencies: modules.map { .product(name: $0, package: $0) }
        ),
        .testTarget(name: "AppFeatureTests", dependencies: ["AppFeature"]),
    ]
)
