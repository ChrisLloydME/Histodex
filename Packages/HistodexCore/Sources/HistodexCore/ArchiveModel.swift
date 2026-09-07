import Foundation

public enum ItemKind: String, Codable, Sendable {
    case message, reasoning, command, commandOutput, toolCall, toolResult, fileChange
    case image, generatedImage, systemEvent, unknown
}

public struct Conversation: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let project: String
    public let startedAt: String
    public let updatedAt: String
    public let itemCount: Int
    public let snapshotID: String
    public let warningCount: Int
    public let preview: String
}

public struct ArchiveItem: Identifiable, Sendable {
    public var id: Int64 = 0
    public var conversationID: String = ""
    public var ordinal: Int = 0
    public var kind: ItemKind = .unknown
    public var category: RecordCategory = .unknown
    /// Adapter-only split of injected context from a mixed user input record.
    var contextText: String = ""
    var unsupportedText: String = ""
    public var messageID: String = ""
    public var channel: String = ""
    public var isDelta: Bool = false
    public var role: String = ""
    public var text: String = ""
    public var textLength: Int = 0
    public var timestamp: String = ""
    public var turnID: String = ""
    public var toolName: String = ""
    public var callID: String = ""
    public var sourceType: String = ""
    public var rawOffset: Int64 = 0
    public var rawLength: Int64 = 0
    public var rawPath: String = ""
    public var isDiagnostic: Bool = false
    public var assets: [ArchivedAsset] = []
    public init() {}
}

public struct ArchivedAsset: Sendable {
    public let hash: String?
    public let relativePath: String?
    public let mimeType: String
    public let byteSize: Int64
    public let width: Int?
    public let height: Int?
    public let sourceReference: String
    public let missingReason: String?
}

public struct SearchHit: Identifiable, Sendable {
    public let id: Int64
    public let conversationID: String
    public let title: String
    public let ordinal: Int
    public let snippet: String
}

public struct ImportProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let filename: String
    public var phase: String = "Indexing"
    public var processedBytes: Int64 = 0
    public var totalBytes: Int64 = 0
    public init(completed: Int, total: Int, filename: String, phase: String = "Indexing", processedBytes: Int64 = 0, totalBytes: Int64 = 0) {
        self.completed = completed; self.total = total; self.filename = filename; self.phase = phase
        self.processedBytes = processedBytes; self.totalBytes = totalBytes
    }
    public var fraction: Double? {
        guard total > 0 else { return nil }
        let fileFraction = totalBytes > 0 ? min(1, Double(processedBytes) / Double(totalBytes)) : 0
        return min(1, (Double(completed) + fileFraction) / Double(total))
    }
    public var description: String {
        let count = total > 0 ? " · \(min(completed + 1, total)) of \(total)" : ""
        let bytes = totalBytes > 0 ? " · \(ByteCountFormatter.string(fromByteCount: processedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))" : ""
        return phase + count + bytes + (filename.isEmpty ? "" : "\n" + URL(fileURLWithPath: filename).lastPathComponent)
    }
}

public struct ImportReport: Sendable {
    public var imported = 0
    public var unchanged = 0
    public var errors: [String] = []
    public init() {}
}

public enum ArchiveError: LocalizedError {
    case invalidSource(String), truncatedSource, corruptCompression(String), invalidArchive(String)
    public var errorDescription: String? {
        switch self {
        case .invalidSource(let s), .corruptCompression(let s), .invalidArchive(let s): return s
        case .truncatedSource: return "The source became shorter during snapshotting. Retry the import."
        }
    }
}

/// Open-ended JSON representation. Unknown fields never invalidate the envelope.
public enum JSONValue: Codable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .number(try c.decode(Double.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    public var string: String { if case .string(let v) = self { return v }; return "" }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    public var integer: Int64? { if case .number(let v) = self, v.isFinite, v >= 0, v < Double(Int64.max) { return Int64(v) }; return nil }
    public var pretty: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: e.encode(self), as: UTF8.self)) ?? ""
    }
}
