import SwiftUI
import QnoteCore

/// Page chrome state, owned by `NoteWindow` so its key handling can reach it.
final class PageState: ObservableObject {
    /// Focus mode hides the chrome and turns on typewriter scrolling (spec 5).
    @Published var focusMode = false
    @Published var focusPulse = 0
    @Published var switcherOpen = false

    func requestFocus() {
        focusPulse &+= 1
    }
}

/// What a page asks the window controller to do on its behalf.
struct PageActions {
    var openGallery: () -> Void
    var openPage: (UUID) -> Void
    var close: () -> Void
}

/// A whole note, read and written comfortably: a paper sheet on a darker desk,
/// with quiet chrome above and below it.
struct PageView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var state: PageState
    let noteID: UUID
    let sessions: EditorSessions
    let problems: ProblemIndexProvider
    let actions: PageActions

    @Environment(\.colorScheme) private var scheme
    @State private var text: String = ""

    private var note: Note? { store.liveNotes.first { $0.id == noteID } }

    var body: some View {
        VStack(spacing: 0) {
            if !state.focusMode { header }
            sheet
            if !state.focusMode { footer }
        }
        .background(Theme.desk(scheme))
        .overlay { switcher }
        .onAppear {
            text = note?.body ?? ""
            state.requestFocus()
        }
        // The store debounces the write and the window controller flushes it when
        // this window closes.
        .onChange(of: text) { newValue in
            store.update(id: noteID, body: newValue)
        }
    }

    @ViewBuilder
    private var switcher: some View {
        if state.switcherOpen {
            QuickSwitcher(store: store) { note in
                state.switcherOpen = false
                actions.openPage(note.id)
            } onClose: {
                state.switcherOpen = false
                state.requestFocus()
            }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: actions.openGallery) {
                Label("Gallery", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.muted(scheme))
            }
            .buttonStyle(.plain)
            .help("Back to the gallery")
            .accessibilityLabel("Back to the gallery")
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
            problems: problems,
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
