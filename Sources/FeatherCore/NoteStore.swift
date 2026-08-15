import Dispatch
import Foundation

/// Owns the notes and the current selection, and persists them through a `NoteRepository`.
///
/// Invariant: there is always at least one live (non-trashed) note, so there is
/// always a surface to type on.
public final class NoteStore: ObservableObject {
    // Full set, including trashed notes; `notes`/`liveNotes`/`trashedNotes` are views onto it.
    @Published private var allNotes: [Note]
    @Published public var selectedID: UUID?

    private let repository: NoteRepository
    private let debounce: TimeInterval
    private let now: () -> Date
    private var pendingSave: DispatchWorkItem?

    /// - Parameters:
    ///   - debounce: how long `updateSelected(body:)` waits before writing. 0 saves
    ///     immediately, which tests use for determinism.
    ///   - now: injectable clock, so trash-expiry tests don't need real sleeps.
    public init(repository: NoteRepository, debounce: TimeInterval = 0.3, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.debounce = debounce
        self.now = now

        let loaded = (try? repository.load()) ?? LoadedNotes(notes: [], selectedID: nil)
        self.allNotes = loaded.notes
        self.selectedID = loaded.selectedID

        if !allNotes.contains(where: { !$0.isTrashed }) {
            let seed = Note()
            allNotes.append(seed)
            selectedID = seed.id
            saveImmediately()
        } else if selectedID == nil || !allNotes.contains(where: { $0.id == selectedID && !$0.isTrashed }) {
            selectedID = allNotes.first(where: { !$0.isTrashed })?.id
        }
    }

    /// Convenience for the app and pre-existing tests. Debounce is 0 here (immediate,
    /// synchronous save on every change) to match the file-per-URL API's old behavior;
    /// callers that want coalesced saves should use `init(repository:debounce:now:)`.
    public convenience init(fileURL: URL? = nil) {
        let directory = fileURL?.deletingLastPathComponent() ?? NoteStore.defaultDirectory()
        self.init(repository: FileRepository(directory: directory), debounce: 0)
    }

    // MARK: - Views

    /// Non-trashed notes, in stored order. Kept as `notes` for source compatibility.
    public var notes: [Note] { liveNotes }
    public var liveNotes: [Note] { allNotes.filter { !$0.isTrashed } }
    public var trashedNotes: [Note] { allNotes.filter { $0.isTrashed } }

    /// Notes shown in the card's tab strip: quick notes plus anything pinned.
    public var cardNotes: [Note] { liveNotes.filter { $0.kind == .quick || $0.pinned } }

    /// Notes shown in the gallery: every live note.
    public var galleryNotes: [Note] { liveNotes }

    public var selectedNote: Note? {
        guard let id = selectedID else { return nil }
        return allNotes.first { $0.id == id }
    }

    // MARK: - Create / select / edit

    @discardableResult
    public func createNote() -> Note {
        let note = Note()
        allNotes.append(note)
        selectedID = note.id
        saveImmediately()
        return note
    }

    public func select(id: UUID) {
        guard allNotes.contains(where: { $0.id == id }) else { return }
        selectedID = id
        saveImmediately()
    }

    public func updateSelected(body: String) {
        guard let id = selectedID else { return }
        update(id: id, body: body)
    }

    /// Edits any note, selected or not, so a page window can write its own note
    /// without disturbing the card's selection.
    public func update(id: UUID, body: String) {
        guard let idx = allNotes.firstIndex(where: { $0.id == id }) else { return }
        guard allNotes[idx].body != body else { return } // avoid redundant writes on re-selection
        allNotes[idx].body = body
        allNotes[idx].updatedAt = now()
        scheduleSave()
    }

    // MARK: - Trash

    public func deleteSelected() {
        guard let id = selectedID else { return }
        delete(id: id)
    }

    /// Soft-delete: sets `deletedAt` and moves selection to a live neighbor. The file
    /// stays on disk (see spec section 7); `purge` is the hard delete.
    public func delete(id: UUID) {
        guard let idx = allNotes.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedID == id
        let livePosition = liveNotes.firstIndex(where: { $0.id == id })

        allNotes[idx].deletedAt = now()

        if wasSelected {
            let liveAfter = liveNotes
            if let pos = livePosition, !liveAfter.isEmpty {
                selectedID = liveAfter[min(pos, liveAfter.count - 1)].id
            } else {
                selectedID = liveAfter.first?.id
            }
        }
        ensureLiveNoteExists()
        saveImmediately()
    }

