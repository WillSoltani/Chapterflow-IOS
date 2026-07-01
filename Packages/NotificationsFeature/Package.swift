// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotificationsFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "NotificationsFeature", targets: ["NotificationsFeature"]),
    ],
    targets: [
        .target(name: "NotificationsFeature"),
        .testTarget(name: "NotificationsFeatureTests", dependencies: ["NotificationsFeature"]),
    ]
)
