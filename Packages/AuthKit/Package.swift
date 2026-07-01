// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuthKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AuthKit", targets: ["AuthKit"]),
    ],
    targets: [
        .target(name: "AuthKit"),
        .testTarget(name: "AuthKitTests", dependencies: ["AuthKit"]),
    ]
)
