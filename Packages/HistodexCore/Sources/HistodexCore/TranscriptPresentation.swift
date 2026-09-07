import Foundation

/// A display projection of the archive, never a replacement for preserved records.
public struct TranscriptEntry: Identifiable, Sendable {
    public enum Style: Sendable { case outgoing, incoming, activity }
    public let items: [ArchiveItem]
    public var id: Int64 { items[0].id }
    public var style: Style {
        guard items.count == 1, items[0].kind == .message, items[0].category == .conversation else { return .activity }
        switch items[0].role { case "user": return .outgoing; case "assistant": return .incoming; default: return .activity }
    }
    public var title: String {
        if items.count > 1 { return "Session activity" }
        let item = items[0]
        if item.category == .context { return "Context and instructions" }
        switch item.kind {
        case .message: return item.role == "user" ? "You" : item.role == "assistant" ? "Codex" : "Instructions"
        case .reasoning: return "Reasoning"
        case .command: return "Command"
        case .commandOutput: return "Command output"
        case .toolCall: return Self.toolTitle(item.toolName, fallback: "Tool call")
        case .toolResult: return Self.toolTitle(item.toolName, fallback: "Tool result") + (item.toolName.isEmpty ? "" : " result")
        case .fileChange: return "File changes"
        case .image, .generatedImage: return item.kind == .generatedImage ? "Generated image" : "Image"
        case .systemEvent: return item.isDiagnostic ? "Archive notice" : "Session activity"
        case .unknown: return "Additional record"
        }
    }
    public var symbol: String {
        switch items[0].kind {
        case .command, .commandOutput: return "terminal"
        case .toolCall, .toolResult: return "wrench.and.screwdriver"
        case .fileChange: return "doc.text"
        case .reasoning: return "text.bubble"
        case .image, .generatedImage: return "photo"
        default: return items.contains(where: \.isDiagnostic) ? "exclamationmark.circle" : "info.circle"
        }
    }
    public var summary: String {
        if items.count > 1 { return "\(items.count) events" }
        let item = items[0]
        if item.kind == .systemEvent && !item.isDiagnostic { return Self.eventSummary(item) }
        if item.kind == .unknown { return "Preserved in your archive" }
        return String(Self.readableText(item).split(whereSeparator: \.isNewline).first?.prefix(180) ?? "")
    }
    public var body: String {
        items.map { item in
            let text = Self.readableText(item)
            return items.count == 1 ? text : Self.eventSummary(item) + "\n" + text
        }.joined(separator: "\n\n")
    }
    public var usesMonospacedText: Bool {
        ![.message, .reasoning, .image, .generatedImage].contains(items[0].kind)
    }
    public var assets: [ArchivedAsset] { items.flatMap(\.assets) }
    public func contains(ordinal: Int) -> Bool { items.contains { $0.ordinal == ordinal } }

    public static func project(_ items: [ArchiveItem]) -> [TranscriptEntry] {
        var rows: [TranscriptEntry] = []
        for item in items {
            let bookkeeping = item.kind == .systemEvent && !item.isDiagnostic && item.assets.isEmpty
            if bookkeeping, let last = rows.last, last.items.allSatisfy({ $0.kind == .systemEvent && !$0.isDiagnostic && $0.assets.isEmpty }),
               last.items[0].timestamp.prefix(10) == item.timestamp.prefix(10) {
                rows[rows.count - 1] = TranscriptEntry(items: last.items + [item])
            } else { rows.append(TranscriptEntry(items: [item])) }
        }
        return rows
    }
    public static func readableText(_ item: ArchiveItem) -> String {
        guard item.kind != .message && item.kind != .reasoning,
              let data = item.text.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return item.text }
        if item.kind == .command || item.kind == .toolCall {
            let command = value["cmd"].string.isEmpty ? value["command"] : value["cmd"]
            let text = command.string.isEmpty ? command.array.map(\.string).joined(separator: " ") : command.string
            if !text.isEmpty { return text }
        }
        if item.kind == .toolResult || item.kind == .commandOutput {
            for key in ["aggregated_output", "output", "stdout", "text"] where !value[key].string.isEmpty { return value[key].string }
            let text = value["content"].array.compactMap { v -> String? in let text = v["text"].string; return text.isEmpty ? nil : text }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        // Label normalized fields for humans; literal archived JSON remains in the detail view.
        if !value.object.isEmpty {
            return value.object.keys.sorted().filter { $0 != "type" }.map { key in
                let v = value[key]
                let label = key.replacingOccurrences(of: "_", with: " ").capitalized
                return label + ": " + (v.string.isEmpty ? v.pretty : v.string)
            }.joined(separator: "\n\n")
        }
        return item.text
    }
    private static func eventSummary(_ item: ArchiveItem) -> String {
        switch item.sourceType {
        case "session_meta": return "Session information"
        case "turn_context": return "Model and turn context"
        case "event_msg/token_count": return "Token usage"
        case "event_msg/task_started": return "Turn started"
        case "event_msg/task_complete": return "Turn completed"
        case "event_msg/thread_name_updated": return "Conversation renamed"
        case "event_msg/thread_settings_applied": return "Session settings"
        case "compacted", "event_msg/context_compacted": return "Context compacted"
        default: return item.isDiagnostic ? String(item.text.prefix(180)) : "Session event"
        }
    }
    private static func toolTitle(_ name: String, fallback: String) -> String {
        guard !name.isEmpty else { return fallback }
        return name.replacingOccurrences(of: "functions.", with: "").replacingOccurrences(of: "_", with: " ").capitalized
    }
}
