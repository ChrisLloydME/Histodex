import AppKit
import Markdown

/// AST to native attributed text. Never evaluates HTML, fetches URLs, or executes code.
@MainActor public enum NativeMarkdown {
    public static func render(_ source: String, monospaced: Bool = false) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3; paragraph.paragraphSpacing = 7
        let base: [NSAttributedString.Key: Any] = [.font: monospaced ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
        if monospaced { return NSAttributedString(string: source, attributes: base) }
        let output = NSMutableAttributedString(string: "")
        func append(_ text: String, _ attributes: [NSAttributedString.Key: Any]) { output.append(NSAttributedString(string: text, attributes: attributes)) }
        func walk(_ node: any Markup, _ attributes: [NSAttributedString.Key: Any], depth: Int = 0) {
            var style = attributes
            if let text = node as? Markdown.Text { append(text.string, style); return }
            if let code = node as? InlineCode { style[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular); style[.backgroundColor] = NSColor.quaternaryLabelColor; append(code.code, style); return }
            if let code = node as? CodeBlock {
                style[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                style[.backgroundColor] = NSColor.controlBackgroundColor
                append(code.code + "\n", style); return
            }
            if let heading = node as? Heading { style[.font] = NSFont.systemFont(ofSize: CGFloat(max(15, 25 - heading.level * 2)), weight: .semibold) }
            if node is Strong { style[.font] = NSFontManager.shared.convert((style[.font] as? NSFont) ?? .systemFont(ofSize: 14), toHaveTrait: .boldFontMask) }
            if node is Emphasis { style[.font] = NSFontManager.shared.convert((style[.font] as? NSFont) ?? .systemFont(ofSize: 14), toHaveTrait: .italicFontMask) }
            if node is Strikethrough { style[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = node as? Markdown.Link, let target = link.destination, let url = URL(string: target), ["https", "http", "mailto"].contains(url.scheme ?? "") {
                style[.link] = url; style[.foregroundColor] = NSColor.linkColor
            }
            if node is BlockQuote { style[.foregroundColor] = NSColor.secondaryLabelColor; append("│ ", style) }
            if node is SoftBreak { append(" ", style); return }
            if node is LineBreak { append("\n", style); return }
            if node is ThematicBreak { append("────────────\n", style); return }
            if let image = node as? Markdown.Image { append("[Image: \(image.plainText)]", style); return }
            if let html = node as? HTMLBlock { append(html.rawHTML, style); return }
            if let html = node as? InlineHTML { append(html.rawHTML, style); return }
            if let list = node as? OrderedList {
                for (index, child) in list.children.enumerated() { append("\(list.startIndex + UInt(index)). ", style); walk(child, style, depth: depth + 1) }
                append("\n", style); return
            }
            if node is UnorderedList {
                for child in node.children { append(String(repeating: "  ", count: depth) + "• ", style); walk(child, style, depth: depth + 1) }
                append("\n", style); return
            }
            if node is Table.Cell { for child in node.children { walk(child, style, depth: depth) }; append("\t", style); return }
            for child in node.children { walk(child, style, depth: depth) }
            if node is Paragraph || node is Heading || node is Table.Row { append("\n", style) }
        }
        walk(Document(parsing: source), base)
        return output
    }
}
