import XCTest
@testable import QnoteCore

final class NoteStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("QnoteTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Trash

    func testDeleteMovesToTrashAndReselectsLiveNeighbor() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        let two = store.createNote()
        _ = store.createNote()

        store.select(id: two.id)
        store.deleteSelected()

        XCTAssertEqual(store.notes.count, 2, "trashed note is no longer live")
        XCTAssertEqual(store.trashedNotes.count, 1)
        XCTAssertEqual(store.trashedNotes.first?.id, two.id)
        XCTAssertNotEqual(store.selectedID, two.id)
    }

    func testDeleteOnlyLiveNoteSeedsAReplacement() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        let onlyID = store.selectedID
        store.deleteSelected()

        XCTAssertEqual(store.notes.count, 1, "must always keep a surface to type on")
        XCTAssertEqual(store.trashedNotes.count, 1)
        XCTAssertNotEqual(store.selectedID, onlyID)
    }

    func testRestoreBringsNoteBackToLive() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        let note = store.createNote()
        store.delete(id: note.id)
        XCTAssertTrue(store.trashedNotes.contains { $0.id == note.id })

        store.restore(id: note.id)

        XCTAssertTrue(store.notes.contains { $0.id == note.id })
        XCTAssertFalse(store.trashedNotes.contains { $0.id == note.id })
    }

    func testPurgeHardDeletesAndKeepsAtLeastOneLiveNote() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        let onlyID = store.selectedID!
        store.delete(id: onlyID) // trashes the only note; invariant seeds a live replacement

        store.purge(id: onlyID)

        XCTAssertFalse((store.notes + store.trashedNotes).contains { $0.id == onlyID })
        XCTAssertEqual(store.trashedNotes.count, 0)
        XCTAssertEqual(store.notes.count, 1, "must always keep a surface to type on")
    }

    func testPurgeExpiredTrashRemovesOnlyOldEntries() {
        var current = Date(timeIntervalSince1970: 1_000_000)
        let store = NoteStore(repository: MemoryRepository(), debounce: 0, now: { current })
        let old = store.createNote()
        let recent = store.createNote()

        store.delete(id: old.id)
        current = current.addingTimeInterval(40 * 86400) // 40 days later
        store.delete(id: recent.id)

        store.purgeExpiredTrash(olderThan: 30)

        XCTAssertFalse(store.trashedNotes.contains { $0.id == old.id })
        XCTAssertTrue(store.trashedNotes.contains { $0.id == recent.id })
    }

    // MARK: Kind, pin, search

    func testPromoteAndDemoteChangeKind() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        let note = store.createNote()
        XCTAssertEqual(note.kind, .quick)

        store.promote(id: note.id)
        XCTAssertEqual(store.notes.first { $0.id == note.id }?.kind, .note)

        store.demote(id: note.id)
        XCTAssertEqual(store.notes.first { $0.id == note.id }?.kind, .quick)
    }

    func testCardNotesIncludesQuickAndPinnedOnly() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        let quick = store.createNote()
        let promoted = store.createNote()
        store.promote(id: promoted.id)
        let pinnedNote = store.createNote()
        store.promote(id: pinnedNote.id)
        store.setPinned(true, id: pinnedNote.id)

        let cardIDs = Set(store.cardNotes.map(\.id))
        XCTAssertTrue(cardIDs.contains(quick.id))
        XCTAssertTrue(cardIDs.contains(pinnedNote.id), "pinned notes stay on the card even when promoted")
        XCTAssertFalse(cardIDs.contains(promoted.id))
    }

    func testSearchMatchesTitleOrBodyCaseInsensitively() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        store.updateSelected(body: "Groceries\nmilk and eggs")
        let other = store.createNote()
        store.select(id: other.id)
        store.updateSelected(body: "trip planning\nbook flights")

        XCTAssertEqual(store.search("grocer").count, 1)
        XCTAssertEqual(store.search("FLIGHTS").count, 1)
        XCTAssertEqual(store.search("").count, store.notes.count)
        XCTAssertEqual(store.search("nonexistent").count, 0)
    }

    // MARK: Update by id

    func testUpdateByIDEditsAnotherNoteWithoutChangingSelection() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        let first = store.notes[0]
        let second = store.createNote()

        store.update(id: first.id, body: "edited from a page")

        XCTAssertEqual(store.selectedID, second.id, "selection must stay where it was")
        XCTAssertEqual(store.notes.first { $0.id == first.id }?.body, "edited from a page")
    }

    func testUpdateByIDWithUnchangedBodyDoesNotSave() {
        let repository = MemoryRepository()
        let store = NoteStore(repository: repository, debounce: 0)
        let id = store.notes[0].id
        store.update(id: id, body: "same")
        let savesSoFar = repository.saveCount

        store.update(id: id, body: "same")

        XCTAssertEqual(repository.saveCount, savesSoFar)
    }

    func testUpdateByIDBumpsUpdatedAt() {
        let store = NoteStore(repository: MemoryRepository(), debounce: 0)
        let id = store.notes[0].id
        let before = store.notes[0].updatedAt

        store.update(id: id, body: "later")

        let after = store.notes.first { $0.id == id }?.updatedAt
        XCTAssertNotNil(after)
        XCTAssertGreaterThanOrEqual(after ?? before, before)
    }

    // MARK: Debounce and flush

    func testDebounceCoalescesRapidUpdatesIntoOneSave() {
        let repository = MemoryRepository()
        let store = NoteStore(repository: repository, debounce: 0.05)
        let savesAfterInit = repository.saveCount

        store.updateSelected(body: "a")
        store.updateSelected(body: "ab")
        store.updateSelected(body: "abc")

        let expectation = expectation(description: "debounced save fires once")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(repository.saveCount, savesAfterInit + 1)
        XCTAssertEqual(try? repository.load().notes.first?.body, "abc")
    }

    func testFlushWritesPendingSaveImmediately() {
        let repository = MemoryRepository()
        let store = NoteStore(repository: repository, debounce: 5)
        let savesAfterInit = repository.saveCount

        store.updateSelected(body: "not yet on disk")
        XCTAssertEqual(repository.saveCount, savesAfterInit, "debounced save should not have fired yet")

        store.flush()

        XCTAssertEqual(repository.saveCount, savesAfterInit + 1)
        XCTAssertEqual(try? repository.load().notes.first?.body, "not yet on disk")
    }
}
