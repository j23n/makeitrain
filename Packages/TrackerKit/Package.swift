// swift-tools-version: 6.0

import PackageDescription

/// In-app feedback in the builds run from Xcode (Debug), never in an archive.
let feedbackInDebugBuilds = SwiftSetting.define("FEEDBACK", .when(configuration: .debug))

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
        .library(name: "TimerActivity", targets: ["TimerActivity"]),
    ],
    dependencies: [
        .package(path: "../TrackerCore"),
        // In-app feedback (README.md, "Feedback"), compiled in only in Debug builds: the
        // FEEDBACK condition below. Pinned to a commit of j23n's own package.
        .package(url: "https://github.com/j23n/feedbackkit", revision: "1fb400a5bd8064749135a762a1c91c69578e0a48"),
    ],
    targets: [
        .target(
            name: "TrackerKit",
            dependencies: [.product(name: "TrackerCore", package: "TrackerCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The wide window's screens: the Mac's main window, and an iPad's
        // when it's wide.
        .target(
            name: "WideUI",
            dependencies: ["TrackerKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MacUI",
            dependencies: ["TrackerKit", "WideUI", .product(name: "FeedbackKit", package: "feedbackkit")],
            swiftSettings: [.swiftLanguageMode(.v5), feedbackInDebugBuilds]
        ),
        .target(
            name: "MobileUI",
            dependencies: [
                "TrackerKit", "TimerActivity", "WideUI", .product(name: "FeedbackKit", package: "feedbackkit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5), feedbackInDebugBuilds]
        ),
        // The Live Activity's attributes, which the iOS app and its widget
        // extension share.
        .target(
            name: "TimerActivity",
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
        .testTarget(
            name: "WideUITests",
            dependencies: ["WideUI", "TrackerKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
