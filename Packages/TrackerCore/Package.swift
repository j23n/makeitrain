// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrackerCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "TrackerCore", targets: ["TrackerCore"]),
    ],
    targets: [
        .target(name: "TrackerCore"),
        .testTarget(name: "TrackerCoreTests", dependencies: ["TrackerCore"]),
    ]
)
