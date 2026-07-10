// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Feather",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, testable logic: the note model and on-disk store.
        .target(name: "FeatherCore"),
        // Native app shell (AppKit + SwiftUI). Depends on the core.
        .executableTarget(
            name: "Feather",
            dependencies: ["FeatherCore"]
        ),
        .testTarget(
            name: "FeatherCoreTests",
            dependencies: ["FeatherCore"]
        ),
    ]
)
