// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuizFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "QuizFeature", targets: ["QuizFeature"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../Models"),
        .package(path: "../Networking"),
        .package(path: "../DesignSystem"),
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(
            name: "QuizFeature",
            dependencies: [
                "CoreKit",
                "Models",
                "Networking",
                "DesignSystem",
                "Persistence",
            ]
        ),
        .testTarget(
            name: "QuizFeatureTests",
            dependencies: [
                "QuizFeature",
                .product(name: "Networking", package: "Networking"),
            ]
        ),
    ]
)
