import SwiftUI
import FeatherCore

/// The floating card: a tab strip of notes over a warm-paper text editor.
struct NoteCardView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var panelState: PanelState
    let sessions: EditorSessions
    var onEscape: () -> Void
    /// Called with the per-frame drag delta while the corner grip is dragged.
    var onResize: (CGFloat, CGFloat) -> Void

    @Environment(\.colorScheme) private var scheme
    /// Local mirror of the selected note's body, kept in sync both ways.
    @State private var text: String = ""
    @State private var lastResizeTranslation: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Rectangle()
                .fill(Theme.border(scheme))
                .frame(height: 1)
            editor
        }
        .background(Theme.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .onExitCommand(perform: onEscape) // Escape hides the panel
        .onAppear {
            syncFromStore()
            panelState.requestFocus()
        }
        .onChange(of: store.selectedID) { _ in
            syncFromStore()
            panelState.requestFocus()
        }
    }

    // MARK: Tab strip

    private var tabStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.notes) { note in
                        tab(for: note)
                    }
                }
                .padding(.vertical, 1)
            }
            Spacer(minLength: 2)
            iconButton("plus", help: "New note") { store.createNote() }
            iconButton("trash", help: "Delete this note") { store.deleteSelected() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func tab(for note: Note) -> some View {
        let active = note.id == store.selectedID
        return Button {
            store.select(id: note.id)
        } label: {
            Text(note.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 118)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundColor(active ? Theme.accentText(scheme) : Theme.muted(scheme))
                .background(active ? Theme.accent(scheme) : Color.clear)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        active ? Color.clear : Theme.border(scheme),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.muted(scheme))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Theme.border(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Jot anything...")
                    .font(.system(size: 16, design: .serif))
                    .foregroundColor(Theme.muted(scheme).opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
            MarkdownEditor(
                text: $text,
                style: .compact,
                undoManager: sessions.undoManager(for: store.selectedID),
                focusPulse: panelState.focusPulse,
                onEscape: onEscape
            )
            .onChange(of: text) { newValue in
                store.updateSelected(body: newValue)
            }
        }
        .background(Theme.paper(scheme))
    }

    private func syncFromStore() {
        text = store.selectedNote?.body ?? ""
    }

    // MARK: Resize grip

    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Theme.muted(scheme).opacity(0.5))
            .padding(8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let dx = value.translation.width - lastResizeTranslation.width
                        let dy = value.translation.height - lastResizeTranslation.height
                        lastResizeTranslation = value.translation
                        onResize(dx, dy)
                    }
                    .onEnded { _ in lastResizeTranslation = .zero }
            )
    }
}
