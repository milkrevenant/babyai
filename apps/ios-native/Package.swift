// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BabyAINativeCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "BabyAINativeCore",
            targets: ["BabyAINativeCore"]
        ),
    ],
    targets: [
        .target(
            name: "BabyAINativeCore"
        ),
        .testTarget(
            name: "BabyAINativeCoreTests",
            dependencies: ["BabyAINativeCore"]
        ),
    ]
)
