// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibraryFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "LibraryFeature", targets: ["LibraryFeature"]),
    ],
    targets: [
        .target(name: "LibraryFeature"),
        .testTarget(name: "LibraryFeatureTests", dependencies: ["LibraryFeature"]),
    ]
)
