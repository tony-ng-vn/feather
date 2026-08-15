import AppKit
import SwiftUI

/// Watches key-down events aimed at the window hosting it.
///
/// The switcher and the gallery need Return, Escape, and arrow handling, which
/// macOS 13 SwiftUI has no reliable declarative API for (`onKeyPress` is 14+).
/// A local monitor also runs before the editor's key equivalents, which is what
/// an open overlay wants.
struct KeyCatcher: NSViewRepresentable {
    /// Return true to swallow the event.
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        CatchingView(handler: handler)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatchingView)?.handler = handler
    }

    private final class CatchingView: NSView {
        var handler: (NSEvent) -> Bool
        private var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("KeyCatcher is created in code, not from a nib")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopWatching()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                return self.handler(event) ? nil : event
            }
        }

        deinit { stopWatching() }

        private func stopWatching() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
