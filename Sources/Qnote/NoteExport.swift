import AppKit
import UniformTypeIdentifiers
import QnoteCore

/// "Export as Markdown": the note's body, written wherever the user picks.
enum NoteExport {
    static func save(note: Note, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(for: note)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(note.body.utf8).write(to: url, options: .atomic)
            } catch {
                NSLog("Qnote: export failed: \(error)")
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            panel.begin(completionHandler: write)
        }
    }

    private static func fileName(for note: Note) -> String {
        let cleaned = note.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Note" : cleaned) + ".md"
    }
}
