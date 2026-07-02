// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EngagementFeature",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "EngagementFeature", targets: ["EngagementFeature"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../Models"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "EngagementFeature",
            dependencies: [
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "Models", package: "Models"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),
        .testTarget(
            name: "EngagementFeatureTests",
            dependencies: [
                "EngagementFeature",
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "Models", package: "Models"),
                .product(name: "Networking", package: "Networking"),
            ]
        ),
    ]
)
