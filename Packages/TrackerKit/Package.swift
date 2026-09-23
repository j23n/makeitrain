// swift-tools-version: 6.0

import PackageDescription

/// The app layer on Apple platforms: the shared app model, storage and iCloud
/// sync, and the screens for the Mac and iOS apps. The data model, file format
/// and rules live in TrackerCore.
let package = Package(
    name: "TrackerKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "TrackerKit", targets: ["TrackerKit"]),
        .library(name: "MacUI", targets: ["MacUI"]),
        .library(name: "MobileUI", targets: ["MobileUI"]),
    ],
    dependencies: [
        .package(path: "../TrackerCore"),
    ],
    targets: [
        .target(
            name: "TrackerKit",
            dependencies: [.product(name: "TrackerCore", package: "TrackerCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MacUI",
            dependencies: ["TrackerKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MobileUI",
            dependencies: ["TrackerKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TrackerKitTests",
            dependencies: ["TrackerKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacUITests",
            dependencies: ["MacUI", "TrackerKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
