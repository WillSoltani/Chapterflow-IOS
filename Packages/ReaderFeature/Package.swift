// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReaderFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ReaderFeature", targets: ["ReaderFeature"]),
    ],
    dependencies: [
        .package(path: "../Models"),
        .package(path: "../DesignSystem"),
        .package(path: "../Persistence"),
        .package(path: "../Networking"),
    ],
    targets: [
        .target(
            name: "ReaderFeature",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Networking", package: "Networking"),
            ]
        ),
        .testTarget(
            name: "ReaderFeatureTests",
            dependencies: [
                "ReaderFeature",
                .product(name: "Models", package: "Models"),
                .product(name: "Persistence", package: "Persistence"),
            ]
        ),
    ]
)
