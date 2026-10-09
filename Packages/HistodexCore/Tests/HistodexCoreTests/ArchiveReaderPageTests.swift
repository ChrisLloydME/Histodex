import XCTest
@testable import HistodexCore

final class ArchiveReaderPageTests: XCTestCase {
    private func message(_ id: Int64, role: String, text: String) -> ArchiveItem {
        var item = ArchiveItem(); item.id = id; item.ordinal = Int(id)
        item.kind = .message; item.category = .conversation; item.role = role
        item.text = text; item.textLength = text.count; return item
    }
    func testReaderHandoffPreservesUserAssistantAndSupportingProvenance() {
        var context = message(3, role: "user", text: "Injected instructions")
        context.category = .context
        let rows = ArchiveReaderPage.rows([message(1, role: "user", text: "First line\nSecond line"), message(2, role: "assistant", text: "The answer"), context])
        XCTAssertEqual(rows.map(\.author), [.user, .assistant, .supporting])
        XCTAssertEqual(rows[0].preview, "First line\nSecond line")
        XCTAssertEqual(rows.map(\.id), ["archive.1", "archive.2", "archive.3"])
        XCTAssertEqual(rows[2].entry.items[0].category, .context)
    }
    func testBoundedChatPreviewRetainsOriginalRecordAndFullTextAccess() {
        var value = message(1, role: "assistant", text: String(repeating: "a", count: 12000))
        value.textLength = 200000
        let row = ArchiveReaderPage.rows([value])[0]
        XCTAssertEqual(row.preview.count, 4500)
        XCTAssertTrue(row.isTruncated)
        XCTAssertEqual(row.entry.items[0].textLength, 200000)
        XCTAssertEqual(row.ordinal, 1)
    }
    func testGroupedMessageStillResolvesExactSearchTargetAndAttachments() {
        var first = message(1, role: "assistant", text: "Hello "); first.messageID = "one"
        var second = message(2, role: "assistant", text: "world"); second.messageID = "one"
        let row = ArchiveReaderPage.rows([first, second])[0]
        XCTAssertEqual(row.preview, "Hello world")
        XCTAssertTrue(row.entry.contains(ordinal: 2))
        XCTAssertEqual(row.entry.items.map(\.id), [1, 2])
        XCTAssertEqual(row.id, "archive.1")
    }
}
