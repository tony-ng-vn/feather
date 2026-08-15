import AppKit
import SwiftUI

/// SwiftUI wrapper around `MarkdownTextView`.
///
/// The card paints the paper, so every layer here is transparent and borderless.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let style: EditorStyle
    /// The current note's undo manager, so history survives tab switches (spec 3.5).
    let undoManager: UndoManager?
    /// Bumped by the host to pull first responder back to the editor.
    let focusPulse: Int
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(
            style: style,
            palette: EditorPalette.resolving(NSApplication.shared.effectiveAppearance)
        )
        textView.delegate = context.coordinator
        textView.noteUndoManager = undoManager
        textView.onEscape = onEscape
        textView.setText(text)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.text = $text
        textView.noteUndoManager = undoManager
        textView.onEscape = onEscape
        textView.setText(text)

        if context.coordinator.lastFocusPulse != focusPulse {
            context.coordinator.lastFocusPulse = focusPulse
            // After the current update, so the window has the view in its hierarchy.
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// Nil until the first update, which is what focuses the editor on appear.
        var lastFocusPulse: Int?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text.wrappedValue != textView.string { text.wrappedValue = textView.string }
        }

        /// Plain clicks edit the link text; Cmd-click opening lives in the text view.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            true
        }
    }
}
