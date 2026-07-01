// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OnboardingFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "OnboardingFeature", targets: ["OnboardingFeature"]),
    ],
    targets: [
        .target(name: "OnboardingFeature"),
        .testTarget(name: "OnboardingFeatureTests", dependencies: ["OnboardingFeature"]),
    ]
)
