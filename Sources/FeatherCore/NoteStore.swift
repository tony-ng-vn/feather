import Foundation
import Combine

/// Owns the notes and the current selection, and persists to disk.
///
/// Persistence uses an injectable file URL so tests write to a temp dir.
/// Invariant: there is always at least one note, so there is always a surface to type on.
public final class NoteStore: ObservableObject {
    @Published public private(set) var notes: [Note]
    @Published public var selectedID: UUID?

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? NoteStore.defaultFileURL()
        let loaded = NoteStore.load(from: self.fileURL)
        if let first = loaded.first {
            self.notes = loaded
            self.selectedID = first.id
        } else {
            let seed = Note()
            self.notes = [seed]
            self.selectedID = seed.id
        }
    }

    public var selectedNote: Note? {
        guard let id = selectedID else { return nil }
        return notes.first { $0.id == id }
    }

    @discardableResult
    public func createNote() -> Note {
        let note = Note()
        notes.append(note)
        selectedID = note.id
        save()
        return note
    }

    public func select(id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    public func updateSelected(body: String) {
        guard let id = selectedID,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[idx].body != body else { return } // avoid redundant writes on re-selection
        notes[idx].body = body
        notes[idx].updatedAt = Date()
        save()
    }

    public func deleteSelected() {
        guard let id = selectedID else { return }
        delete(id: id)
    }

    public func delete(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedID == id
        notes.remove(at: idx)

        if notes.isEmpty {
            let seed = Note()
            notes = [seed]
            selectedID = seed.id
        } else if wasSelected {
            let neighbor = min(idx, notes.count - 1)
            selectedID = notes[neighbor].id
        }
        save()
    }

    // MARK: - Persistence

    public func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Feather: failed to save notes: \(error)")
        }
    }

    private static func load(from url: URL) -> [Note] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Note].self, from: data)) ?? []
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Feather", isDirectory: true)
            .appendingPathComponent("notes.json")
    }
}
