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
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.13.0"),
    ],
    targets: [
        .target(
            name: "CoreKit",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa"),
            ]
        ),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"]),
    ]
)
