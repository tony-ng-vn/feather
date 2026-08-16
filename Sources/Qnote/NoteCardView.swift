import SwiftUI
import QnoteCore

/// What the card asks the window controller to do.
struct CardActions {
    var hide: () -> Void
    /// Called with the per-frame drag delta while the corner grip is dragged.
    var resize: (CGFloat, CGFloat) -> Void
    var newNote: () -> Void
    var trashNote: () -> Void
    var openGallery: () -> Void
    var openPage: (UUID) -> Void
}

/// The floating card: a tab strip of quick and pinned notes over a warm-paper editor.
struct NoteCardView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var panelState: PanelState
    let sessions: EditorSessions
    let problems: ProblemIndexProvider
    let actions: CardActions

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
        .overlay { switcher }
        .overlay(alignment: .bottom) { pillOverlay }
        // Driven from here, so the pill's insertion and removal both animate.
        .animation(Motion.isReduced ? nil : .easeOut(duration: 0.18), value: panelState.pill?.id)
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .onExitCommand(perform: actions.hide) // Escape hides the panel
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
                    // Quick notes plus anything pinned, so the strip stays small
                    // however big the library grows (spec 2).
                    ForEach(store.cardNotes) { note in
                        tab(for: note)
                    }
                }
                .padding(.vertical, 1)
            }
            Spacer(minLength: 2)
            iconButton("square.grid.2x2", label: "Open gallery", action: actions.openGallery)
            iconButton("plus", label: "New note", action: actions.newNote)
            iconButton("trash", label: "Move note to trash", action: actions.trashNote)
            iconButton("xmark", label: "Hide", action: actions.hide)
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

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.muted(scheme))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Theme.border(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
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
                problems: problems,
                onEscape: actions.hide
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

    // MARK: Quick switcher

    @ViewBuilder
    private var switcher: some View {
        if panelState.switcherOpen {
            QuickSwitcher(store: store) { note in
                panelState.switcherOpen = false
                // In the strip: just switch tabs. Anywhere else: open its page.
                if store.cardNotes.contains(where: { $0.id == note.id }) {
                    store.select(id: note.id)
                    panelState.requestFocus()
                } else {
                    actions.openPage(note.id)
                }
            } onClose: {
                panelState.switcherOpen = false
                panelState.requestFocus()
            }
        }
    }

    // MARK: Undo pill

    @ViewBuilder
    private var pillOverlay: some View {
        if let pill = panelState.pill {
            HStack(spacing: 10) {
                Text(pill.text)
                Button(pill.actionTitle) {
                    pill.action()
                    panelState.dismissPill()
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.link(scheme))
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.ink(scheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.codeBackground(scheme))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.border(scheme), lineWidth: 1))
            .padding(.bottom, 14)
            .transition(Motion.isReduced ? .identity : .opacity)
        }
    }

    // MARK: Resize grip

    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Theme.muted(scheme).opacity(0.5))
            .padding(8)
            .contentShape(Rectangle())
            .accessibilityLabel("Resize card")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let dx = value.translation.width - lastResizeTranslation.width
                        let dy = value.translation.height - lastResizeTranslation.height
                        lastResizeTranslation = value.translation
                        actions.resize(dx, dy)
                    }
                    .onEnded { _ in lastResizeTranslation = .zero }
            )
    }
}
