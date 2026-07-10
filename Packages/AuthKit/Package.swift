// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuthKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AuthKit", targets: ["AuthKit"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(
            url: "https://github.com/aws-amplify/amplify-swift.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .target(
            name: "AuthKit",
            dependencies: [
                "CoreKit",
                "DesignSystem",
                "Networking",
                "Persistence",
                .product(name: "Amplify", package: "amplify-swift"),
                .product(name: "AWSPluginsCore", package: "amplify-swift"),
                .product(name: "AWSCognitoAuthPlugin", package: "amplify-swift"),
            ]
        ),
        .testTarget(
            name: "AuthKitTests",
            dependencies: [
                "AuthKit",
                "CoreKit",
                "Persistence",
            ]
        ),
    ]
)