    public func restore(id: UUID) {
        guard let idx = allNotes.firstIndex(where: { $0.id == id }) else { return }
        allNotes[idx].deletedAt = nil
        saveImmediately()
    }

    /// Hard delete. Unlike `delete(id:)`, this removes the note and its file for good.
    public func purge(id: UUID) {
        guard let idx = allNotes.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedID == id
        allNotes.remove(at: idx)
        if wasSelected {
            selectedID = liveNotes.first?.id
        }
        ensureLiveNoteExists()
        saveImmediately()
    }

    /// Hard-deletes trashed notes older than `days`. Call periodically (spec: 30 days).
    public func purgeExpiredTrash(olderThan days: Int = 30) {
        let cutoff = now().addingTimeInterval(-Double(days) * 86400)
        let expiredIDs = Set(allNotes.filter { ($0.deletedAt).map { $0 < cutoff } ?? false }.map(\.id))
        guard !expiredIDs.isEmpty else { return }

        allNotes.removeAll { expiredIDs.contains($0.id) }
        if let id = selectedID, expiredIDs.contains(id) {
            selectedID = liveNotes.first?.id
        }
        ensureLiveNoteExists()
        saveImmediately()
    }

    // MARK: - Kind, pin, order

    public func promote(id: UUID) {
        guard let idx = allNotes.firstIndex(where: { $0.id == id }) else { return }
        allNotes[idx].kind = .note
        saveImmediately()
    }

    public func demote(id: UUID) {
        guard let idx = allNotes.firstIndex(where: { $0.id == id }) else { return }
        allNotes[idx].kind = .quick
        saveImmediately()
    }

    public func setPinned(_ pinned: Bool, id: UUID) {
        guard let idx = allNotes.firstIndex(where: { $0.id == id }) else { return }
        allNotes[idx].pinned = pinned
        saveImmediately()
    }

    /// Reorders the global note list; `toIndex` is clamped to a valid position.
    public func move(id: UUID, toIndex index: Int) {
        guard let currentIndex = allNotes.firstIndex(where: { $0.id == id }) else { return }
        let note = allNotes.remove(at: currentIndex)
        allNotes.insert(note, at: max(0, min(index, allNotes.count)))
        saveImmediately()
    }

    // MARK: - Search

    /// Case-insensitive substring match on title or body, over live notes only.
    /// Empty query returns every live note.
    public func search(_ query: String) -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return liveNotes }
        let needle = trimmed.lowercased()
        return liveNotes.filter {
            $0.title.lowercased().contains(needle) || $0.body.lowercased().contains(needle)
        }
    }

    // MARK: - Persistence

    private func ensureLiveNoteExists() {
        guard !allNotes.contains(where: { !$0.isTrashed }) else { return }
        let seed = Note()
        allNotes.append(seed)
        selectedID = seed.id
    }

    /// Cancels any pending debounced save and writes now. Structural changes
    /// (create, delete, restore, pin, promote, reorder, select) use this so they are
    /// never lost behind a stale debounce timer.
    private func saveImmediately() {
        pendingSave?.cancel()
        pendingSave = nil
        writeToRepository()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        guard debounce > 0 else {
            writeToRepository()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.writeToRepository()
            self?.pendingSave = nil
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// Performs any pending debounced save synchronously. Call on hide, window close,
    /// quit, and losing app focus (spec section 7).
    public func flush() {
        guard pendingSave != nil else { return }
        saveImmediately()
    }

    private func writeToRepository() {
        do {
            try repository.save(allNotes, selectedID: selectedID)
        } catch {
            NSLog("Feather: failed to save notes: \(error)")
        }
    }

    @available(*, deprecated, message: "use flush(); save() is kept for one release")
    public func save() {
        saveImmediately()
    }

    // MARK: - Locations

    public static func defaultDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Feather", isDirectory: true)
    }

    @available(*, deprecated, message: "notes now live under defaultDirectory()/notes; kept for one release")
    public static func defaultFileURL() -> URL {
        defaultDirectory().appendingPathComponent("notes.json")
    }
}
