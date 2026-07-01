// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EngagementFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "EngagementFeature", targets: ["EngagementFeature"]),
    ],
    targets: [
        .target(name: "EngagementFeature"),
        .testTarget(name: "EngagementFeatureTests", dependencies: ["EngagementFeature"]),
    ]
)
