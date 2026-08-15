import SwiftUI
import FeatherCore

/// One paper card in the gallery grid: title, up to three preview lines,
/// a kind dot, and a relative date.
struct GalleryCard: View {
    @ObservedObject var store: NoteStore
    let note: Note
    let isFocused: Bool
    var onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private var lifted: Bool { hovering && !Motion.isReduced }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundColor(Theme.ink(scheme))
                .lineLimit(1)

            ForEach(Array(GalleryCard.previewLines(of: note.body).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 13, design: .serif))
                    .foregroundColor(Theme.muted(scheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            footer
        }
        .padding(14)
        .frame(height: 148, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isFocused ? Theme.accent(scheme) : Theme.border(scheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(lifted ? 0.14 : 0), radius: lifted ? 8 : 0, y: lifted ? 3 : 0)
        .offset(y: lifted ? -2 : 0)
        .animation(Motion.isReduced ? nil : .easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu { menu }
        .accessibilityLabel(note.title)
        .accessibilityAddTraits(.isButton)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(note.kind == .note ? Theme.accent(scheme) : Theme.markerMuted(scheme))
                .frame(width: 6, height: 6)
                .accessibilityLabel(note.kind == .note ? "Note" : "Quick note")
            Text(RelativeDate.text(note.updatedAt))
                .font(.system(size: 11))
                .foregroundColor(Theme.muted(scheme))
                .lineLimit(1)
            Spacer(minLength: 0)
            if note.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.muted(scheme))
                    .accessibilityLabel("Pinned")
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open") { onOpen() }
        Button(note.pinned ? "Unpin" : "Pin") { store.setPinned(!note.pinned, id: note.id) }
        if note.kind == .quick {
            Button("Keep as Note") { store.promote(id: note.id) }
        } else {
            Button("Send to Card") { store.demote(id: note.id) }
        }
        Button("Export as Markdown") { NoteExport.save(note: note, in: NSApp.keyWindow) }
        Divider()
        Button("Move to Trash") { store.delete(id: note.id) }
    }

    /// The lines shown under the title: the first non-blank lines after the
    /// title line, with their markdown markers dropped.
    static func previewLines(of body: String, limit: Int = 3) -> [String] {
        var lines: [String] = []
        var passedTitle = false
        for line in Markup.lines(in: body) {
            let content = body[line.contentRange].trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            guard passedTitle else {
                passedTitle = true
                continue
            }
            lines.append(content)
            if lines.count == limit { break }
        }
        return lines
    }
}
