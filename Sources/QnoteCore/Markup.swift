import Foundation

/// Pure, AppKit-free markdown analysis and editing logic.
///
/// Everything here operates on `String` and `String.Index` ranges so it can be
/// unit tested on Linux and driven later by a TextKit editor on macOS.
public enum Markup {}
