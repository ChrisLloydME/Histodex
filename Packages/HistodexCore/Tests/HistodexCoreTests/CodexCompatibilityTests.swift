import XCTest
import AppKit
@testable import HistodexCore

extension ArchiveTests {
    func testLegacyCodexRecordsAndLiteralText() async throws {
        let work = try workspace()
        let lines: [[String: Any]] = [
            ["timestamp": 1757498400, "role": "user", "content": "Translate hello to Spanish"],
            ["timestamp": "2025-09-10T10:00:01Z", "type": "tool_call", "function": ["name": "translate"], "arguments": ["text": "hello", "to": "es"]],
            ["timestamp": "2025-09-10T10:00:02Z", "type": "tool_result", "name": "translate", "result": "hola"],
            ["timestamp": "2025-09-10T10:00:03Z", "role": "assistant", "content": "\"hola\""],
            ["role": "user", "text": "{\"keep\": \"my spacing\"}"]
        ]
        let bytes = try lines.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) + "\n" }.joined()
        _ = try source(work, bytes)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let conversations = try await store.conversations(); let c = try XCTUnwrap(conversations.first)
        XCTAssertEqual(c.title, "Translate hello to Spanish")
        XCTAssertEqual(c.startedAt, "2025-09-10T10:00:00Z")
        let items = try await store.items(conversationID: c.id)
        XCTAssertEqual(items.map(\.kind), [.message, .toolCall, .toolResult, .message, .message])
        XCTAssertEqual(items[1].toolName, "translate")
        XCTAssertEqual(TranscriptEntry.readableText(items[2]), "hola")
        XCTAssertEqual(items[3].text, "\"hola\"")
        XCTAssertEqual(items[4].text, "{\"keep\": \"my spacing\"}")
    }

    func testTypedContentBlocksDoNotBecomeJSONMessages() async throws {
        let work = try workspace()
        let blocks: [Any] = ["Read ", ["type": "input_text", "text": "the "], ["type": "text", "value": "archive"], ["type": "text", "data": " carefully."], ["type": "future_binary", "private": "unsupportedneedle"]]
        _ = try source(work, metadata() + record("response_item", ["type": "message", "role": "user", "content": blocks])
            + record("response_item", ["type": "message", "role": "assistant", "content": [["type": "refusal", "refusal": "I cannot do that."]]]))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let items = try await store.items(conversationID: "test-session", scope: .conversation)
        XCTAssertEqual(items.map(\.text), ["Read the archive carefully.", "I cannot do that."])
        let hits = try await store.search("unsupportedneedle", scope: .conversation); XCTAssertTrue(hits.isEmpty)
        let raw = try await store.search("unsupportedneedle", scope: .allRecords); XCTAssertEqual(raw.count, 1)
    }

    func testStreamIdentityAndChannelSurviveOfflineReparse() async throws {
        let work = try workspace()
        func chunk(_ text: String, delta: Bool, channel: String = "final", id: String = "answer") -> String {
            record("response_item", ["type": "message", "role": "assistant", "message_id": id, "channel": channel, "delta": delta, "content": text])
        }
        _ = try source(work, metadata() + message("Explain the fix") + chunk("A readable ", delta: true)
            + chunk("answer.", delta: true) + chunk("A readable answer.", delta: false)
            + chunk("A distinct comment.", delta: false, channel: "commentary")
            + chunk("Another answer.", delta: false, id: "another"))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        try FileManager.default.removeItem(at: work.appendingPathComponent("codex"))
        _ = try await store.reparseArchive()
        let items = try await store.items(conversationID: "test-session", scope: .conversation)
        let entries = TranscriptEntry.project(items)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[1].style, .incoming)
        XCTAssertEqual(entries[1].body, "A readable answer.")
        XCTAssertEqual(entries[1].items.count, 3)
        XCTAssertEqual(entries[2].body, "A distinct comment.")
        XCTAssertTrue(entries[1].contains(ordinal: items[2].ordinal))
    }

    func testCompleteEmbeddedContextAndIDERequestKeepActualPrompt() async throws {
        let work = try workspace()
        let prompt = "Keep the original change.\n<turn_aborted reason=\"user\">Interrupted</turn_aborted>\nNow fix search."
        let ide = "# Context from my IDE setup:\n## Open tabs:\n- archive.swift\n\n## My request for Codex:\nRepair conversation ordering"
        _ = try source(work, metadata() + message(ide) + message(prompt))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let messages = try await store.items(conversationID: "test-session", scope: .conversation)
        XCTAssertEqual(messages[0].text, "Repair conversation ordering")
        XCTAssertTrue(messages[1].text.contains("Keep the original change."))
        XCTAssertTrue(messages[1].text.contains("Now fix search."))
        XCTAssertFalse(messages[1].text.contains("turn_aborted"))
        let conversations = try await store.conversations()
        XCTAssertEqual(conversations.first?.title, "Repair conversation ordering")
        let quoted = "Here is a sample:\n```xml\n<turn_aborted reason=\"sample\">Example</turn_aborted>\n```"
        XCTAssertEqual(ConversationSemantics.separateContext(quoted).message, quoted)
        let adjacent = "<environment_context>workspace</environment_context><user_instructions>setup</user_instructions>\nActual request"
        let separated = ConversationSemantics.separateContext(adjacent)
        XCTAssertEqual(separated.message, "Actual request")
        XCTAssertTrue(separated.context.contains("<user_instructions>"))
        XCTAssertTrue(ConversationSemantics.separateContext(separated.message).context.isEmpty)
    }

    func testToolOutputPreservesBothChannelsAndExitStatus() {
        var item = ArchiveItem(); item.kind = .commandOutput
        item.text = #"{"stdout":"normal output","stderr":"compiler error","exit_code":2}"#
        let text = TranscriptEntry.readableText(item)
        XCTAssertTrue(text.contains("normal output")); XCTAssertTrue(text.contains("Standard error:\ncompiler error")); XCTAssertTrue(text.contains("Exit code: 2"))
        item.text = #"{"output":{"content":[{"type":"text","text":"first"},{"type":"text","text":"second"}]}}"#
        XCTAssertEqual(TranscriptEntry.readableText(item), "first\nsecond")
    }

    func testMirrorsAllowMissingChannelAndImageMarkersWithoutRepeatingAnswer() async throws {
        let work = try workspace()
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII="
        _ = try source(work, metadata()
            + record("event_msg", ["type": "user_message", "message": "Describe this image"])
            + record("response_item", ["type": "message", "role": "user", "content": [["type": "input_image", "image_url": "data:image/png;base64," + png], ["type": "input_text", "text": "Describe this image"]]])
            + record("response_item", ["type": "message", "role": "assistant", "channel": "final", "content": "A small image."])
            + record("event_msg", ["type": "agent_message", "message": "A small image.\n"]))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let items = try await store.items(conversationID: "test-session", scope: .conversation)
        XCTAssertEqual(items.map(\.text), ["Describe this image", "A small image."])
        XCTAssertEqual(items.first?.assets.count, 1)
    }

    func testAnalysisChannelIsActivityAndFinalChannelIsConversation() async throws {
        let work = try workspace()
        _ = try source(work, metadata() + message("Explain the result")
            + record("response_item", ["type": "message", "role": "assistant", "channel": "analysis", "content": "Private working notes"])
            + record("response_item", ["type": "message", "role": "assistant", "channel": "final", "content": "The readable result"]))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let conversation = try await store.items(conversationID: "test-session", scope: .conversation)
        XCTAssertEqual(conversation.map(\.text), ["Explain the result", "The readable result"])
        let records = try await store.items(conversationID: "test-session")
        XCTAssertTrue(records.contains { $0.kind == .reasoning && $0.category == .activity && $0.text == "Private working notes" })
    }

}
