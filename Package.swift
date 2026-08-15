// swift-tools-version:5.9
import PackageDescription

var targets: [Target] = [
    // Pure, testable logic: the note model and on-disk store. Builds on Linux too.
    .target(name: "FeatherCore"),
    .testTarget(
        name: "FeatherCoreTests",
        dependencies: ["FeatherCore"]
    ),
]

#if os(macOS)
// Native app shell (AppKit + SwiftUI). Depends on the core.
targets.append(.executableTarget(name: "Feather", dependencies: ["FeatherCore"]))
#endif

let package = Package(
    name: "Feather",
    platforms: [.macOS(.v13)],
    targets: targets
)
