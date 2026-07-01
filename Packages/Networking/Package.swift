// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Networking",
    // macOS is included so the package builds and its tests run on the host
    // toolchain (`swift build`/`swift test`); the app itself targets iOS 18.
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "Networking", targets: ["Networking"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(
            name: "Networking",
            dependencies: ["CoreKit"]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking", "CoreKit"]
        ),
    ]
)
