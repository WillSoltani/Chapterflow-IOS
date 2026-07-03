// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SettingsFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(
            name: "SettingsFeature",
            dependencies: [
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "CoreKit", package: "CoreKit"),
            ]
        ),
        .testTarget(
            name: "SettingsFeatureTests",
            dependencies: ["SettingsFeature"]
        ),
    ]
)
