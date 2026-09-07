import Foundation

/// Codex picker-style short head prompt, then meaningful full-history fallbacks.
/// Saved state/index titles are applied separately after normalization.
struct CodexTitleCandidates {
    var firstUser: String?
    var headUser: String?
    var headCommand: String?
    var firstAssistant: String?
    var firstTool: String?
    var value: String { headUser ?? headCommand ?? firstUser ?? firstAssistant ?? firstTool ?? "" }

    mutating func consider(_ item: ArchiveItem, record: Int) {
        if item.category == .conversation, item.kind == .message {
            guard let text = ConversationSemantics.title(item.text) else { return }
            if item.role == "user" {
                if firstUser == nil || ConversationSemantics.isGenericTitle(firstUser ?? "") { firstUser = text }
                if record <= 10, item.text.count <= 400, (headUser == nil || ConversationSemantics.isGenericTitle(headUser ?? "")) { headUser = text }
            } else if item.role == "assistant", firstAssistant == nil { firstAssistant = text }
        }
        if [.command, .toolCall].contains(item.kind) {
            if firstTool == nil, !item.toolName.isEmpty { firstTool = item.toolName }
            if record <= 10, item.kind == .command, headCommand == nil {
                headCommand = ConversationSemantics.title(TranscriptEntry.readableText(item))
            }
        }
    }
}
