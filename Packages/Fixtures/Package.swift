// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fixtures",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "Fixtures", targets: ["Fixtures"]),
    ],
    dependencies: [
        .package(path: "../Models"),
    ],
    targets: [
        .target(
            name: "Fixtures",
            dependencies: ["Models"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "FixturesTests",
            dependencies: ["Fixtures"]
        ),
    ]
)
