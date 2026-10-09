import Foundation
import HistodexCore
import LanguageModelChatUI
import ImageIO
import UIKit

/// StorageProvider is an in-memory projection of one archive page, never a second database.
final class ArchiveChatStorage: StorageProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var page: [ConversationMessage] = []
    private var pageTitle = "Histodex"
    func replace(messages: [ConversationMessage], title: String) {
        lock.lock(); defer { lock.unlock() }; page = messages; pageTitle = title
    }
    func messages(in conversationID: String) -> [ConversationMessage] {
        lock.lock(); defer { lock.unlock() }; return page.filter { $0.conversationID == conversationID }
    }
    func title(for id: String) -> String? { lock.lock(); defer { lock.unlock() }; return pageTitle }
    // Archive commands and inference are disabled in ChatViewController's read-only configuration.
    func createMessage(in conversationID: String, role: MessageRole) -> ConversationMessage {
        ConversationMessage(conversationID: conversationID, role: role)
    }
    func save(_ messages: [ConversationMessage]) {}
    func delete(_ messageIDs: [String]) {}
    func setTitle(_ title: String, for id: String) {}
}

@MainActor enum ArchiveChatProjection {
    static func messages(rows: [ArchiveReaderRow], conversationID: String, root: URL, targetOrdinal: Int? = nil) async -> [ConversationMessage] {
        var result: [ConversationMessage] = []
        for row in rows {
            guard !Task.isCancelled else { return [] }
            var parts: [ContentPart] = []
            let body = row.preview + (row.isTruncated ? "\n\n[Preview truncated — use Read Full Text in the message menu.]" : "")
            if row.author == .supporting {
                parts.append(.reasoning(.init(text: row.title + "\n\n" + body, isCollapsed: !(targetOrdinal.map(row.entry.contains) ?? false))))
            } else if !body.isEmpty { parts.append(.text(.init(text: body))) }
            for asset in row.entry.assets {
                let name = URL(fileURLWithPath: asset.sourceReference).lastPathComponent
                if let path = asset.relativePath, asset.mimeType.hasPrefix("image/") {
                    let url = root.appendingPathComponent(path)
                    let preview = await Task.detached(priority: .utility) { thumbnail(url) }.value
                    if let preview {
                        parts.append(.image(.init(mediaType: "image/png", data: preview, previewData: preview, name: name)))
                        continue
                    }
                }
                // Only bounded thumbnails enter the list. Original assets remain in the inspector.
                let description = asset.missingReason.map { "Unavailable attachment: \($0)" } ?? "\(asset.mimeType) · \(asset.byteSize) bytes · Open Message Details to inspect."
                parts.append(.file(.init(mediaType: asset.mimeType, data: Data(), textContent: description, name: asset.missingReason == nil ? name : "Unavailable: " + name)))
            }
            let date = ArchiveDates.date(row.entry.items[0].timestamp) ?? .distantPast
            result.append(ConversationMessage(id: row.id, conversationID: conversationID, role: row.author == .user ? .user : .assistant, parts: parts, createdAt: date, metadata: ["histodex.archive": "true", "histodex.title": row.title]))
        }
        return result
    }
    nonisolated private static func thumbnail(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 800] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }
}

@MainActor enum ArchiveDates {
    private static let iso = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = { let value = ISO8601DateFormatter(); value.formatOptions.insert(.withFractionalSeconds); return value }()
    static func date(_ value: String) -> Date? { fractional.date(from: value) ?? iso.date(from: value) }
    static func full(_ value: String) -> String { date(value)?.formatted(date: .abbreviated, time: .shortened) ?? value }
}
