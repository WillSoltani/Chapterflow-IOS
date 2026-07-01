// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreKit",
    // macOS is included so the package builds and its tests run on the host
    // toolchain (`swift build`/`swift test`); the app itself targets iOS 18.
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
    ],
    targets: [
        .target(name: "CoreKit"),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"]),
    ]
)
