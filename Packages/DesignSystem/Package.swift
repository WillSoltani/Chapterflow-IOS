// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        // Snapshot / render tests — run on macOS via `swift test`.
        // Generate references: SNAPSHOT_RECORD=1 swift test --filter "DesignSystemSnapshotTests"
        .testTarget(
            name: "DesignSystemSnapshotTests",
            dependencies: ["DesignSystem"],
            path: "Tests/DesignSystemSnapshotTests"
        ),
    ]
)
