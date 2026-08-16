// swift-tools-version:5.9
import PackageDescription

var targets: [Target] = [
    // Pure, testable logic: the note model and on-disk store. Builds on Linux too.
    .target(
        name: "QnoteCore",
        resources: [.copy("Resources/leetcode-problems.json")]
    ),
    .testTarget(
        name: "QnoteCoreTests",
        dependencies: ["QnoteCore"]
    ),
]

#if os(macOS)
// Native app shell (AppKit + SwiftUI). Depends on the core.
targets.append(.executableTarget(name: "Qnote", dependencies: ["QnoteCore"]))
#endif

let package = Package(
    name: "Qnote",
    platforms: [.macOS(.v13)],
    targets: targets
)
