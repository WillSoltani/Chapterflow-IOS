// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SocialFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "SocialFeature", targets: ["SocialFeature"]),
    ],
    targets: [
        .target(name: "SocialFeature"),
        .testTarget(name: "SocialFeatureTests", dependencies: ["SocialFeature"]),
    ]
)
