import XCTest
import Foundation
import CryptoKit
import libzstd
@testable import HistodexCore

final class ArchiveTests: XCTestCase, @unchecked Sendable {
    func workspace() throws -> URL {
        var project = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { project.deleteLastPathComponent() }
        let url = project.appendingPathComponent(".tmp/tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func record(_ type: String, _ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["type": type, "timestamp": "2026-09-06T10:00:00Z", "payload": payload], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
    func metadata(_ id: String = "test-session") -> String {
        record("session_meta", ["id": id, "cwd": "/project", "timestamp": "2026-09-06T10:00:00Z", "cli_version": "fixture"])
    }
    func message(_ text: String, role: String = "user") -> String {
        record("response_item", ["type": "message", "role": role, "content": [["type": "input_text", "text": text]]])
    }
    func source(_ workspace: URL, _ text: String, archived: Bool = false) throws -> URL {
        let dir = workspace.appendingPathComponent("codex/\(archived ? "archived_sessions" : "sessions/2026/09/06")")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("rollout-test.jsonl")
        try Data(text.utf8).write(to: file)
        return file
    }

    func testIndependentArchiveSearchAndRepeatImport() async throws {
        let work = try workspace(); let bytes = metadata() + message("Unique searchable telescope") + message("A readable answer", role: "assistant")
        let file = try source(work, bytes, archived: true)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        let report = try await store.importDirectory(work.appendingPathComponent("codex"))
        XCTAssertEqual(report.imported, 1); XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), Data(bytes.utf8))
        let repeatReport = try await store.importDirectory(work.appendingPathComponent("codex"))
        XCTAssertEqual(repeatReport.unchanged, 1)
        try FileManager.default.removeItem(at: work.appendingPathComponent("codex"))
        let sessions = try await store.conversations(); XCTAssertEqual(sessions.count, 1)
        let hits = try await store.search("telescope"); XCTAssertEqual(hits.count, 1)
        let page = try await store.items(conversationID: hits[0].conversationID, from: hits[0].ordinal)
        XCTAssertEqual(page.first?.id, hits[0].id); XCTAssertTrue(page[0].text.contains("telescope"))
        let reparsed = try await store.reparseArchive(); XCTAssertEqual(reparsed.imported, 1)
        let hitsAgain = try await store.search("telescope"); XCTAssertEqual(hitsAgain.count, 1)
    }

