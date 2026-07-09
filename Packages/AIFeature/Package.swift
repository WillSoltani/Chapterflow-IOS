// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIFeature",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AIFeature", targets: ["AIFeature"]),
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
            name: "AIFeature",
            dependencies: [
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "Models", package: "Models"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Persistence", package: "Persistence"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation", .when(platforms: [.iOS])),
                .linkedFramework("MediaPlayer", .when(platforms: [.iOS])),
                .linkedFramework("AVKit", .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "AIFeatureTests",
            dependencies: [
                "AIFeature",
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "Models", package: "Models"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Fixtures", package: "Fixtures"),
            ]
        ),
    ]
)
