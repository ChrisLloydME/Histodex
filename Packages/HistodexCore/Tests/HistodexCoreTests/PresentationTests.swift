import XCTest
import AppKit
@testable import HistodexCore

final class PresentationTests: XCTestCase {
    private func item(_ id: Int64, kind: ItemKind, role: String = "", text: String = "") -> ArchiveItem {
        var item = ArchiveItem(); item.id = id; item.ordinal = Int(id); item.kind = kind; item.category = kind == .message && ["user", "assistant"].contains(role) ? .conversation : .unknown; item.role = role; item.text = text; item.textLength = text.count; item.timestamp = "2026-09-06T10:00:00Z"; return item
    }
    func testOnlyRoutineBookkeepingIsGrouped() {
        let metadata = item(1, kind: .systemEvent)
        let context = item(2, kind: .systemEvent)
        var warning = item(3, kind: .systemEvent, text: "Missing inherited history"); warning.isDiagnostic = true
        let message = item(4, kind: .message, role: "assistant", text: "The answer")
        let unknown = item(5, kind: .unknown)
        let entries = TranscriptEntry.project([metadata, context, warning, message, unknown])
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].items.count, 2)
        XCTAssertTrue(entries[0].contains(ordinal: 2))
        XCTAssertEqual(entries[1].title, "Archive notice")
        XCTAssertEqual(entries[2].style, .incoming)
        XCTAssertEqual(entries.flatMap(\.items).map(\.id), [1,2,3,4,5])
    }
    func testInstructionsAreNotPresentedAsAssistantAnswers() {
        let rows = TranscriptEntry.project([item(1, kind: .message, role: "user"), item(2, kind: .message, role: "developer"), item(3, kind: .message, role: "assistant")])
        XCTAssertEqual(rows.map(\.style), [.outgoing, .activity, .incoming])
        XCTAssertEqual(rows[1].title, "Instructions")
    }
    func testCommandAndResultTextIsReadableWithoutChangingArchive() {
        let command = item(1, kind: .command, text: #"{"cmd":"swift test","yield_time_ms":1000}"#)
        let result = item(2, kind: .toolResult, text: #"{"content":[{"type":"text","text":"Build succeeded"}]}"#)
        XCTAssertEqual(TranscriptEntry.readableText(command), "swift test")
        XCTAssertEqual(TranscriptEntry.readableText(result), "Build succeeded")
        XCTAssertTrue(command.text.contains("yield_time_ms"))
        let malformed = item(3, kind: .toolResult, text: "{incomplete")
        XCTAssertEqual(TranscriptEntry.readableText(malformed), "{incomplete")
    }
    @MainActor func testCollapsedActivityNeverRendersPayload() {
        let row = TranscriptEntry.project([item(1, kind: .toolResult, text: String(repeating: "Output\n", count: 5000))])[0]
        let collapsed = TranscriptLayout(entry: row, expanded: false, width: 700, date: nil, highlighted: false)
        XCTAssertEqual(collapsed.textHeight, 0)
        XCTAssertEqual(collapsed.attributedText.length, 0)
        XCTAssertLessThan(collapsed.height, 100)
        let expanded = TranscriptLayout(entry: row, expanded: true, width: 700, date: nil, highlighted: false)
        XCTAssertGreaterThan(expanded.textHeight, 0)
        XCTAssertLessThanOrEqual(expanded.textHeight, 900)
        XCTAssertTrue(expanded.truncated)
    }
    @MainActor func testBubbleWidthAndHeightUseTheSameTextGeometry() {
        for width in [480.0, 700.0, 1100.0] {
            for role in ["user", "assistant"] {
                let row = TranscriptEntry.project([item(1, kind: .message, role: role, text: "A short readable message")])[0]
                let layout = TranscriptLayout(entry: row, expanded: false, width: width, date: "Today", highlighted: false)
                XCTAssertLessThan(layout.bubbleWidth, width - 48)
                XCTAssertGreaterThan(layout.bubbleWidth, 100)
                XCTAssertGreaterThanOrEqual(layout.height, layout.dateHeight + layout.textHeight + 30)
                XCTAssertFalse(layout.truncated)
                XCTAssertEqual(layout.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines), "A short readable message")
            }
        }
    }
    @MainActor func testOutputPreviewAndSearchHighlightRemainBounded() {
        var message = item(1, kind: .message, role: "assistant", text: String(repeating: "A", count: 12000))
        message.textLength = 200000
        let layout = TranscriptLayout(entry: TranscriptEntry.project([message])[0], expanded: false, width: 800, date: nil, highlighted: true)
        XCTAssertTrue(layout.highlighted)
        XCTAssertTrue(layout.truncated)
        XCTAssertLessThanOrEqual(layout.attributedText.length, 4501)
        XCTAssertLessThanOrEqual(layout.textHeight, 900)
    }
    @MainActor func testMarkdownTablesSeparateHeaderAndListsIndentWrappedText() {
        let table = NativeMarkdown.render("| Layer | Purpose |\n| --- | --- |\n| Archive | Preservation |")
        XCTAssertTrue(table.string.contains("Layer\tPurpose\t\nArchive"))
        let list = NativeMarkdown.render("- First item with text\n- Second item")
        let style = list.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(style?.headIndent ?? 0, style?.firstLineHeadIndent ?? 0)
        XCTAssertTrue(list.string.contains("•\tFirst item"))
    }
    @MainActor func testOutgoingLinksRemainLegibleAndSelectable() {
        let row = TranscriptEntry.project([item(1, kind: .message, role: "user", text: "See [documentation](https://example.com)")])[0]
        let layout = TranscriptLayout(entry: row, expanded: false, width: 700, date: nil, highlighted: false)
        let range = (layout.attributedText.string as NSString).range(of: "documentation")
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(layout.attributedText.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor, .white)
        XCTAssertNotNil(layout.attributedText.attribute(.link, at: range.location, effectiveRange: nil))
        XCTAssertNotNil(layout.attributedText.attribute(.underlineStyle, at: range.location, effectiveRange: nil))
    }

}
