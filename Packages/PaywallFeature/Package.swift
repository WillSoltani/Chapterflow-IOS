// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaywallFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PaywallFeature", targets: ["PaywallFeature"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../Models"),
        .package(path: "../Networking"),
        .package(path: "../DesignSystem"),
        .package(path: "../Persistence"),
        .package(path: "../Fixtures"),
    ],
    targets: [
        .target(
            name: "PaywallFeature",
            dependencies: [
                "CoreKit",
                "Models",
                "Networking",
                "DesignSystem",
                "Persistence",
            ]
        ),
        .testTarget(
            name: "PaywallFeatureTests",
            dependencies: [
                "PaywallFeature",
                "CoreKit",
                .product(name: "Fixtures", package: "Fixtures"),
            ]
        ),
    ]
)
