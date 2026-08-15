import AppKit
import Carbon.HIToolbox
import SwiftUI
import FeatherCore

/// Cmd-P: jump to any note without leaving the keyboard. Shown as an overlay
/// inside whichever surface opened it (spec section 6).
struct QuickSwitcher: View {
    @ObservedObject var store: NoteStore
    var onOpen: (Note) -> Void
    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var results: [Note] { Array(store.search(query).prefix(12)) }

    var body: some View {
        VStack(spacing: 0) {
            field
            if !results.isEmpty {
                Rectangle().fill(Theme.border(scheme)).frame(height: 1)
                list
            }
        }
        .frame(maxWidth: 420)
        .background(Theme.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 6)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(scrim)
        .background(KeyCatcher(handler: handleKey).frame(width: 0, height: 0))
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _ in selection = 0 }
    }

    private var scrim: some View {
        Color.black.opacity(0.16)
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .accessibilityHidden(true)
    }

    private var field: some View {
        TextField("Jump to a note", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(Theme.ink(scheme))
            .focused($fieldFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityLabel("Jump to a note")
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, note in
                    row(note, at: index)
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private func row(_ note: Note, at index: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(note.kind == .note ? Theme.accent(scheme) : Theme.markerMuted(scheme))
                .frame(width: 5, height: 5)
                .accessibilityLabel(note.kind == .note ? "Note" : "Quick note")
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.ink(scheme))
                    .lineLimit(1)
                if let preview = GalleryCard.previewLines(of: note.body, limit: 1).first {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted(scheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(RelativeDate.text(note.updatedAt))
                .font(.system(size: 10))
                .foregroundColor(Theme.muted(scheme))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(index == selection ? Theme.codeBackground(scheme) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { open(at: index) }
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        if let shortcut = Shortcut.match(event) {
            // Cmd-1..9 pick a row; every other Command key belongs to the surface.
            guard case .pick(let position) = shortcut else { return false }
            open(at: position - 1)
            return true
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            onClose()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            open(at: selection)
        case kVK_DownArrow:
            selection = min(selection + 1, max(results.count - 1, 0))
        case kVK_UpArrow:
            selection = max(selection - 1, 0)
        default:
            return false
        }
        return true
    }

    private func open(at index: Int) {
        guard results.indices.contains(index) else { return }
        onOpen(results[index])
    }
}
