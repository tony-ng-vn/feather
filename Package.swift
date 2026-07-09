// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TonyNote",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, testable logic: the note model and on-disk store.
        .target(name: "TonyNoteCore"),
        // Native app shell (AppKit + SwiftUI). Depends on the core.
        .executableTarget(
            name: "TonyNote",
            dependencies: ["TonyNoteCore"]
        ),
        .testTarget(
            name: "TonyNoteCoreTests",
            dependencies: ["TonyNoteCore"]
        ),
    ]
)