    func testMalformedUnknownAndTruncatedRecordsSurvive() async throws {
        let work = try workspace()
        _ = try source(work, metadata() + "{broken}\n" + record("future_envelope", ["novel": "preserve me"]) + message("after corruption") + "{\"type\":")
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let items = try await store.items(conversationID: "test-session")
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items.filter(\.isDiagnostic).count, 2)
        XCTAssertTrue(items.contains { $0.kind == .unknown && $0.text.contains("preserve me") })
        XCTAssertTrue(items.contains { $0.text == "after corruption" })
    }

    func testBoundedReaderPreservesOversizeOffsets() throws {
        let work = try workspace(); let url = work.appendingPathComponent("lines.jsonl")
        let bytes = Data((String(repeating: "x", count: 200_000) + "\n{}\nlast").utf8)
        try bytes.write(to: url)
        var lines: [RawLine] = []
        try JSONLReader(maximumRecordBytes: 100).read(url) { lines.append($0) }
        XCTAssertEqual(lines.count, 3); XCTAssertNil(lines[0].data)
        XCTAssertEqual(lines[1].offset, 200_001); XCTAssertEqual(lines[1].length, 3)
        XCTAssertEqual(lines[2].offset, 200_004); XCTAssertFalse(lines[2].terminated)
    }

    func testCompressedAndCorruptFrames() async throws {
        let work = try workspace(); let file = try source(work, metadata() + message("compressed content"))
        let input = try Data(contentsOf: file)
        var output = Data(count: ZSTD_compressBound(input.count))
        let count = output.withUnsafeMutableBytes { out in input.withUnsafeBytes { src in ZSTD_compress(out.baseAddress, out.count, src.baseAddress, src.count, 3) } }
        XCTAssertEqual(ZSTD_isError(count), 0); output.count = count
        let compressed = file.appendingPathExtension("zst"); try output.write(to: compressed)
        try FileManager.default.removeItem(at: file)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        let report = try await store.importDirectory(work.appendingPathComponent("codex"))
        XCTAssertEqual(report.imported, 1); XCTAssertTrue(report.errors.isEmpty)
        let hit = try await store.search("compressed"); XCTAssertEqual(hit.count, 1)
        try output.dropLast(4).write(to: compressed)
        let bad = try await store.importDirectory(work.appendingPathComponent("codex"))
        XCTAssertEqual(bad.errors.count, 1)
        let stillThere = try await store.search("compressed"); XCTAssertEqual(stillThere.count, 1)
    }

    func testAssetDedupMissingAndReparseAfterSourceRemoval() async throws {
        let work = try workspace()
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII="
        let local = work.appendingPathComponent("picture.png"); try Data(base64Encoded: png)!.write(to: local)
        let payload: [String: Any] = ["type": "message", "role": "user", "content": [
            ["type": "input_image", "image_url": "data:image/png;base64," + png],
            ["type": "input_image", "image_url": local.path],
            ["type": "input_image", "image_url": work.appendingPathComponent("missing.png").path]]]
        _ = try source(work, metadata() + record("response_item", payload) + record("response_item", ["type": "image_generation_call", "result": png, "revised_prompt": "generated fixture"]))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        var items = try await store.items(conversationID: "test-session")
        XCTAssertEqual(items[1].assets.count, 3)
        XCTAssertEqual(items[1].assets[0].hash, items[1].assets[1].hash)
        XCTAssertEqual(items[2].assets[0].hash, items[1].assets[0].hash)
        XCTAssertNotNil(items[1].assets[2].missingReason)
        XCTAssertFalse(items.map(\.text).joined().contains(png))
        try FileManager.default.removeItem(at: local)
        try FileManager.default.removeItem(at: work.appendingPathComponent("codex"))
        _ = try await store.reparseArchive()
        items = try await store.items(conversationID: "test-session")
        XCTAssertNotNil(items[1].assets[1].hash)
    }

    func testMirrorsDoNotEraseRepeatedUtterances() async throws {
        let work = try workspace()
        let mirror = record("event_msg", ["type": "user_message", "message": "repeat"])
        _ = try source(work, metadata() + mirror + message("repeat") + mirror + message("repeat") + message("repeat"))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let items = try await store.items(conversationID: "test-session")
        XCTAssertEqual(items.filter { $0.kind == .message }.count, 3)
    }

    func testChangedSourceUpdatesAndKeepsOldRawSnapshot() async throws {
        let work = try workspace(); let initial = metadata() + message("first version")
        let file = try source(work, initial)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        try Data((initial + message("next version")).utf8).write(to: file)
        let report = try await store.importDirectory(work.appendingPathComponent("codex")); XCTAssertEqual(report.imported, 1)
        let raw = try FileManager.default.contentsOfDirectory(atPath: work.appendingPathComponent("archive/raw").path)
        XCTAssertEqual(raw.count, 2)
        let hits = try await store.search("version"); XCTAssertEqual(hits.count, 2)
        let literal = try await store.search("\" OR NEAR("); XCTAssertTrue(literal.isEmpty)
    }

    func testLargeTranscriptPagesAndPositions() async throws {
        let work = try workspace()
        _ = try source(work, metadata() + (0..<2200).map { message("Item \($0)") }.joined())
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let page = try await store.items(conversationID: "test-session", from: 1001, limit: 9999)
        XCTAssertEqual(page.count, 200); XCTAssertEqual(page[0].text, "Item 1000")
        try await store.savePosition(conversationID: "test-session", ordinal: 1001)
        let position = try await store.position(conversationID: "test-session"); XCTAssertEqual(position, 1001)
        let prior = try await store.precedingPageStart(conversationID: "test-session", before: 1001)
        XCTAssertEqual(prior, 901)
    }

    func testSnapshotExactPrefixAndDiscoveryDoesNotFollowSymlinks() throws {
        let work = try workspace(); let file = try source(work, metadata())
        let outside = work.appendingPathComponent("outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(message("outside").utf8).write(to: outside.appendingPathComponent("rollout-outside.jsonl"))
        try FileManager.default.createSymbolicLink(at: work.appendingPathComponent("codex/sessions/link"), withDestinationURL: outside)
        let source = try CodexSource(root: work.appendingPathComponent("codex")); let files = try source.discover()
        XCTAssertEqual(files.count, 1)
        let snapshot = try SnapshotStore(root: work.appendingPathComponent("archive")).snapshot(source: source, file: files[0])
        XCTAssertEqual(try Data(contentsOf: work.appendingPathComponent("archive/" + snapshot.rawPath)), try Data(contentsOf: file))
    }
    func testInheritedPrefixAndOfflineReparse() async throws {
        let work = try workspace()
        let parentID = "11111111-1111-1111-1111-111111111111"
        let prefix = metadata(parentID) + message("inherited telescope")
        let file = try source(work, prefix + message("excluded suffix"))
        let parent = file.deletingLastPathComponent().appendingPathComponent("rollout-parent-" + parentID + ".jsonl")
        try FileManager.default.moveItem(at: file, to: parent)
        let child = record("session_meta", ["id": "child", "cwd": "/child-project", "history_base": ["thread_id": parentID, "end_byte_offset": prefix.utf8.count, "end_ordinal_exclusive": 2]]) + message("child message")
        try Data(child.utf8).write(to: file)
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        let report = try await store.importDirectory(work.appendingPathComponent("codex"))
        XCTAssertTrue(report.errors.isEmpty)
        var items = try await store.items(conversationID: "child")
        XCTAssertTrue(items.contains { $0.text == "inherited telescope" })
        XCTAssertFalse(items.contains { $0.text == "excluded suffix" })
        XCTAssertTrue(items.contains { $0.text == "child message" })
        try FileManager.default.removeItem(at: work.appendingPathComponent("codex"))
        _ = try await store.reparseArchive()
        items = try await store.items(conversationID: "child")
        XCTAssertTrue(items.contains { $0.text == "inherited telescope" })
    }

    func testLargeOutputPreviewAndCompleteTextPaging() async throws {
        let work = try workspace()
        let output = String(repeating: "log line\n", count: 25000) + "last sentinel"
        _ = try source(work, metadata() + record("response_item", ["type": "function_call_output", "call_id": "call", "output": output]))
        let store = try ArchiveStore(root: work.appendingPathComponent("archive"))
        _ = try await store.importDirectory(work.appendingPathComponent("codex"))
        let items = try await store.items(conversationID: "test-session")
        XCTAssertEqual(items[1].text.count, 12000)
        XCTAssertEqual(items[1].textLength, output.count)
        let end = try await store.textPage(itemID: items[1].id, offset: output.count - 13)
        XCTAssertEqual(end, "last sentinel")
        let hits = try await store.search("sentinel"); XCTAssertEqual(hits.count, 1)
    }

}
