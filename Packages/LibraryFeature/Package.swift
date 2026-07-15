// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibraryFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "LibraryFeature", targets: ["LibraryFeature"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../Models"),
        .package(path: "../Networking"),
        .package(path: "../DesignSystem"),
        .package(path: "../Persistence"),
        .package(path: "../AIFeature"),
        .package(path: "../Fixtures"),
    ],
    targets: [
        .target(
            name: "LibraryFeature",
            dependencies: [
                "CoreKit",
                "Models",
                "Networking",
                "DesignSystem",
                "Persistence",
                .product(name: "AIFeature", package: "AIFeature"),
            ]
        ),
        // Fixtures is a preview/test-only dependency — not linked into the production target.
        .testTarget(
            name: "LibraryFeatureTests",
            dependencies: [
                "LibraryFeature",
                "Persistence",
                .product(name: "Fixtures", package: "Fixtures"),
            ]
        ),
    ]
)
