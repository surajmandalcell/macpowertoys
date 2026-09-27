// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OnePlusUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "OnePlusUI", targets: ["OnePlusUI"]),
        .executable(name: "OnePlusUIShowcase", targets: ["OnePlusUIShowcase"]),
    ],
    targets: [
        .target(
            name: "OnePlusUI",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "OnePlusUIShowcase",
            dependencies: ["OnePlusUI"]
        ),
        .testTarget(
            name: "OnePlusUITests",
            dependencies: ["OnePlusUI"]
        ),
    ]
)
