import Foundation

/// Whether a note lives on the quick-capture card or has been promoted into the gallery.
public enum NoteKind: String, Codable {
    case quick
    case note
}

/// A single sticky note. Body is stored as markdown; styling is applied at render time.
public struct Note: Codable, Identifiable, Equatable {
    public let id: UUID
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date
    public var kind: NoteKind
    public var pinned: Bool
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        kind: NoteKind = .quick,
        pinned: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.pinned = pinned
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, body, createdAt, updatedAt, kind, pinned, deletedAt
    }

    // Legacy notes.json predates kind/pinned/deletedAt, so decode them as optional
    // and fall back to Note.init's defaults. Writing this init(from:) here (not in an
    // extension) still lets the compiler synthesize encode(to:) for us.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        kind = try container.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .quick
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    /// True once the note has been moved to trash.
    public var isTrashed: Bool { deletedAt != nil }

    /// Tab label: first non-empty line, markers and whitespace stripped. Falls back to "New note".
    public var title: String {
        Markup.title(of: body)
    }
}
