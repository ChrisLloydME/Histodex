import XCTest
import GRDB
@testable import HistodexCore

extension ArchiveTests {
    func testContentProvenanceSeparatesInjectedBlocksAndPreservesLiteralUserText() async throws {
        let work = try workspace()
        func input(_ texts: [String], _ kinds: [String]) -> String {
            record("response_item", ["type": "message", "role": "user",
                "content": texts.map { ["type": "input_text", "text": $0] },
                "internal_chat_message_metadata_passthrough": ["content_item_kinds": kinds]])
        }
        let literal = "<environment_context>\nPlease explain this literal example\n</environment_context>"
        _ = try source(work, metadata()
            + input(["Injectedneedle arbitrary future configuration"], ["future.configuration"])
            + input([literal, "Hiddenneedle context"], ["user.text", "plugins.recommendations"])
            + input(["Actual question"], ["user.text"]))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let items = try await store.items(conversationID: "test-session", scope: .conversation)
        XCTAssertEqual(items.map(\.text), [literal, "Actual question"])
        let hidden = try await store.search("Injectedneedle", scope: .conversation)
        XCTAssertTrue(hidden.isEmpty)
        let preserved = try await store.search("Hiddenneedle", scope: .allRecords)
        XCTAssertEqual(preserved.count, 1)
        _ = try await store.reparseArchive()
        let reparsed = try await store.items(conversationID: "test-session", scope: .conversation)
        XCTAssertEqual(reparsed.map(\.text), items.map(\.text))
    }

    func testInternalThreadProvenanceExcludesListAndSearchButPreservesRecords() async throws {
        for provenance in ["subagent", "guardian_review"] {
            let work = try workspace()
            _ = try source(work, record("session_meta", ["id": "test-session", "thread_source": provenance]) + message("Internalneedle task"))
            let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
            _ = try await store.importDirectory(work.appendingPathComponent("codex"))
            let list = try await store.conversations(); XCTAssertTrue(list.isEmpty)
            let hits = try await store.search("Internalneedle"); XCTAssertTrue(hits.isEmpty)
            let items = try await store.items(conversationID: "test-session"); XCTAssertFalse(items.isEmpty)
        }
        let payload: JSONValue = .object(["source": .object(["subagent": .object(["other": .string("guardian")])])])
        XCTAssertFalse(CodexAdapter.isUserVisible(payload))
        XCTAssertTrue(CodexAdapter.isUserVisible(.object(["source": .string("exec")])) )
    }

    func testModernDisplayNameOverridesPromptTitleAndStaleIndex() async throws {
        let work = try workspace(); let file = try source(work, metadata() + message("Original request"))
        let root = work.appendingPathComponent("codex")
        let db = try DatabaseQueue(path: root.appendingPathComponent("state_5.sqlite").path)
        try await db.write { db in
            try db.execute(sql: "CREATE TABLE threads(id TEXT,rollout_path TEXT,title TEXT,name TEXT)")
            try db.execute(sql: "INSERT INTO threads VALUES(?,?,?,?)", arguments: ["test-session",file.path,"整理当前项目的 git 历史，尤其是 commit info 什么的","整理 Git 提交历史"])
        }
        try Data("{\"id\":\"test-session\",\"thread_name\":\"Old title\"}\n".utf8).write(to: root.appendingPathComponent("session_index.jsonl"))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(root)
        var list = try await store.conversations(); XCTAssertEqual(list.first?.title, "整理 Git 提交历史")
        try db.close(); try FileManager.default.removeItem(at: root)
        _ = try await store.reparseArchive()
        list = try await store.conversations(); XCTAssertEqual(list.first?.title, "整理 Git 提交历史")
    }

    func testProgressDescriptionOmitsStorageDetails() {
        let progress = ImportProgress(completed: 2, total: 4, filename: "secret.jsonl", phase: "Indexing", processedBytes: 512, totalBytes: 1024)
        XCTAssertEqual(progress.description, "Indexing · 62%")
    }
}

extension ArchiveTests {
    func testOptionalCurrentCodexScreenshotTitles() async throws {
        guard let path = ProcessInfo.processInfo.environment["HISTODEX_CURRENT_CODEX_FIXTURES"] else { throw XCTSkip("Private current Codex reference not configured") }
        let work = try workspace()
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(URL(fileURLWithPath: path))
        let conversations = try await store.conversations()
        let expected = ["01a04802-90e3-7ee3-a57a-dcd34f9293f9": "修复搜索超时问题", "01a05187-bcf1-7e53-bd68-720bca43ad16": "整理 Git 提交历史", "01a05211-9214-7001-ae7f-5de7d1268722": "评估 swift-taglib 集成"]
        XCTAssertEqual(conversations.count, expected.count)
        for conversation in conversations {
            XCTAssertEqual(conversation.title, expected[conversation.id])
            let items = try await store.items(conversationID: conversation.id, limit: 200, scope: .conversation)
            XCTAssertFalse(items.isEmpty)
            XCTAssertFalse(items.contains { $0.text.hasPrefix("<recommended_plugins>") })
        }
    }
}
