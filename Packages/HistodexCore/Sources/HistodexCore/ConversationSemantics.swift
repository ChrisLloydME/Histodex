import Foundation

/// Source roles describe model input, not authorship. Keep injected context and
/// execution records distinct from the user/assistant exchange throughout storage.
public enum RecordCategory: String, Codable, Sendable {
    case conversation, activity, context, metadata, unknown
}

public enum ArchiveScope: Sendable {
    case conversation, allRecords
    var predicate: String { self == .conversation ? "category='conversation'" : "1" }
}

enum ConversationSemantics {
    /// Only consume complete, leading envelopes emitted by Codex. Quoted examples,
    /// incomplete tags, and ordinary prose mentioning these names remain messages.
    static func separateContext(_ text: String) -> (context: String, message: String) {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        while !rest.isEmpty {
            var closing: String?
            if rest.hasPrefix("# AGENTS.md instructions for "),
               let opening = rest.range(of: "<INSTRUCTIONS>"),
               !rest[..<opening.lowerBound].contains("\n\n# ") {
                closing = "</INSTRUCTIONS>"
            } else {
                for tag in ["environment_context", "user_instructions", "turn_aborted", "permissions instructions", "collaboration_mode", "app-context", "skills_instructions", "multi_agent_role", "multi_agent_mode", "subagent_notification"] {
                    if rest.hasPrefix("<\(tag)>") { closing = "</\(tag)>"; break }
                }
            }
            guard let closing, let end = rest.range(of: closing) else { break }
            parts.append(String(rest[..<end.upperBound]))
            rest = String(rest[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (parts.joined(separator: "\n\n"), parts.isEmpty ? text : rest)
    }

    static func title(_ text: String) -> String? {
        let clean = separateContext(text).message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        // Extractive: use the actual request, never a tool result or generated summary.
        let lines = clean.split(whereSeparator: \.isNewline).map(String.init)
        let line = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? clean
        let plain = line.replacingOccurrences(of: #"^\s*(?:#{1,6}\s+|[-*]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
        let compact = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !compact.isEmpty, compact != "[Archived image]" else { return nil }
        return abbreviate(compact)
    }

    static func explicitTitle(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, separateContext(value).context.isEmpty else { return nil }
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func abbreviate(_ text: String, limit: Int = 120) -> String {
        guard text.count > limit else { return text }
        let prefix = String(text.prefix(limit - 1))
        if let space = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: space) > limit / 2 {
            return String(prefix[..<space]) + "…"
        }
        return prefix + "…"
    }

    static func isGenericTitle(_ title: String) -> Bool {
        ["continue", "continue.", "yes", "yes.", "ok", "okay", "go ahead", "please continue"].contains(title.lowercased())
    }
}
