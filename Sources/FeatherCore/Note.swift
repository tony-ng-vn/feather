import Foundation

/// A single sticky note. Plain text only in v1.
public struct Note: Codable, Identifiable, Equatable {
    public let id: UUID
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Tab label: first non-empty line, markers and whitespace stripped. Falls back to "New note".
    public var title: String {
        Markup.title(of: body)
    }
}
