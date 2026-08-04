// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SourceConflictKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "SourceConflictKit", targets: ["SourceConflictKit"]),
        .executable(name: "SourceConflictDemo", targets: ["SourceConflictDemo"])
    ],
    targets: [
        .target(
            name: "SourceConflictKit",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .executableTarget(
            name: "SourceConflictDemo",
            dependencies: ["SourceConflictKit"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "SourceConflictKitTests",
            dependencies: ["SourceConflictKit"]
        )
    ]
)
