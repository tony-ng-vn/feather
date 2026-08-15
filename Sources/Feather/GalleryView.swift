import AppKit
import Carbon.HIToolbox
import SwiftUI
import FeatherCore

/// What the gallery asks the window controller to do.
struct GalleryActions {
    /// Opens a note as a page. The rect is the card's frame inside the gallery
    /// window, which the page uses as the start of its open animation.
    var openPage: (UUID, CGRect?) -> Void
    var newPage: () -> Void
    var close: () -> Void
}

/// Collects each card's frame so opening one can animate from where it sits.
private struct CardFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Browse everything: search, four sections of paper cards, keyboard-first.
struct GalleryView: View {
    @ObservedObject var store: NoteStore
    let actions: GalleryActions

    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var focusedID: UUID?
    @State private var cardFrames: [UUID: CGRect] = [:]

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    private var results: [Note] { store.search(query) }
    private var pinned: [Note] { results.filter { $0.pinned } }
    private var notes: [Note] { results.filter { !$0.pinned && $0.kind == .note } }
    private var quick: [Note] { results.filter { !$0.pinned && $0.kind == .quick } }
    /// Flat reading order, which is also the order Cmd-1..9 and the arrows follow.
    private var visible: [Note] { pinned + notes + quick }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Pinned", pinned)
                    section("Notes", notes)
                    section("Quick notes", quick)
                    trashSection
                    if visible.isEmpty {
                        Text("No notes match \"\(query)\".")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.muted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .background(Theme.paper(scheme))
        .background(KeyCatcher(handler: handleKey).frame(width: 0, height: 0))
        .onPreferenceChange(CardFrames.self) { cardFrames = $0 }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.muted(scheme))
            TextField("Search notes", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(Theme.ink(scheme))
                .accessibilityLabel("Search notes")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.codeBackground(scheme).opacity(0.6))
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 32) // clears the transparent titlebar
        .padding(.bottom, 12)
    }

    // MARK: Sections

    @ViewBuilder
    private func section(_ title: String, _ notes: [Note]) -> some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(title)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(notes) { note in card(for: note) }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(Theme.muted(scheme))
    }

    private func card(for note: Note) -> some View {
        GalleryCard(store: store, note: note, isFocused: focusedID == note.id) {
            open(id: note.id)
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: CardFrames.self, value: [note.id: proxy.frame(in: .global)])
        })
    }

    @ViewBuilder
    private var trashSection: some View {
        if !store.trashedNotes.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Empty Trash") { emptyTrash() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.trashedNotes) { note in trashCard(note) }
                    }
                }
                .padding(.top, 10)
            } label: {
                sectionTitle("Trash")
            }
            .tint(Theme.muted(scheme))
        }
    }

    private func trashCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.title)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundColor(Theme.muted(scheme))
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("Restore") { store.restore(id: note.id) }
                Button("Delete Forever") { store.purge(id: note.id) }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(height: 96, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 1)
        )
    }

    // MARK: Actions

    private func open(id: UUID) {
        focusedID = id
        // A quick note browsed from the gallery becomes a real note (spec 2).
        if store.liveNotes.first(where: { $0.id == id })?.kind == .quick {
            store.promote(id: id)
        }
        actions.openPage(id, cardFrames[id])
    }

    private func emptyTrash() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Empty the trash?"
        alert.informativeText = "\(store.trashedNotes.count) note(s) will be deleted for good."
        alert.addButton(withTitle: "Delete Forever")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for note in store.trashedNotes { store.purge(id: note.id) }
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        if let shortcut = Shortcut.match(event) { return handle(shortcut) }

        switch Int(event.keyCode) {
        case kVK_Escape:
            if query.isEmpty { actions.close() } else { query = "" }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let id = focusedID ?? visible.first?.id else { return false }
            open(id: id)
        case kVK_DownArrow:
            moveFocus(by: 1)
        case kVK_UpArrow:
            moveFocus(by: -1)
        case kVK_RightArrow where focusedID != nil:
            moveFocus(by: 1)
        case kVK_LeftArrow where focusedID != nil:
            moveFocus(by: -1)
        default:
            return false
        }
        return true
    }

    private func handle(_ shortcut: Shortcut) -> Bool {
        switch shortcut {
        case .newNote:
            actions.newPage()
        case .closeOrTrash:
            actions.close()
        case .pick(let index):
            guard index <= visible.count else { return true }
            open(id: visible[index - 1].id)
        case .trashNote:
            guard let id = focusedID else { return false }
            focusedID = nil
            store.delete(id: id)
        case .togglePin:
            guard let note = focused else { return false }
            store.setPinned(!note.pinned, id: note.id)
        case .toggleKeep:
            guard let note = focused else { return false }
            if note.kind == .quick { store.promote(id: note.id) } else { store.demote(id: note.id) }
        default:
            return false
        }
        return true
    }

    private var focused: Note? {
        guard let focusedID else { return nil }
        return visible.first { $0.id == focusedID }
    }

    /// Steps focus through the flat card order, starting at the first card.
    private func moveFocus(by delta: Int) {
        guard !visible.isEmpty else { return }
        guard let current = focusedID, let index = visible.firstIndex(where: { $0.id == current }) else {
            focusedID = visible.first?.id
            return
        }
        let next = min(max(index + delta, 0), visible.count - 1)
        focusedID = visible[next].id
    }
}
