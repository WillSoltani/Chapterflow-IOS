// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Persistence",
    // macOS is included so the package builds and its tests run on the host
    // toolchain (`swift build`/`swift test`); the app itself targets iOS 18.
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [
        .package(path: "../Models"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [.product(name: "Models", package: "Models")]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", .product(name: "Models", package: "Models")]
        ),
    ]
)
