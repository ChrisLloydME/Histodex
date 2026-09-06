import AppKit
import HistodexCore

final class TranscriptCell: NSTableCellView {
    private let bubble = NSView()
    private let date = NSTextField(labelWithString: "")
    private let author = NSTextField(labelWithString: "")
    private let disclosure = NSButton(title: "", target: nil, action: nil)
    private let summary = NSTextField(labelWithString: "")
    private let body = NSTextView(usingTextLayoutManager: true)
    private let bodyScroll = NSScrollView()
    private let details = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Message Details")!, target: nil, action: nil)
    private let readMore = NSButton(title: "Read Full Text…", target: nil, action: nil)
    private let attachment = NSButton(title: "", target: nil, action: nil)
    private let preview = NSImageView()
    private var current: TranscriptEntry?
    private var prepared: TranscriptLayout?
    private var thumbnailTask: Task<Void, Never>?
    var onToggle: (() -> Void)?
    var onRead: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        bubble.wantsLayer = true
        date.alignment = .center; date.font = .systemFont(ofSize: 11, weight: .medium); date.textColor = .secondaryLabelColor
        author.font = .systemFont(ofSize: 11); author.textColor = .secondaryLabelColor
        summary.font = .systemFont(ofSize: 12); summary.textColor = .secondaryLabelColor; summary.lineBreakMode = .byTruncatingTail
        body.isEditable = false; body.isSelectable = true; body.drawsBackground = false; body.textContainerInset = .zero; body.textContainer?.lineFragmentPadding = 0
        body.isVerticallyResizable = true; body.isHorizontallyResizable = false; body.autoresizingMask = [.width]; body.textContainer?.widthTracksTextView = true
        bodyScroll.documentView = body; bodyScroll.drawsBackground = false; bodyScroll.autohidesScrollers = true
        disclosure.bezelStyle = .inline; disclosure.font = .systemFont(ofSize: 12, weight: .medium); disclosure.alignment = .left
        disclosure.target = self; disclosure.action = #selector(toggle)
        for button in [details, readMore, attachment] { button.bezelStyle = .inline; button.target = self; button.action = #selector(inspect) }
        details.isBordered = false; details.toolTip = "Message Details"
        readMore.font = .systemFont(ofSize: 12, weight: .medium); attachment.font = .systemFont(ofSize: 12)
        preview.imageScaling = .scaleProportionallyUpOrDown
        for child in [bubble, date, author, details] { addSubview(child) }
        for child in [disclosure, summary, bodyScroll, preview, attachment, readMore] { bubble.addSubview(child) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ entry: TranscriptEntry, layout: TranscriptLayout, archiveRoot: URL) {
        thumbnailTask?.cancel(); preview.image = nil; current = entry; prepared = layout
        date.stringValue = layout.date ?? ""; date.isHidden = layout.date == nil
        author.stringValue = layout.activity ? "" : entry.title; author.isHidden = layout.activity
        disclosure.title = (layout.expanded ? "▾  " : "▸  ") + entry.title
        disclosure.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil); disclosure.imagePosition = .imageLeading
        disclosure.setAccessibilityLabel((layout.expanded ? "Collapse " : "Expand ") + entry.title)
        disclosure.isHidden = !layout.activity; summary.isHidden = !layout.activity; summary.stringValue = entry.summary
        body.textStorage?.setAttributedString(layout.attributedText); bodyScroll.isHidden = layout.textHeight == 0
        bodyScroll.hasVerticalScroller = layout.naturalTextHeight > layout.textHeight
        body.linkTextAttributes = entry.style == .outgoing ? [.foregroundColor: NSColor.white, .underlineStyle: NSUnderlineStyle.single.rawValue] : [.foregroundColor: NSColor.linkColor]
        readMore.isHidden = !layout.truncated || layout.activity && !layout.expanded
        let missing = entry.assets.filter { $0.missingReason != nil }.count
        attachment.title = missing > 0 ? "\(missing) unavailable attachment\(missing == 1 ? "" : "s")…" : "\(entry.assets.count) attachment\(entry.assets.count == 1 ? "" : "s")…"
        attachment.isHidden = layout.attachmentHeight == 0; preview.isHidden = layout.imageHeight == 0
        applyColors()
        if layout.imageHeight > 0, let asset = entry.assets.first(where: { $0.relativePath != nil && $0.mimeType.hasPrefix("image/") }), let path = asset.relativePath {
            let url = archiveRoot.appendingPathComponent(path)
            thumbnailTask = Task { [weak self] in
                let image = await Task.detached(priority: .utility) { Thumbnail.decode(url, pixels: 1000) }.value
                guard !Task.isCancelled, let self else { return }
                if let image { self.preview.image = NSImage(cgImage: image, size: .zero) }
                else { self.attachment.title = "Image preview unavailable…" }
            }
        }
        setAccessibilityLabel(entry.title + ". " + entry.summary); needsLayout = true
    }
    private func applyColors() {
        guard let current, let prepared else { return }
        let outgoing = current.style == .outgoing
        bubble.layer?.backgroundColor = (outgoing ? NSColor.systemBlue : prepared.activity ? NSColor.controlBackgroundColor : NSColor.quaternaryLabelColor.withAlphaComponent(0.09)).cgColor
        bubble.layer?.cornerRadius = prepared.activity ? 10 : 18
        bubble.layer?.borderWidth = prepared.highlighted ? 2 : prepared.activity ? 0.5 : 0
        bubble.layer?.borderColor = (prepared.highlighted ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        for button in [attachment, readMore] { button.contentTintColor = outgoing ? .white : .linkColor }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyColors() }
    override func layout() {
        super.layout(); guard let p = prepared, let current else { return }
        let contentWidth = min(p.bubbleWidth, max(250, bounds.width - 48))
        let x = current.style == .outgoing ? bounds.width - 28 - contentWidth : 28
        let top = bounds.height - p.dateHeight
        date.frame = NSRect(x: 20, y: bounds.height - 30, width: bounds.width - 40, height: 20)
        author.frame = NSRect(x: x + 8, y: top - 20, width: contentWidth - 44, height: 16)
        details.frame = NSRect(x: x + contentWidth - 28, y: p.activity ? 4 + p.bubbleHeight - 25 : top - 22, width: 24, height: 18)
        bubble.frame = NSRect(x: x, y: 4, width: contentWidth, height: p.bubbleHeight)
        var cursor = bubble.bounds.height
        if p.activity {
            disclosure.frame = NSRect(x: 12, y: cursor - 27, width: contentWidth - 48, height: 22)
            summary.frame = NSRect(x: 34, y: cursor - 46, width: contentWidth - 50, height: 18); cursor -= 54
        }
        if p.textHeight > 0 {
            cursor -= 14
            bodyScroll.frame = NSRect(x: 16, y: cursor - p.textHeight, width: contentWidth - 32, height: p.textHeight)
            body.frame.size = NSSize(width: contentWidth - 32, height: max(p.textHeight, p.naturalTextHeight))
            cursor -= p.textHeight + 14
        }
        if p.imageHeight > 0 { preview.frame = NSRect(x: 12, y: cursor - p.imageHeight, width: contentWidth - 24, height: p.imageHeight); cursor -= p.imageHeight }
        if p.attachmentHeight > 0 { attachment.frame = NSRect(x: 12, y: cursor - 28, width: contentWidth - 24, height: 24); cursor -= 32 }
        if !readMore.isHidden { readMore.frame = NSRect(x: 12, y: cursor - 25, width: contentWidth - 24, height: 23) }
    }
    @objc private func toggle() { onToggle?() }
    @objc private func inspect() { onRead?() }
}
