// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuthKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AuthKit", targets: ["AuthKit"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../Networking"),
    ],
    targets: [
        .target(
            name: "AuthKit",
            dependencies: ["CoreKit", "Networking"]
        ),
        .testTarget(
            name: "AuthKitTests",
            dependencies: ["AuthKit", "CoreKit", "Networking"]
        ),
    ]
)
