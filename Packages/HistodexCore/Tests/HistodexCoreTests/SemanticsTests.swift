import XCTest
import GRDB
@testable import HistodexCore

extension ArchiveTests {
    func testContextIsModeledSeparatelyAndNeverBecomesTitleOrPreview() async throws {
        let work = try workspace()
        let agents = "# AGENTS.md instructions for /project\n\n<INSTRUCTIONS>\nscaffoldneedle\n</INSTRUCTIONS>"
        let environment = "<environment_context>\nworkspaceprobe\n</environment_context>"
        let bytes = metadata() + message(agents) + message(environment)
            + message("permissionsprobe", role: "developer")
            + record("event_msg", ["type": "user_message", "kind": "environment_context", "message": "legacycontextprobe"])
            + message(environment + "\n\nFix the archive search results")
            + record("event_msg", ["type": "user_message", "message": "Fix the archive search results"])
            + message("Search now returns matching messages", role: "assistant")
            + record("event_msg", ["type": "token_count", "info": ["total": 999]])
            + record("response_item", ["type": "agent_message", "author": "user", "recipient": "/worker", "content": [["type": "input_text", "text": "coordinationprobe"]]])
            + record("response_item", ["type": "function_call_output", "output": "executionprobe"])
            + record("future_record", ["value": "futureprobe"])
        let file = try source(work, bytes)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        let report = try await store.importDirectory(work.appendingPathComponent("codex"))
        XCTAssertTrue(report.errors.isEmpty)
        let conversations = try await store.conversations()
        let conversation = try XCTUnwrap(conversations.first)
        XCTAssertEqual(conversation.title, "Fix the archive search results")
        XCTAssertEqual(conversation.preview, "Search now returns matching messages")
        XCTAssertEqual(conversation.itemCount, 2)
        let transcript = try await store.items(conversationID: conversation.id, scope: .conversation)
        XCTAssertEqual(transcript.map(\.text), ["Fix the archive search results", "Search now returns matching messages"])
        let all = try await store.items(conversationID: conversation.id)
        XCTAssertEqual(all.filter { $0.category == .context }.count, 6)
        XCTAssertTrue(all.contains { $0.category == .activity && $0.text == "executionprobe" })
        XCTAssertTrue(all.contains { $0.category == .unknown && $0.text.contains("futureprobe") })
        for term in ["scaffoldneedle", "workspaceprobe", "permissionsprobe", "legacycontextprobe", "coordinationprobe", "executionprobe", "futureprobe"] {
            let messages = try await store.search(term, scope: .conversation)
            let records = try await store.search(term, scope: .allRecords)
            XCTAssertTrue(messages.isEmpty, term); XCTAssertFalse(records.isEmpty, term)
        }
        XCTAssertEqual(try Data(contentsOf: file), Data(bytes.utf8))
        let context = try XCTUnwrap(all.first { $0.text == agents })
        let ownedRaw = try Data(contentsOf: work.appendingPathComponent("archive/" + context.rawPath))
        XCTAssertEqual(ownedRaw, Data(bytes.utf8))
    }

    func testEnvelopeRecognitionPreservesQuotedIncompleteAndMixedRequests() {
        for text in ["Explain <environment_context> to me", "```xml\n<environment_context>x</environment_context>\n```", "<environment_context>unfinished", "# AGENTS.md instructions are worth explaining"] {
            XCTAssertEqual(ConversationSemantics.separateContext(text).message, text)
            XCTAssertTrue(ConversationSemantics.separateContext(text).context.isEmpty)
        }
        let mixed = ConversationSemantics.separateContext("<environment_context>x</environment_context>\n<user_instructions>y</user_instructions>\nActual request")
        XCTAssertEqual(mixed.message, "Actual request")
        XCTAssertTrue(mixed.context.contains("<user_instructions>"))
        XCTAssertEqual(ConversationSemantics.title("# Repair conversation titles\nDetails"), "Repair conversation titles")
        XCTAssertTrue(ConversationSemantics.title(String(repeating: "请求", count: 100))!.hasSuffix("…"))
    }

    func testIndexNamesUpdateWithoutRolloutChangesAndRemainIndependent() async throws {
        let work = try workspace()
        _ = try source(work, metadata() + message("The actual first request"))
        let index = work.appendingPathComponent("codex/session_index.jsonl")
        func name(_ value: String) throws -> Data {
            var data = try JSONSerialization.data(withJSONObject: ["id": "test-session", "thread_name": value, "updated_at": "2026-09-06T11:00:00Z"])
            data.append(10); return data
        }
        let initial = try name("First explicit name") + name("Search and title repair")
        try initial.write(to: index)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        var conversations = try await store.conversations()
        XCTAssertEqual(conversations.first?.title, "Search and title repair")
        let updated = try initial + name("Readable conversation archive")
        try updated.write(to: index)
        let report = try await store.importDirectory(work.appendingPathComponent("codex"))
        XCTAssertEqual(report.unchanged, 1)
        conversations = try await store.conversations()
        XCTAssertEqual(conversations.first?.title, "Readable conversation archive")
        XCTAssertEqual(try Data(contentsOf: index), updated)
        try FileManager.default.removeItem(at: work.appendingPathComponent("codex"))
        _ = try await store.reparseArchive()
        conversations = try await store.conversations()
        XCTAssertEqual(conversations.first?.title, "Readable conversation archive")
    }

