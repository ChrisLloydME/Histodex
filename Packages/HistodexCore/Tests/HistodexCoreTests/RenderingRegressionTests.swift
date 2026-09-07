import XCTest
import AppKit
@testable import HistodexCore

extension PresentationTests {
    @MainActor func testUserLineBreaksAndLongTableValuesRemainReadable() {
        var item = ArchiveItem(); item.kind = .message; item.category = .conversation; item.role = "user"
        item.text = "First instruction\nSecond instruction\nThird instruction"; item.textLength = item.text.count
        let layout = TranscriptLayout(entry: TranscriptEntry.project([item])[0], expanded: false, width: 600, date: nil, highlighted: false)
        XCTAssertTrue(layout.attributedText.string.contains("First instruction\nSecond instruction\nThird instruction"))
        let value = String(repeating: "a long readable value ", count: 20)
        let table = NativeMarkdown.render("| Name | Description |\n| --- | --- |\n| Example | \(value) |")
        XCTAssertTrue(table.string.contains("Name: Example")); XCTAssertTrue(table.string.contains(value.trimmingCharacters(in: .whitespaces)))
        XCTAssertFalse(table.string.contains("\t"))
    }
    func testMessageIDGroupsBlocksWithoutDeltaFlagsButKeepsOtherMessagesSeparate() {
        func block(_ id: Int64, messageID: String, text: String) -> ArchiveItem {
            var item = ArchiveItem(); item.id = id; item.ordinal = Int(id); item.kind = .message
            item.category = .conversation; item.role = "assistant"; item.messageID = messageID; item.text = text
            return item
        }
        let entries = TranscriptEntry.project([block(1, messageID: "one", text: "Hello "), block(2, messageID: "one", text: "world"), block(3, messageID: "two", text: "Separate answer")])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].body, "Hello world")
        XCTAssertEqual(entries[0].style, .incoming)
        XCTAssertEqual(entries[0].items.map(\.id), [1, 2])
    }

}
