import Foundation

/// Notes plus the selection, as read back from storage.
public struct LoadedNotes {
    public var notes: [Note]
    public var selectedID: UUID?

    public init(notes: [Note], selectedID: UUID?) {
        self.notes = notes
        self.selectedID = selectedID
    }
}

/// Where `NoteStore` reads and writes. Synchronous: `NoteStore` owns debouncing.
public protocol NoteRepository {
    func load() throws -> LoadedNotes
    func save(_ notes: [Note], selectedID: UUID?) throws
}

/// In-memory stand-in for tests. `saveCount` lets debounce tests assert coalescing.
public final class MemoryRepository: NoteRepository {
    public private(set) var saveCount = 0
    private var storedNotes: [Note]
    private var storedSelectedID: UUID?

    public init(notes: [Note] = [], selectedID: UUID? = nil) {
        self.storedNotes = notes
        self.storedSelectedID = selectedID
    }

    public func load() throws -> LoadedNotes {
        LoadedNotes(notes: storedNotes, selectedID: storedSelectedID)
    }

    public func save(_ notes: [Note], selectedID: UUID?) throws {
        storedNotes = notes
        storedSelectedID = selectedID
        saveCount += 1
    }
}

/// One markdown file per note under `directory/notes/`, plus an `index.json` for
/// everything that isn't the body text (kind, pin, order, dates).
///
/// Migration: if `directory/notes.json` (the old single-blob format) exists and
/// `notes/` does not, it is imported once and renamed to `notes.legacy.json`.
public final class FileRepository: NoteRepository {
    private let directory: URL
    private let notesDir: URL
    private let indexURL: URL
    private let legacyURL: URL
    private let legacyRenamedURL: URL

    // Tracks what we last wrote per note so unchanged bodies are not rewritten.
    private var writtenBodies: [UUID: String] = [:]

    private struct IndexEntry: Codable {
        var id: UUID
        var kind: NoteKind
        var pinned: Bool
        var order: Int
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
    }

    private struct IndexFile: Codable {
        var notes: [IndexEntry]
        var selectedID: UUID?
    }

    public init(directory: URL) {
        self.directory = directory
        self.notesDir = directory.appendingPathComponent("notes", isDirectory: true)
        self.indexURL = notesDir.appendingPathComponent("index.json")
        self.legacyURL = directory.appendingPathComponent("notes.json")
        self.legacyRenamedURL = directory.appendingPathComponent("notes.legacy.json")
    }

    public func load() throws -> LoadedNotes {
        try migrateLegacyIfNeeded()
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let filesOnDisk = try mdFilesOnDisk()
        guard let index = readIndex() else {
            return rebuildFromDisk(filesOnDisk)
        }

        var notes: [Note] = []
        for entry in index.notes.sorted(by: { $0.order < $1.order }) {
            // An index entry with no file behind it is stale; drop it.
            guard let fileURL = filesOnDisk[entry.id] else { continue }
            let body = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            writtenBodies[entry.id] = body
            notes.append(Note(
                id: entry.id,
                body: body,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                kind: entry.kind,
                pinned: entry.pinned,
                deletedAt: entry.deletedAt
            ))
        }

        // A file with no index entry (e.g. written out-of-band) is still a real note.
        let knownIDs = Set(notes.map { $0.id })
        for (id, fileURL) in filesOnDisk where !knownIDs.contains(id) {
            let body = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            writtenBodies[id] = body
            let date = modificationDate(of: fileURL)
            notes.append(Note(id: id, body: body, createdAt: date, updatedAt: date))
        }

        return LoadedNotes(notes: notes, selectedID: index.selectedID)
    }

    public func save(_ notes: [Note], selectedID: UUID?) throws {
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let currentIDs = Set(notes.map { $0.id })
        let existingFiles = (try? mdFilesOnDisk()) ?? [:]
        for (id, fileURL) in existingFiles where !currentIDs.contains(id) {
            try? FileManager.default.removeItem(at: fileURL)
            writtenBodies.removeValue(forKey: id)
        }

        for note in notes where writtenBodies[note.id] != note.body {
            let data = Data(note.body.utf8)
            try data.write(to: fileURL(for: note.id), options: .atomic)
            writtenBodies[note.id] = note.body
        }

        let entries = notes.enumerated().map { index, note in
            IndexEntry(
                id: note.id,
                kind: note.kind,
                pinned: note.pinned,
                order: index,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                deletedAt: note.deletedAt
            )
        }
        let indexData = try JSONEncoder().encode(IndexFile(notes: entries, selectedID: selectedID))
        try indexData.write(to: indexURL, options: .atomic)
    }

    // MARK: - Legacy migration

    private func migrateLegacyIfNeeded() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyURL.path), !fm.fileExists(atPath: notesDir.path) else { return }
        guard let data = try? Data(contentsOf: legacyURL),
              let legacyNotes = try? JSONDecoder().decode([Note].self, from: data) else {
            return // unreadable legacy file: leave it alone rather than lose it
        }

        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        for note in legacyNotes {
            writtenBodies[note.id] = note.body
            try Data(note.body.utf8).write(to: fileURL(for: note.id), options: .atomic)
        }
        let entries = legacyNotes.enumerated().map { index, note in
            IndexEntry(
                id: note.id,
                kind: note.kind,
                pinned: note.pinned,
                order: index,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                deletedAt: note.deletedAt
            )
        }
        let indexData = try JSONEncoder().encode(IndexFile(notes: entries, selectedID: legacyNotes.first?.id))
        try indexData.write(to: indexURL, options: .atomic)

        try fm.moveItem(at: legacyURL, to: legacyRenamedURL)
    }

    // MARK: - Helpers

    private func fileURL(for id: UUID) -> URL {
        notesDir.appendingPathComponent("\(id.uuidString).md")
    }

    private func mdFilesOnDisk() throws -> [UUID: URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: notesDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [:] }

        var map: [UUID: URL] = [:]
        for url in items where url.pathExtension == "md" {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) {
                map[id] = url
            }
        }
        return map
    }

    private func readIndex() -> IndexFile? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? JSONDecoder().decode(IndexFile.self, from: data)
    }

    private func rebuildFromDisk(_ files: [UUID: URL]) -> LoadedNotes {
        var notes: [Note] = []
        for (id, fileURL) in files {
            let body = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            writtenBodies[id] = body
            let date = modificationDate(of: fileURL)
            notes.append(Note(id: id, body: body, createdAt: date, updatedAt: date, kind: .quick))
        }
        notes.sort { $0.createdAt < $1.createdAt }
        return LoadedNotes(notes: notes, selectedID: notes.first?.id)
    }

    private func modificationDate(of url: URL) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date) ?? Date()
    }
}
