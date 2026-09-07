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
    /// Consume complete, line-aligned envelopes emitted by Codex. Quoted examples,
    /// incomplete tags, and ordinary prose mentioning these names remain messages.
    static func separateContext(_ text: String) -> (context: String, message: String) {
        var message = text; var contexts: [String] = []
        while true {
            let part = splitContextPass(message)
            guard !part.context.isEmpty, part.message.count < message.count else { break }
            contexts.append(part.context); message = part.message
        }
        return (contexts.joined(separator: "\n\n"), message)
    }

    private static func splitContextPass(_ text: String) -> (context: String, message: String) {
        if text.hasPrefix("# Context from my IDE setup:"), let request = text.range(of: "## My request for Codex:") {
            return (String(text[..<request.upperBound]), String(text[request.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard text.contains("<") else { return ("", text) }
        let tags = ["environment_context", "user_instructions", "turn_aborted", "permissions instructions", "collaboration_mode", "app-context", "skills_instructions", "multi_agent_role", "multi_agent_mode", "subagent_notification"]
        let names = tags.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = "(?im)^[ \t]*(?:# AGENTS\\.md instructions for [^\\n]*\\n[\\s\\S]*?<INSTRUCTIONS>[\\s\\S]*?</INSTRUCTIONS>|<(" + names + ")(?:[ \t][^>]*)?>[\\s\\S]*?</\\1>)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return ("", text) }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var context: [String] = []; var message = ""; var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            // Preserve fenced examples of protocol markup as authored conversation.
            var fence: Character?
            for line in text[..<range.lowerBound].split(separator: "\n", omittingEmptySubsequences: false) {
                let line = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("```") || line.hasPrefix("~~~") {
                    let marker = line.first!
                    if fence == marker { fence = nil } else if fence == nil { fence = marker }
                }
            }
            guard fence == nil else { continue }
            message += text[cursor..<range.lowerBound]; context.append(String(text[range]))
            cursor = range.upperBound
        }
        guard !context.isEmpty else { return ("", text) }
        message += text[cursor...]
        return (context.joined(separator: "\n\n"), message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func title(_ text: String) -> String? {
        let clean = separateContext(text).message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        // Extractive: use the actual request, never a tool result or generated summary.
        let lines = clean.split(whereSeparator: \.isNewline).map(String.init)
        let useful = lines.filter {
            let heading = $0.trimmingCharacters(in: CharacterSet(charactersIn: "# :\t"))
            return !heading.isEmpty && !["[Archived image]", "[Archived audio]", "My request for Codex", "User request", "Task"].contains(heading)
        }
        let plain = useful.joined(separator: " ").replacingOccurrences(of: #"^\s*(?:#{1,6}\s+|[-*]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
        let compact = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !compact.isEmpty, compact != "[Archived image]" else { return nil }
        return abbreviate(compact, limit: 512)
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
