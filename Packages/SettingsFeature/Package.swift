// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SettingsFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../CoreKit"),
        .package(path: "../Models"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../AuthKit"),
        .package(path: "../NotificationsFeature"),
        .package(path: "../SyncEngine"),
    ],
    targets: [
        .target(
            name: "SettingsFeature",
            dependencies: [
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "Models", package: "Models"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "AuthKit", package: "AuthKit"),
                .product(name: "NotificationsFeature", package: "NotificationsFeature"),
                .product(name: "SyncEngine", package: "SyncEngine"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SettingsFeatureTests",
            dependencies: [
                "SettingsFeature",
                .product(name: "AuthKit", package: "AuthKit"),
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Persistence", package: "Persistence"),
            ]
        ),
    ]
)
