import XCTest
import GRDB
@testable import HistodexCore

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ImportProgress] = []
    func append(_ value: ImportProgress) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var events: [ImportProgress] { lock.lock(); defer { lock.unlock() }; return values }
}

extension ArchiveTests {
    func testStateDatabaseWALTitlesAndIndexOverrideSurviveSourceRemoval() async throws {
        let work = try workspace(); let rollout = try source(work, metadata() + message("Unhelpful first line\nThe substantive request"))
        let sourceRoot = work.appendingPathComponent("codex")
        let state = sourceRoot.appendingPathComponent("state_5.sqlite")
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0") }
        let queue = try DatabaseQueue(path: state.path, configuration: config)
        try await queue.write { db in
            try db.execute(sql: "CREATE TABLE threads(id TEXT PRIMARY KEY, rollout_path TEXT, title TEXT, first_user_message TEXT)")
            try db.execute(sql: "INSERT INTO threads VALUES(?,?,?,?)", arguments: ["test-session",rollout.path,"Correct Codex database title","Original request"])
        }
        let original = try Data(contentsOf: state)
        let wal = URL(fileURLWithPath: state.path + "-wal"); let walBytes = try Data(contentsOf: wal)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        let report = try await store.importDirectory(sourceRoot)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "\n"))
        var conversations = try await store.conversations()
        XCTAssertEqual(conversations.first?.title, "Correct Codex database title")
        XCTAssertEqual(try Data(contentsOf: state), original); XCTAssertEqual(try Data(contentsOf: wal), walBytes)
        try await queue.write { db in try db.execute(sql: "UPDATE threads SET title='Updated database title'") }
        let update = try await store.importDirectory(sourceRoot)
        XCTAssertEqual(update.unchanged, 1)
        conversations = try await store.conversations(); XCTAssertEqual(conversations.first?.title, "Updated database title")
        try Data("{\"id\":\"test-session\",\"thread_name\":\"User chosen title\",\"updated_at\":\"2020-01-01T00:00:00Z\"}\n".utf8).write(to: sourceRoot.appendingPathComponent("session_index.jsonl"))
        _ = try await store.importDirectory(sourceRoot)
        conversations = try await store.conversations(); XCTAssertEqual(conversations.first?.title, "User chosen title")
        try queue.close()
        try FileManager.default.removeItem(at: sourceRoot)
        _ = try await store.reparseArchive()
        conversations = try await store.conversations(); XCTAssertEqual(conversations.first?.title, "User chosen title")
    }

    func testStateTitleFallsBackToFirstMessageAndMatchesRolloutPath() async throws {
        let work = try workspace(); let file = try source(work, metadata() + message("Fallback"))
        let queue = try DatabaseQueue(path: work.appendingPathComponent("codex/state_5.sqlite").path)
        try await queue.write { db in
            try db.execute(sql: "CREATE TABLE threads(id TEXT,rollout_path TEXT,title TEXT,first_user_message TEXT)")
            try db.execute(sql: "INSERT INTO threads VALUES(?,?,?,?)", arguments: ["different-runtime-id", file.path, "   ", "The actual first user request"])
        }
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let conversations = try await store.conversations()
        XCTAssertEqual(conversations.first?.title, "The actual first user request")
    }

    func testIndexAndUpdateProgressAndUnchangedSnapshotReuse() async throws {
        let work = try workspace()
        let file = try source(work, metadata() + (0..<1500).map { message("Progress request \($0)") }.joined())
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        let first = ProgressLog()
        _ = try await store.importDirectory(work.appendingPathComponent("codex"), progress: { first.append($0) })
        XCTAssertTrue(first.events.contains { $0.phase == "Finding sessions" && $0.fraction == nil })
        XCTAssertTrue(first.events.contains { $0.phase == "Copying sessions" && $0.processedBytes > 0 })
        XCTAssertTrue(first.events.contains { $0.phase == "Indexing sessions" && $0.processedBytes > 0 })
        XCTAssertEqual(first.events.last?.fraction, 1)
        let repeated = ProgressLog()
        let report = try await store.importDirectory(work.appendingPathComponent("codex"), progress: { repeated.append($0) })
        XCTAssertEqual(report.unchanged, 1)
        XCTAssertFalse(repeated.events.contains { $0.totalBytes > 0 }, "Unchanged rollouts must not be copied or parsed again")
        try Data((metadata() + message("Changed source")).utf8).write(to: file)
        let changed = try await store.importDirectory(work.appendingPathComponent("codex"))
        XCTAssertEqual(changed.imported, 1)
        let rebuilt = ProgressLog()
        _ = try await store.reparseArchive(progress: { rebuilt.append($0) })
        XCTAssertTrue(rebuilt.events.contains { $0.phase == "Rebuilding index" && $0.totalBytes > 0 })
        XCTAssertEqual(rebuilt.events.last?.fraction, 1)
    }

    func testTitleCandidatesPreferShortHeadRequestAndUseMultilineFallback() {
        var candidates = CodexTitleCandidates()
        var item = ArchiveItem(); item.kind = .message; item.category = .conversation; item.role = "user"
        item.text = String(repeating: "Detailed requirement ", count: 30); candidates.consider(item, record: 2)
        item.text = "Fix the sidebar layout"; candidates.consider(item, record: 4)
        XCTAssertEqual(candidates.value, "Fix the sidebar layout")
        XCTAssertEqual(ConversationSemantics.title("First line\nSecond line with the actual request"), "First line Second line with the actual request")
    }
}
