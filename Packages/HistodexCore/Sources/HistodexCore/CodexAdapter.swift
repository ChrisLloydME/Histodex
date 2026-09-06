import Foundation

struct SessionMetadata {
    var sourceID = ""
    var title = ""
    var project = ""
    var startedAt = ""
    var updatedAt = ""
    var parentRolloutID = ""
    var parentEndOrdinal: Int64?
    var parentEndByte: Int64?
}

struct CodexAdapter {
    static let version = 1
    var metadata = SessionMetadata()
    var turnID = ""

    mutating func normalize(_ line: RawLine, rawPath: String, assetStore: AssetStore) -> ArchiveItem {
        var item = ArchiveItem()
        item.rawOffset = line.offset; item.rawLength = line.length; item.rawPath = rawPath
        guard let data = line.data else {
            item.text = "Record exceeds the 32 MiB parsing limit. Its complete bytes are preserved in the raw snapshot."
            item.sourceType = "oversized"; item.isDiagnostic = true; return item
        }
        guard let raw = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = raw else {
            item.text = "\(line.terminated ? "Malformed JSON record" : "Partially written final record"). Original bytes are preserved.\n" + String(decoding: data.prefix(4096), as: UTF8.self)
            item.sourceType = "malformed"; item.isDiagnostic = true; return item
        }
        let type = raw["type"].string, p = raw["payload"], subtype = p["type"].string
        item.sourceType = type + (subtype.isEmpty ? "" : "/" + subtype)
        item.timestamp = raw["timestamp"].string
        if !item.timestamp.isEmpty { metadata.updatedAt = item.timestamp }
        if !p["turn_id"].string.isEmpty { turnID = p["turn_id"].string }
        item.turnID = turnID; item.callID = p["call_id"].string
        item.assets = assetStore.extract(from: p, cwd: metadata.project)
        let clean = p.withoutImageBodies
        func content(_ value: JSONValue) -> String {
            if case .string(let s) = value {
                if let d = s.data(using: .utf8), let j = try? JSONDecoder().decode(JSONValue.self, from: d) { return j.withoutImageBodies.pretty }
                return s.hasPrefix("data:image/") ? "[Archived image]" : s
            }
            if case .array(let a) = value {
                return a.map { v in
                    if !v["text"].string.isEmpty { return v["text"].string }
                    if ["input_image", "image", "image_url"].contains(v["type"].string) { return "[Archived image]" }
                    return v.withoutImageBodies.pretty
                }.joined(separator: "\n")
            }
            if case .null = value { return "" }
            return value.withoutImageBodies.pretty
        }
        switch type {
        case "session_meta":
            if metadata.sourceID.isEmpty {
                metadata.sourceID = p["id"].string; metadata.project = p["cwd"].string
                metadata.startedAt = p["timestamp"].string.isEmpty ? item.timestamp : p["timestamp"].string
                metadata.parentRolloutID = p["history_base"]["thread_id"].string
                metadata.parentEndOrdinal = p["history_base"]["end_ordinal_exclusive"].integer
                metadata.parentEndByte = p["history_base"]["end_byte_offset"].integer
            }
            item.kind = .systemEvent; item.text = "Session metadata · Codex \(p["cli_version"].string)\n\(p["cwd"].string)"
        case "turn_context":
            item.kind = .systemEvent; item.text = "Turn context · \(p["model"].string)\n\(p["cwd"].string)"
        case "compacted":
            item.kind = .systemEvent; item.text = "Context compacted\n" + p["message"].string
            if !p["replacement_history"].array.isEmpty { item.text += "\nReplacement model context is preserved in the raw record." }
        case "response_item":
            switch subtype {
            case "message", "agent_message":
                item.kind = .message; item.role = p["role"].string.isEmpty ? p["author"].string : p["role"].string
                item.text = content(clean["content"])
            case "reasoning":
                item.kind = .reasoning; item.role = "assistant"
                item.text = content(clean["summary"])
                if item.text.isEmpty { item.text = content(clean["content"]) }
                if item.text.isEmpty { item.text = "Reasoning is encrypted or has no readable summary. Original record preserved." }
            case "function_call", "custom_tool_call", "local_shell_call", "tool_search_call", "web_search_call":
                item.toolName = p["name"].string.isEmpty ? subtype : p["name"].string
                item.kind = item.toolName.contains("exec_command") || subtype == "local_shell_call" ? .command : .toolCall
                item.text = content(clean["arguments"])
                if item.text.isEmpty { item.text = content(clean["input"]) }
                if item.text.isEmpty { item.text = content(clean["action"]) }
                if item.text.isEmpty { item.text = clean.pretty }
                if item.toolName.contains("apply_patch") { item.kind = .fileChange }
            case "function_call_output", "custom_tool_call_output", "tool_search_output":
                item.kind = .toolResult; item.text = content(clean["output"])
                if item.text.isEmpty { item.text = clean.pretty }
            case "image_generation_call":
                item.kind = .generatedImage; item.text = p["revised_prompt"].string
            default: item.text = clean.pretty
            }
        case "event_msg":
            switch subtype {
            case "user_message", "agent_message":
                item.kind = .message; item.role = subtype == "user_message" ? "user" : "assistant"; item.text = p["message"].string
            case "agent_reasoning": item.kind = .reasoning; item.role = "assistant"; item.text = p["text"].string
            case "exec_command_begin", "exec_command_end":
                item.kind = subtype.hasSuffix("end") ? .commandOutput : .command; item.toolName = "command"
                item.text = p["command"].array.map(\.string).joined(separator: " ")
                item.text += "\n" + content(clean["aggregated_output"])
                if !p["stdout"].string.isEmpty && p["aggregated_output"].string.isEmpty { item.text += "\n" + p["stdout"].string }
                if !p["stderr"].string.isEmpty { item.text += "\n" + p["stderr"].string }
            case "patch_apply_begin", "patch_apply_end": item.kind = .fileChange; item.text = clean.pretty
            case "mcp_tool_call_begin", "mcp_tool_call_end": item.kind = subtype.hasSuffix("end") ? .toolResult : .toolCall; item.text = clean.pretty
            case "image_generation_end": item.kind = .generatedImage; item.text = p["revised_prompt"].string
            case "thread_name_updated":
                metadata.title = p["thread_name"].string; item.kind = .systemEvent; item.text = "Renamed conversation: " + metadata.title
            case "task_started", "task_complete", "turn_aborted", "token_count", "context_compacted", "thread_settings_applied":
                item.kind = .systemEvent; item.text = clean.pretty
            default: item.text = clean.pretty
            }
        default: item.text = raw.withoutImageBodies.pretty
        }
        if item.kind == .message && item.role == "user" && metadata.title.isEmpty {
            metadata.title = String(item.text.split(separator: "\n").first.map(String.init)?.prefix(120) ?? "Untitled conversation")
        }
        if item.text.isEmpty { item.text = item.assets.isEmpty ? "No readable content. Original record preserved." : "Archived image" }
        return item
    }
}
