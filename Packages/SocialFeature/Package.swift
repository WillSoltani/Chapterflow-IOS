// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SocialFeature",
    defaultLocalization: "en",
    // macOS declared so AppFeature (which depends on us) can build and test on the host toolchain.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SocialFeature", targets: ["SocialFeature"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../Models"),
        .package(path: "../Networking"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "SocialFeature",
            dependencies: [
                "CoreKit",
                "Models",
                "Networking",
                "DesignSystem",
            ]
        ),
        .testTarget(
            name: "SocialFeatureTests",
            dependencies: [
                "SocialFeature",
                "Networking",
                "CoreKit",
            ]
        ),
    ]
)
