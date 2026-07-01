// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReaderFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ReaderFeature", targets: ["ReaderFeature"]),
    ],
    targets: [
        .target(name: "ReaderFeature"),
        .testTarget(name: "ReaderFeatureTests", dependencies: ["ReaderFeature"]),
    ]
)