    func testForeignAndInheritedNamesCannotRenameChild() async throws {
        let work = try workspace(); let parentID = "11111111-1111-1111-1111-111111111111"
        let prefix = metadata(parentID) + message("Parent request")
            + record("event_msg", ["type": "thread_name_updated", "thread_id": parentID, "thread_name": "Parent name"])
        let file = try source(work, prefix)
        try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("rollout-parent-" + parentID + ".jsonl"))
        let child = record("session_meta", ["id": "child", "history_base": ["thread_id": parentID, "end_byte_offset": prefix.utf8.count, "end_ordinal_exclusive": 3]])
            + message("continue") + message("Repair the child archive")
            + record("event_msg", ["type": "thread_name_updated", "thread_id": parentID, "thread_name": "Unrelated rename"])
        try Data(child.utf8).write(to: file)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let conversations = try await store.conversations()
        XCTAssertEqual(conversations.first { $0.id == "child" }?.title, "Repair the child archive")
        XCTAssertEqual(conversations.first { $0.id == parentID }?.title, "Parent name")
    }

    func testNewerRenameEventOutranksStaleIndex() async throws {
        let work = try workspace()
        _ = try source(work, metadata() + message("Fallback") + record("event_msg", ["type": "thread_name_updated", "thread_id": "test-session", "thread_name": "Current rename"]))
        try Data("{\"id\":\"test-session\",\"thread_name\":\"Stale index\",\"updated_at\":\"2026-09-05T10:00:00Z\"}\n".utf8).write(to: work.appendingPathComponent("codex/session_index.jsonl"))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let conversations = try await store.conversations()
        XCTAssertEqual(conversations.first?.title, "Current rename")
    }

    func testOutdatedArchiveRepairUsesOwnedSnapshotsAndIsIdempotent() async throws {
        let work = try workspace()
        _ = try source(work, metadata() + message("<environment_context>old scaffold</environment_context>") + message("Readable repair"))
        let root = work.appendingPathComponent("archive")
        let store = try ArchiveStore(root: root)
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        // Recreate the previous schema/projection in this disposable fixture only.
        let db = try DatabaseQueue(path: root.appendingPathComponent("archive.sqlite").path)
        try await db.write { db in
            try db.execute(sql: """
                UPDATE snapshots SET parserVersion=2;
                UPDATE conversations SET title='<environment_context>';
                DROP INDEX item_category_order;
                ALTER TABLE items DROP COLUMN category;
                ALTER TABLE conversations DROP COLUMN baseTitle;
                ALTER TABLE conversations DROP COLUMN titleUpdatedAt;
                DROP TABLE conversation_names;
                ALTER TABLE items DROP COLUMN messageID;
                ALTER TABLE items DROP COLUMN channel;
                ALTER TABLE items DROP COLUMN isDelta;
                DELETE FROM grdb_migrations WHERE identifier='archive-v4';
                DELETE FROM grdb_migrations WHERE identifier='archive-v3';
                """)
        }
        try FileManager.default.removeItem(at: work.appendingPathComponent("codex"))
        let reopened = try ArchiveStore(root: root)
        let report = try await reopened.reparseArchive(onlyOutdated: true)
        XCTAssertEqual(report.imported, 1); XCTAssertTrue(report.errors.isEmpty)
        let conversations = try await reopened.conversations()
        XCTAssertEqual(conversations.first?.title, "Readable repair")
        let messages = try await reopened.items(conversationID: "test-session", scope: .conversation)
        XCTAssertEqual(messages.map(\.text), ["Readable repair"])
        let again = try await reopened.reparseArchive(onlyOutdated: true)
        XCTAssertEqual(again.imported, 0)
    }

    func testConversationPaginationSkipsSupportingRecordsAtDatabaseLayer() async throws {
        let work = try workspace()
        let bytes = metadata() + (0..<250).map { index in
            record("event_msg", ["type": "token_count", "value": index]) + message("Request \(index)")
        }.joined()
        _ = try source(work, bytes)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let start = try await store.precedingPageStart(conversationID: "test-session", before: Int.max, scope: .conversation)
        let page = try await store.items(conversationID: "test-session", from: start, scope: .conversation)
        XCTAssertEqual(page.count, 100); XCTAssertEqual(page.first?.text, "Request 150"); XCTAssertEqual(page.last?.text, "Request 249")
        let hits = try await store.search("Request 149", scope: .conversation)
        let hit = try XCTUnwrap(hits.first)
        let target = try await store.items(conversationID: hit.conversationID, from: hit.ordinal, limit: 1, scope: .conversation)
        XCTAssertEqual(target.first?.id, hit.id)
    }
}
