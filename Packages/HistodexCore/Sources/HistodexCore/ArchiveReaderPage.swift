import Foundation

/// A bounded, platform-independent handoff to the reused chat UI.
public struct ArchiveReaderRow: Identifiable, Sendable {
    public enum Author: Sendable { case user, assistant, supporting }
    public let entry: TranscriptEntry
    public var id: String { "archive.\(entry.id)" }
    public var ordinal: Int { entry.items[0].ordinal }
    public var author: Author {
        switch entry.style { case .outgoing: .user; case .incoming: .assistant; case .activity: .supporting }
    }
    public var title: String { entry.title }
    public var preview: String {
        String(entry.body.prefix(author == .user ? 1200 : author == .assistant ? 4500 : 12000))
    }
    public var isTruncated: Bool { preview.count < entry.body.count || entry.items.contains { $0.textLength > $0.text.count } }
    public init(entry: TranscriptEntry) { self.entry = entry }
}

public enum ArchiveReaderPage {
    public static func rows(_ items: [ArchiveItem]) -> [ArchiveReaderRow] {
        TranscriptEntry.project(items).map(ArchiveReaderRow.init)
    }
}
