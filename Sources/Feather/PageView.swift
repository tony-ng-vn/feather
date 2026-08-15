import SwiftUI
import FeatherCore

/// Page chrome state, owned by `NoteWindow` so its key handling can reach it.
final class PageState: ObservableObject {
    /// Focus mode hides the chrome and turns on typewriter scrolling (spec 5).
    @Published var focusMode = false
    @Published var focusPulse = 0

    func requestFocus() {
        focusPulse &+= 1
    }
}

/// What a page asks the window controller to do on its behalf.
struct PageActions {
    var close: () -> Void
}

/// A whole note, read and written comfortably: a paper sheet on a darker desk,
/// with quiet chrome above and below it.
struct PageView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var state: PageState
    let noteID: UUID
    let sessions: EditorSessions
    let actions: PageActions

    @Environment(\.colorScheme) private var scheme
    @State private var text: String = ""
    @State private var writer = BodyWriter()

    private var note: Note? { store.liveNotes.first { $0.id == noteID } }

    var body: some View {
        VStack(spacing: 0) {
            if !state.focusMode { header }
            sheet
            if !state.focusMode { footer }
        }
        .background(Theme.desk(scheme))
        .onAppear {
            text = note?.body ?? ""
            state.requestFocus()
        }
        .onChange(of: text) { newValue in
            writer.schedule(body: newValue, id: noteID, store: store)
        }
        .onDisappear { writer.flush(store: store) }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            iconButton(
                note?.pinned == true ? "pin.fill" : "pin",
                label: note?.pinned == true ? "Unpin note" : "Pin note"
            ) {
                store.setPinned(!(note?.pinned ?? false), id: noteID)
            }
            overflowMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var overflowMenu: some View {
        Menu {
            Button("Export as Markdown") {
                guard let note else { return }
                NoteExport.save(note: note, in: NSApp.keyWindow)
            }
            Button("Send to Card") { sendToCard() }
            Button("Move to Trash") { store.delete(id: noteID) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.muted(scheme))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 28)
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    private var footer: some View {
        HStack {
            Text("\(wordCount) words")
            Spacer(minLength: 8)
            if let note { Text("Edited \(RelativeDate.text(note.updatedAt))") }
        }
        .font(.system(size: 11))
        .foregroundColor(Theme.muted(scheme))
        .padding(.horizontal, 26)
        .padding(.bottom, 10)
        .padding(.top, 6)
    }

    // MARK: Sheet

    private var sheet: some View {
        MarkdownEditor(
            text: $text,
            style: .page,
            undoManager: sessions.undoManager(for: noteID),
            focusPulse: state.focusPulse,
            keepsCaretCentered: state.focusMode,
            onEscape: { state.focusMode = false }
        )
        .background(Theme.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 1)
        )
        .padding(.horizontal, state.focusMode ? 0 : 18)
        .padding(.bottom, state.focusMode ? 0 : 4)
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func sendToCard() {
        store.demote(id: noteID)
        actions.close()
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.muted(scheme))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Coalesces page edits before they reach the store.
///
/// `NoteStore` writes through the current selection, which belongs to the card,
/// so a page edit is a short transaction: select this note, write it, hand the
/// selection straight back. Debouncing keeps that to once per pause in typing.
final class BodyWriter {
    private var pending: (body: String, id: UUID)?
    private var timer: DispatchWorkItem?

    func schedule(body: String, id: UUID, store: NoteStore, debounce: TimeInterval = 0.4) {
        pending = (body, id)
        timer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush(store: store) }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// Writes any pending edit now. Called when the page goes away.
    func flush(store: NoteStore) {
        timer?.cancel()
        timer = nil
        guard let pending else { return }
        self.pending = nil

        let previous = store.selectedID
        store.select(id: pending.id)
        store.updateSelected(body: pending.body)
        if let previous, previous != pending.id { store.select(id: previous) }
        store.flush()
    }
}
