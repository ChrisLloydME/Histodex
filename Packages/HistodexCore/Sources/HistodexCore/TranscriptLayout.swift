import AppKit

/// One prepared layout is shared by row sizing and rendering. Width changes invalidate the cache.
@MainActor public struct TranscriptLayout {
    public let attributedText: NSAttributedString
    public let bubbleWidth: CGFloat
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
    public var bubbleHeight: CGFloat { height - dateHeight - (activity ? 12 : 30) }

    public init(entry: TranscriptEntry, expanded: Bool, width: CGFloat, date: String?, highlighted: Bool) {
        self.date = date; self.expanded = expanded; self.highlighted = highlighted
        activity = entry.style == .activity
        let available = max(300, width - 64)
        let maximum = min(entry.style == .outgoing ? 600 : 720, available * (entry.style == .outgoing ? 0.80 : 0.93))
        let fullText = entry.body
        let limit = expanded ? 12000 : entry.style == .outgoing ? 1200 : 4500
        let preview = String(fullText.prefix(limit))
        truncated = preview.count < fullText.count || entry.items.contains { $0.textLength > $0.text.count }
        let visible = activity && !expanded ? "" : preview
        let rendered = NativeMarkdown.render(visible, monospaced: entry.usesMonospacedText, preserveLineBreaks: entry.style == .outgoing)
        if entry.style == .outgoing {
            let colored = NSMutableAttributedString(attributedString: rendered)
            colored.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: colored.length))
            colored.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: colored.length))
            colored.enumerateAttribute(.link, in: NSRange(location: 0, length: colored.length)) { value, range, _ in
                if value != nil { colored.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            }
            attributedText = colored
        } else { attributedText = rendered }
        let ideal = ceil(attributedText.boundingRect(with: NSSize(width: maximum - 32, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading]).width) + 34
        bubbleWidth = activity ? maximum : min(maximum, max(entry.assets.isEmpty ? 140 : 280, ideal))
        naturalTextHeight = visible.isEmpty ? 0 : ceil(attributedText.boundingRect(with: NSSize(width: bubbleWidth - 32, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8
        textHeight = min(900, naturalTextHeight)
        let showAssets = !activity || expanded
        imageHeight = showAssets && entry.assets.contains(where: { $0.mimeType.hasPrefix("image/") && $0.relativePath != nil }) ? 220 : 0
        attachmentHeight = showAssets && !entry.assets.isEmpty ? 32 : 0
        let heading: CGFloat = activity ? 54 : 0
        let contentPadding: CGFloat = visible.isEmpty ? 0 : 28
        let readMore: CGFloat = truncated && (!activity || expanded) ? 28 : 0
        height = (date == nil ? 0 : 36) + (activity ? 12 : 30) + heading + contentPadding + textHeight + imageHeight + attachmentHeight + readMore
    }
}

