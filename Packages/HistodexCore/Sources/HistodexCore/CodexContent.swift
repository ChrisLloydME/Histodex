import Foundation

/// Codex text blocks are not JSON descriptions of messages. Decode their text
/// leaves explicitly, retaining unsupported blocks separately in the archive.
enum CodexContent {
    struct Decoded {
        var text = ""
        var unknown: [JSONValue] = []
    }
    static func decode(_ value: JSONValue, separator: String = "") -> Decoded {
        switch value {
        case .null: return Decoded()
        case .string(let text): return Decoded(text: text.hasPrefix("data:image/") ? "[Archived image]" : text)
        case .array(let blocks):
            let parts = blocks.map { decode($0, separator: separator) }
            return Decoded(text: parts.map(\.text).joined(separator: separator), unknown: parts.flatMap(\.unknown))
        case .object:
            let type = value["type"].string
            if ["input_image", "image", "image_url", "local_image"].contains(type) { return Decoded() }
            if ["input_audio", "audio", "audio_url"].contains(type) { return Decoded() }
            if ["", "text", "input_text", "output_text", "summary_text", "refusal", "text_delta"].contains(type) {
                for key in ["text", "value", "data", "refusal"] {
                    if case .string(let text) = value[key] { return Decoded(text: text) }
                    if case .object = value[key], case .string(let text) = value[key]["value"] { return Decoded(text: text) }
                }
            }
            return Decoded(unknown: [value.withoutImageBodies])
        default: return Decoded(unknown: [value])
        }
    }

    static func message(_ payload: JSONValue) -> Decoded {
        for key in ["content", "text", "message"] {
            if case .null = payload[key] { continue }
            return decode(payload[key])
        }
        if case .object = payload["delta"] {
            return message(payload["delta"])
        }
        if case .string(let text) = payload["delta"] { return Decoded(text: text) }
        return Decoded()
    }

    /// Output channels are independent. Do not pick stdout and silently lose stderr.
    static func output(_ value: JSONValue) -> String {
        if case .string(let text) = value {
            if let data = text.data(using: .utf8), let nested = try? JSONDecoder().decode(JSONValue.self, from: data),
               case .object = nested { return output(nested) }
            return text
        }
        if case .array = value { return decode(value, separator: "\n").text }
        var parts: [String] = []
        if !value["aggregated_output"].string.isEmpty { parts.append(value["aggregated_output"].string) }
        else {
            for key in ["stdout", "stderr"] where !value[key].string.isEmpty {
                parts.append((key == "stderr" ? "Standard error:\n" : "") + value[key].string)
            }
        }
        for key in ["result", "output", "content", "text"] {
            if case .null = value[key] { continue }
            let part: String
            if case .array = value[key] { part = decode(value[key], separator: "\n").text }
            else { part = output(value[key]) }
            if !part.isEmpty, !parts.contains(part) { parts.append(part) }
        }
        if case .number(let status) = value["exit_code"], let code = Int(exactly: status) { parts.append("Exit code: \(code)") }
        if case .number(let status) = value["exitCode"], let code = Int(exactly: status) { parts.append("Exit code: \(code)") }
        return parts.isEmpty ? value.withoutImageBodies.pretty : parts.joined(separator: "\n\n")
    }

    static func timestamp(_ raw: JSONValue, _ payload: JSONValue) -> String {
        for object in [raw, payload] {
            for key in ["timestamp", "time", "ts", "created_at", "created"] {
                if case .string(let text) = object[key], !text.isEmpty { return text }
                if case .number(let seconds) = object[key], seconds.isFinite {
                    return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds))
                }
            }
        }
        return ""
    }
}
