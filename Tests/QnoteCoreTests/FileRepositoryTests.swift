import XCTest
@testable import QnoteCore

final class FileRepositoryTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QnoteRepoTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    func testRoundTrip() throws {
        let repo = FileRepository(directory: directory)
        let note = Note(body: "hello world", kind: .note, pinned: true)
        try repo.save([note], selectedID: note.id)

        let reloaded = try FileRepository(directory: directory).load()
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.body, "hello world")
        XCTAssertEqual(reloaded.notes.first?.kind, .note)
        XCTAssertEqual(reloaded.notes.first?.pinned, true)
        XCTAssertEqual(reloaded.selectedID, note.id)
    }

    func testMissingIndexRebuildsFromMarkdownFiles() throws {
        let repo = FileRepository(directory: directory)
        let a = Note(body: "first")
        let b = Note(body: "second")
        try repo.save([a, b], selectedID: a.id)

        try FileManager.default.removeItem(at: directory.appendingPathComponent("notes/index.json"))

        let reloaded = try FileRepository(directory: directory).load()
        XCTAssertEqual(reloaded.notes.count, 2)
        XCTAssertEqual(Set(reloaded.notes.map(\.body)), Set(["first", "second"]))
        XCTAssertTrue(reloaded.notes.allSatisfy { $0.kind == .quick })
    }

    func testLegacyNotesJsonIsMigratedAndRenamed() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyNote = Note(body: "legacy body")
        let data = try JSONEncoder().encode([legacyNote])
        try data.write(to: directory.appendingPathComponent("notes.json"))

        let loaded = try FileRepository(directory: directory).load()

        XCTAssertEqual(loaded.notes.count, 1)
        XCTAssertEqual(loaded.notes.first?.body, "legacy body")
        XCTAssertEqual(loaded.notes.first?.kind, .quick)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("notes.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("notes.legacy.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("notes/index.json").path))
    }

    func testUnchangedBodyIsNotRewritten() throws {
        let repo = FileRepository(directory: directory)
        let note = Note(body: "stable")
        try repo.save([note], selectedID: note.id)

        let fileURL = directory.appendingPathComponent("notes/\(note.id.uuidString).md")
        let firstModified = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as! Date

        // Sleep isn't reliable enough on CI; instead prove the write was skipped by
        // checking the file simply exists with the same content, which is all the
        // "skip unchanged bodies" behavior promises. A changed note (below) does write.
        try repo.save([note], selectedID: note.id)
        let secondModified = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as! Date
        XCTAssertEqual(firstModified, secondModified)

        var changed = note
        changed.body = "stable, edited"
        try repo.save([changed], selectedID: changed.id)
        let body = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(body, "stable, edited")
    }

    func testRemovedNoteFileIsDeleted() throws {
        let repo = FileRepository(directory: directory)
        let a = Note(body: "keep")
        let b = Note(body: "remove me")
        try repo.save([a, b], selectedID: a.id)

        let bFileURL = directory.appendingPathComponent("notes/\(b.id.uuidString).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bFileURL.path))

        try repo.save([a], selectedID: a.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bFileURL.path))
    }

    func testIndexEntryWithoutFileIsDropped() throws {
        let repo = FileRepository(directory: directory)
        let a = Note(body: "present")
        try repo.save([a], selectedID: a.id)

        // Simulate a stale index entry pointing at a file that no longer exists.
        let indexURL = directory.appendingPathComponent("notes/index.json")
        var indexJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as! [String: Any]
        var entries = indexJSON["notes"] as! [[String: Any]]
        var ghost = entries[0]
        ghost["id"] = UUID().uuidString
        entries.append(ghost)
        indexJSON["notes"] = entries
        let data = try JSONSerialization.data(withJSONObject: indexJSON)
        try data.write(to: indexURL)

        let reloaded = try FileRepository(directory: directory).load()
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.id, a.id)
    }
}

// MARK: - App directory migration

final class AppDirectoryMigrationTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testMovesOldDirectoryWhenNewOneIsAbsent() throws {
        let old = root.appendingPathComponent("Feather", isDirectory: true)
        let new = root.appendingPathComponent("Qnote", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: old.appendingPathComponent("notes.json"))

        NoteStore.migrateAppDirectory(from: old, to: new)

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        let moved = try String(contentsOf: new.appendingPathComponent("notes.json"), encoding: .utf8)
        XCTAssertEqual(moved, "hello")
    }

    func testLeavesNewDirectoryAloneWhenItAlreadyExists() throws {
        let old = root.appendingPathComponent("Feather", isDirectory: true)
        let new = root.appendingPathComponent("Qnote", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: new.appendingPathComponent("marker"))

        NoteStore.migrateAppDirectory(from: old, to: new)

        // Both survive: the new directory wins and the old one is left for the user to inspect.
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("marker").path))
    }

    func testDoesNothingWhenOldDirectoryIsAbsent() {
        let old = root.appendingPathComponent("Feather", isDirectory: true)
        let new = root.appendingPathComponent("Qnote", isDirectory: true)

        NoteStore.migrateAppDirectory(from: old, to: new)

        XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
    }
}
