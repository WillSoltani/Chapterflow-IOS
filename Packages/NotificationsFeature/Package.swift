// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotificationsFeature",
    // macOS added so tests run on the host toolchain; shipping target is iOS.
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "NotificationsFeature", targets: ["NotificationsFeature"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
    ],
    targets: [
        .target(
            name: "NotificationsFeature",
            dependencies: [
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Networking", package: "Networking"),
            ]
        ),
        .testTarget(
            name: "NotificationsFeatureTests",
            dependencies: [
                "NotificationsFeature",
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "Networking", package: "Networking"),
            ]
        ),
    ]
)
