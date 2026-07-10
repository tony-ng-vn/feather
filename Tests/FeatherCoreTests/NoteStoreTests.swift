import XCTest
@testable import FeatherCore

final class NoteStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FeatherTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    // MARK: Note.title

    func testTitleFallsBackWhenEmpty() {
        XCTAssertEqual(Note(body: "").title, "New note")
        XCTAssertEqual(Note(body: "\n\n   \n").title, "New note")
    }

    func testTitleUsesFirstNonEmptyLine() {
        XCTAssertEqual(Note(body: "  groceries \nmilk\neggs").title, "groceries")
        XCTAssertEqual(Note(body: "\n\nproject kickoff\n").title, "project kickoff")
    }

    // MARK: NoteStore

    func testSeedsOneNoteWhenFileMissing() {
        let store = NoteStore(fileURL: tempURL())
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertNotNil(store.selectedID)
        XCTAssertEqual(store.selectedID, store.notes.first?.id)
    }

    func testCreateAppendsAndSelectsNewNote() {
        let store = NoteStore(fileURL: tempURL())
        let created = store.createNote()
        XCTAssertEqual(store.notes.count, 2)
        XCTAssertEqual(store.selectedID, created.id)
        XCTAssertEqual(store.notes.last?.id, created.id)
    }

    func testUpdatePersistsAcrossReload() {
        let url = tempURL()
        let store = NoteStore(fileURL: url)
        store.updateSelected(body: "buy milk")
        let reloaded = NoteStore(fileURL: url)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.body, "buy milk")
    }

    func testDeleteSelectsNeighbor() {
        let store = NoteStore(fileURL: tempURL())
        store.updateSelected(body: "one")
        let two = store.createNote(); store.updateSelected(body: "two")
        _ = store.createNote(); store.updateSelected(body: "three")

        store.select(id: two.id)
        store.deleteSelected()

        XCTAssertEqual(store.notes.count, 2)
        XCTAssertNotNil(store.selectedID)
        XCTAssertFalse(store.notes.contains { $0.id == two.id })
    }

    func testDeleteNeverLeavesZeroNotes() {
        let store = NoteStore(fileURL: tempURL())
        store.deleteSelected()
        store.deleteSelected()
        XCTAssertEqual(store.notes.count, 1, "must always keep a surface to type on")
        XCTAssertNotNil(store.selectedID)
    }
}
