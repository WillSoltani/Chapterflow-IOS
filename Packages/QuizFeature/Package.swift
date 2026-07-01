// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuizFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "QuizFeature", targets: ["QuizFeature"]),
    ],
    targets: [
        .target(name: "QuizFeature"),
        .testTarget(name: "QuizFeatureTests", dependencies: ["QuizFeature"]),
    ]
)
