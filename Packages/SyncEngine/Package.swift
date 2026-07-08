// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SyncEngine",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "SyncEngine", targets: ["SyncEngine"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../Models"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "SyncEngine",
            dependencies: [
                "CoreKit",
                "Networking",
                "Persistence",
                "Models",
                "DesignSystem",
            ]
        ),
        .testTarget(
            name: "SyncEngineTests",
            dependencies: ["SyncEngine", "Persistence", "Models", "Networking", "CoreKit"]
        ),
    ]
)
