// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SettingsFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    targets: [
        .target(name: "SettingsFeature"),
        .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature"]),
    ]
)
