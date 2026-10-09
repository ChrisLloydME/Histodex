import AppKit

/// One prepared layout is shared by row sizing and rendering. Width changes invalidate the cache.
@MainActor public struct TranscriptLayout {
    public let attributedText: NSAttributedString
    public let bubbleWidth: CGFloat
    public let readingWidth: CGFloat
    public let readingInset: CGFloat
    public let textInset: CGFloat
    public let textHeight: CGFloat
    public let naturalTextHeight: CGFloat
    public let imageHeight: CGFloat
    public let attachmentHeight: CGFloat
    public let date: String?
    public let expanded: Bool
    public let activity: Bool
    public let truncated: Bool
    public let highlighted: Bool
    public let height: CGFloat
    public var dateHeight: CGFloat { date == nil ? 0 : 36 }
    public var bubbleHeight: CGFloat { height - dateHeight - (activity ? 16 : 38) }

    public init(entry: TranscriptEntry, expanded: Bool, width: CGFloat, date: String?, highlighted: Bool) {
        self.date = date; self.expanded = expanded; self.highlighted = highlighted
        activity = entry.style == .activity
        // Keep both roles in one centered reading column, even in a very wide window.
        readingWidth = min(800, max(1, width - 64))
        readingInset = max(0, (width - readingWidth) / 2)
        textInset = entry.style == .incoming ? 0 : 12
        let maximum = entry.style == .outgoing ? readingWidth * 0.88 : readingWidth
        let fullText = entry.body
        let limit = expanded ? 12000 : entry.style == .outgoing ? 1200 : 4500
        let preview = String(fullText.prefix(limit))
        truncated = preview.count < fullText.count || entry.items.contains { $0.textLength > $0.text.count }
        let visible = activity && !expanded ? "" : preview
        let rendered = NativeMarkdown.render(visible, monospaced: entry.usesMonospacedText, preserveLineBreaks: entry.style == .outgoing)
        if entry.style == .outgoing {
            let linked = NSMutableAttributedString(attributedString: rendered)
            linked.enumerateAttribute(.link, in: NSRange(location: 0, length: linked.length)) { value, range, _ in
                if value != nil { linked.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            }
            attributedText = linked
        } else { attributedText = rendered }
        let ideal = ceil(attributedText.boundingRect(with: NSSize(width: max(1, maximum - textInset * 2), height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading]).width) + textInset * 2 + 2
        bubbleWidth = entry.style == .outgoing ? min(maximum, max(entry.assets.isEmpty ? 140 : 280, ideal)) : maximum
        naturalTextHeight = visible.isEmpty ? 0 : ceil(attributedText.boundingRect(with: NSSize(width: max(1, bubbleWidth - textInset * 2), height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8
        textHeight = min(900, naturalTextHeight)
        let showAssets = !activity || expanded
        imageHeight = showAssets && entry.assets.contains(where: { $0.mimeType.hasPrefix("image/") && $0.relativePath != nil }) ? 220 : 0
        attachmentHeight = showAssets && !entry.assets.isEmpty ? 32 : 0
        let heading: CGFloat = activity ? 54 : 0
        let contentPadding: CGFloat = visible.isEmpty ? 0 : 24
        let readMore: CGFloat = truncated && (!activity || expanded) ? 28 : 0
        height = (date == nil ? 0 : 36) + (activity ? 16 : 38) + heading + contentPadding + textHeight + imageHeight + attachmentHeight + readMore
    }
}
