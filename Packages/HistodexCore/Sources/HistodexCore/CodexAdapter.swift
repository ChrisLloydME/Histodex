import Foundation

struct SessionMetadata {
    var sourceID = ""
    var title = ""
    var titleUpdatedAt = ""
    var hasExplicitTitle = false
    var project = ""
    var startedAt = ""
    var updatedAt = ""
    var parentRolloutID = ""
    var parentEndOrdinal: Int64?
    var parentEndByte: Int64?
}

struct CodexAdapter {
    static let version = 4
    var metadata = SessionMetadata()
    var turnID = ""
    var acceptsTitle = true
    var recordThreadID = ""
    private var ownsTitle: Bool { acceptsTitle && (recordThreadID.isEmpty || recordThreadID == metadata.sourceID) }

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
        var type = raw["type"].string
        let p: JSONValue
        if case .object = raw["payload"] { p = raw["payload"] } else { p = raw }
        var subtype = p["type"].string
        // Older Codex/OpenAI sessions use top-level messages and tool records.
        if case .null = raw["payload"] {
            if ["", "message", "user", "assistant", "tool"].contains(type), !p["role"].string.isEmpty {
                subtype = p["role"].string == "tool" ? "function_call_output" : "message"; type = "response_item"
            } else if ["function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output", "web_search_call", "web_search_call_output", "tool_call", "tool_result", "reasoning"].contains(type) {
                subtype = type == "tool_call" ? "function_call" : type == "tool_result" ? "function_call_output" : type
                type = "response_item"
            }
        }
        item.sourceType = type + (subtype.isEmpty ? "" : "/" + subtype)
        item.timestamp = CodexContent.timestamp(raw, p)
        if metadata.startedAt.isEmpty { metadata.startedAt = item.timestamp }
        item.messageID = p["message_id"].string.isEmpty ? p["id"].string : p["message_id"].string
        item.channel = p["channel"].string
        if case .bool(let delta) = p["delta"] { item.isDelta = delta }
        else if case .object = p["delta"] { item.isDelta = true }
        else if case .string = p["delta"] { item.isDelta = true }
        if case .null = p["chunk"] {} else { item.isDelta = true }
        if case .null = p["delta_index"] {} else { item.isDelta = true }
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
            recordThreadID = p["id"].string
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
            case "message":
                item.kind = .message; item.role = p["role"].string.isEmpty ? p["author"].string : p["role"].string
                let decoded = CodexContent.message(clean)
                item.text = decoded.text
                item.unsupportedText = decoded.unknown.isEmpty ? "" : JSONValue.array(decoded.unknown).pretty
            case "agent_message":
                item.role = p["author"].string; item.text = content(clean["content"])
                item.category = .context
            case "reasoning":
                item.kind = .reasoning; item.role = "assistant"
                item.text = CodexContent.decode(clean["summary"], separator: "\n\n").text
                if item.text.isEmpty { item.text = CodexContent.decode(clean["content"], separator: "\n\n").text }
                if item.text.isEmpty { item.text = "Reasoning is encrypted or has no readable summary. Original record preserved." }
            case "function_call", "custom_tool_call", "local_shell_call", "tool_search_call", "web_search_call":
                item.toolName = [p["name"].string, p["tool"].string, p["function"]["name"].string].first(where: { !$0.isEmpty }) ?? subtype
                item.kind = item.toolName.contains("exec_command") || subtype == "local_shell_call" ? .command : .toolCall
                item.text = content(clean["arguments"])
                if item.text.isEmpty { item.text = content(clean["input"]) }
                if item.text.isEmpty { item.text = content(clean["action"]) }
                if item.text.isEmpty { item.text = clean.pretty }
                if item.toolName.contains("apply_patch") { item.kind = .fileChange }
            case "function_call_output", "custom_tool_call_output", "tool_search_output", "web_search_call_output":
                item.kind = .toolResult
                if case .string(let output) = clean["output"], clean["stdout"].string.isEmpty, clean["stderr"].string.isEmpty, case .null = clean["result"], case .null = clean["exit_code"], case .null = clean["exitCode"] { item.text = output }
                else { item.text = clean.pretty }
            case "image_generation_call":
                item.kind = .generatedImage; item.text = p["revised_prompt"].string
            default: item.text = clean.pretty
            }
        case "event_msg":
            switch subtype {
            case "user_message", "agent_message":
                item.kind = .message; item.role = subtype == "user_message" ? "user" : "assistant"
                let decoded = CodexContent.message(clean); item.text = decoded.text
                item.unsupportedText = decoded.unknown.isEmpty ? "" : JSONValue.array(decoded.unknown).pretty
            case "agent_reasoning": item.kind = .reasoning; item.role = "assistant"; item.text = p["text"].string
            case "exec_command_begin", "exec_command_end":
                item.kind = subtype.hasSuffix("end") ? .commandOutput : .command; item.toolName = "command"
                item.text = p["command"].array.map(\.string).joined(separator: " ")
                item.text += "\n" + content(clean["aggregated_output"])
                if !p["stdout"].string.isEmpty && p["aggregated_output"].string.isEmpty { item.text += "\n" + p["stdout"].string }
                if !p["stderr"].string.isEmpty { item.text += "\n" + p["stderr"].string }
                if subtype.hasSuffix("end") { item.text = clean.pretty }
            case "patch_apply_begin", "patch_apply_end": item.kind = .fileChange; item.text = clean.pretty
            case "mcp_tool_call_begin", "mcp_tool_call_end": item.kind = subtype.hasSuffix("end") ? .toolResult : .toolCall; item.text = clean.pretty
            case "image_generation_end": item.kind = .generatedImage; item.text = p["revised_prompt"].string
            case "thread_name_updated":
                if ownsTitle, p["thread_id"].string.isEmpty || p["thread_id"].string == metadata.sourceID,
                   let title = ConversationSemantics.explicitTitle(p["thread_name"].string) {
                    metadata.title = title; metadata.hasExplicitTitle = true; metadata.titleUpdatedAt = item.timestamp
                }
                item.kind = .systemEvent; item.text = "Renamed conversation: " + p["thread_name"].string
            case "task_started", "task_complete", "turn_aborted", "token_count", "context_compacted", "thread_settings_applied":
                item.kind = .systemEvent; item.text = clean.pretty
            default: item.text = clean.pretty
            }
        default: item.text = raw.withoutImageBodies.pretty
        }
        if item.kind == .message {
            item.category = ["user", "assistant"].contains(item.role) ? .conversation : .context
            if item.role == "assistant", item.channel == "analysis" { item.kind = .reasoning; item.category = .activity }
            if item.role == "assistant", !p["recipient"].string.isEmpty, p["recipient"].string != "all" { item.category = .activity }
            if item.role == "user" {
                let split = ConversationSemantics.separateContext(item.text)
                if ["environment_context", "environment-context", "env_context"].contains(p["kind"].string) {
                    item.category = .context
                } else if !split.context.isEmpty {
                    if split.message.isEmpty { item.category = .context }
                    else { item.contextText = split.context; item.text = split.message }
                }
                if ownsTitle, item.category == .conversation, !metadata.hasExplicitTitle,
                   metadata.title.isEmpty || ConversationSemantics.isGenericTitle(metadata.title),
                   let title = ConversationSemantics.title(item.text) { metadata.title = title }
            }
        } else if item.category != .context {
            switch item.kind {
            case .image, .generatedImage: item.category = .conversation
            case .systemEvent: item.category = .metadata
            case .unknown: item.category = .unknown
            default: item.category = .activity
            }
        }
        if item.kind == .message, item.text.isEmpty, item.assets.isEmpty {
            item.category = .unknown
        }
        if item.text.isEmpty { item.text = !item.unsupportedText.isEmpty ? "Unsupported content block. Original record preserved." : item.assets.isEmpty ? "No readable content. Original record preserved." : "Archived image" }
        return item
    }
}
