// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AIFeature", targets: ["AIFeature"]),
    ],
    targets: [
        .target(name: "AIFeature"),
        .testTarget(name: "AIFeatureTests", dependencies: ["AIFeature"]),
    ]
)
