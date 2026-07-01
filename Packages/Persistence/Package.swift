// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Persistence",
    // macOS allows swift test on the host toolchain; the app targets iOS 18.
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    targets: [
        .target(name: "Persistence"),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
