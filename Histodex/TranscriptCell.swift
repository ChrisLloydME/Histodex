import AppKit
import ImageIO
import HistodexCore

final class TranscriptCell: NSTableCellView {
    private let heading = NSTextField(labelWithString: "")
    private let body = NSTextView(usingTextLayoutManager: true)
    private let toggle = NSButton(title: "", target: nil, action: nil)
    private let read = NSButton(title: "Inspect…", target: nil, action: nil)
    private let assetLabel = NSTextField(wrappingLabelWithString: "")
    private let imageViewNative = NSImageView()
    private var thumbnailTask: Task<Void, Never>?
    var onToggle: (() -> Void)?
    var onRead: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.cornerRadius = 9
        heading.font = .systemFont(ofSize: 11, weight: .semibold); heading.textColor = .secondaryLabelColor
        body.isEditable = false; body.isSelectable = true; body.drawsBackground = false
        body.textContainerInset = .zero; body.textContainer?.lineFragmentPadding = 0
        body.isVerticallyResizable = false; body.isHorizontallyResizable = false; body.textContainer?.widthTracksTextView = true
        toggle.bezelStyle = .inline; toggle.target = self; toggle.action = #selector(didToggle)
        read.bezelStyle = .inline; read.target = self; read.action = #selector(didRead)
        assetLabel.font = .systemFont(ofSize: 11); assetLabel.textColor = .secondaryLabelColor; assetLabel.maximumNumberOfLines = 3
        imageViewNative.imageScaling = .scaleProportionallyUpOrDown
        for child in [heading, body, toggle, read, assetLabel, imageViewNative] { addSubview(child) }
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    private var contentHeight: CGFloat = 0
    private var imageHeight: CGFloat = 0
    private var assetHeight: CGFloat = 0
    override func layout() {
        super.layout()
        let width = max(100, bounds.width - 32)
        contentHeight = min(1100, max(24, ceil(body.attributedString().boundingRect(with: NSSize(width: width, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8))
        heading.frame = NSRect(x: 16, y: bounds.height - 31, width: width - 150, height: 17)
        read.frame = NSRect(x: bounds.width - 78, y: bounds.height - 32, width: 62, height: 18)
        toggle.frame = NSRect(x: bounds.width - 154, y: bounds.height - 32, width: 74, height: 18)
        body.frame = NSRect(x: 16, y: bounds.height - 45 - contentHeight, width: width, height: contentHeight)
        imageViewNative.frame = NSRect(x: 16, y: bounds.height - 51 - contentHeight - imageHeight, width: width, height: imageHeight)
        assetLabel.frame = NSRect(x: 16, y: 10, width: width, height: assetHeight)
    }
    private static func text(_ item: ArchiveItem, expanded: Bool) -> String {
        let compact = item.kind != .message
        let limit = expanded ? 12000 : compact ? 260 : 4000
        let s = String(item.text.prefix(limit))
        return item.text.count > limit || item.textLength > item.text.count ? s + "\n… Use Inspect to read all archived text." : s
    }
    private static func attributed(_ item: ArchiveItem, expanded: Bool) -> NSAttributedString {
        NativeMarkdown.render(text(item, expanded: expanded), monospaced: ![.message, .reasoning].contains(item.kind))
    }
    private static func measured(_ item: ArchiveItem, expanded: Bool, width: CGFloat) -> CGFloat {
        let rect = attributed(item, expanded: expanded).boundingRect(with: NSSize(width: max(100, width), height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return min(1100, max(24, ceil(rect.height) + 8))
    }
    static func height(_ item: ArchiveItem, expanded: Bool, width: CGFloat) -> CGFloat {
        let image: CGFloat = item.assets.contains(where: { $0.relativePath != nil && $0.mimeType.hasPrefix("image/") }) ? 220 : 0
        let assets: CGFloat = item.assets.isEmpty ? 0 : 48
        return 62 + measured(item, expanded: expanded, width: width) + image + assets
    }
    func configure(_ item: ArchiveItem, expanded: Bool, archiveRoot: URL) {
        thumbnailTask?.cancel(); imageViewNative.image = nil
        let author = item.role.isEmpty ? item.kind.rawValue : item.role.capitalized
        heading.stringValue = author + (item.toolName.isEmpty ? "" : " · " + item.toolName) + " · #\(item.ordinal + 1)"
        heading.toolTip = item.sourceType + "\n" + item.timestamp
        body.textStorage?.setAttributedString(Self.attributed(item, expanded: expanded))
        contentHeight = Self.measured(item, expanded: expanded, width: max(300, bounds.width - 32))
        toggle.title = expanded ? "Collapse" : "Expand"
        toggle.isHidden = item.kind == .message && item.text.count <= 4000
        layer?.backgroundColor = (item.role == "user" ? NSColor.controlBackgroundColor : NSColor.clear).cgColor
        layer?.borderWidth = item.isDiagnostic ? 1 : 0
        layer?.borderColor = NSColor.separatorColor.cgColor
        assetHeight = item.assets.isEmpty ? 0 : 48
        let missing = item.assets.filter { $0.missingReason != nil }.count
        assetLabel.stringValue = item.assets.isEmpty ? "" : "\(item.assets.count) asset(s)" + (missing > 0 ? " · \(missing) unavailable" : " · Copied into archive") + "\nInspect to browse assets and source provenance."
        imageHeight = 0
        if let asset = item.assets.first(where: { $0.relativePath != nil && $0.mimeType.hasPrefix("image/") }), let path = asset.relativePath {
            imageHeight = 220
            let url = archiveRoot.appendingPathComponent(path)
            thumbnailTask = Task { [weak self] in
                let cg = await Task.detached(priority: .utility) { Thumbnail.decode(url, pixels: 1000) }.value
                guard !Task.isCancelled, let self else { return }
                if let cg { self.imageViewNative.image = NSImage(cgImage: cg, size: .zero) }
                else { self.assetLabel.stringValue += "\nImage could not be decoded; original bytes are preserved." }
            }
        }
        needsLayout = true
    }
    @objc private func didToggle() { onToggle?() }
    @objc private func didRead() { onRead?() }
}

nonisolated enum Thumbnail {
    static func decode(_ url: URL, pixels: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary)
    }
}

final class ItemDetailController: NSViewController {
    let item: ArchiveItem
    let store: ArchiveStore
    private let text = NSTextView(usingTextLayoutManager: true)
    private let pageLabel = NSTextField(labelWithString: "")
    private let previous = NSButton(title: "Previous text page", target: nil, action: nil)
    private let next = NSButton(title: "Next text page", target: nil, action: nil)
    private let assets = NSPopUpButton()
    private let image = NSImageView()
    private let assetInfo = NSTextField(wrappingLabelWithString: "")
    private var offset = 0
    private var imageTask: Task<Void, Never>?
    init(item: ArchiveItem, store: ArchiveStore) { self.item = item; self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView()
        text.isEditable = false; text.isSelectable = true; text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = text
        previous.target = self; previous.action = #selector(back); next.target = self; next.action = #selector(forward)
        let nav = NSStackView(views: [previous, next, pageLabel]); nav.spacing = 12
        let provenance = NSTextField(wrappingLabelWithString: "\(item.sourceType) · \(item.timestamp)\nRaw: \(item.rawPath) · bytes \(item.rawOffset)–\(item.rawOffset + item.rawLength)")
        provenance.font = .systemFont(ofSize: 11); provenance.textColor = .secondaryLabelColor; provenance.isSelectable = true
        for (i, asset) in item.assets.enumerated() { assets.addItem(withTitle: "\(i + 1). \(asset.sourceReference.prefix(90))") }
        assets.target = self; assets.action = #selector(showAsset); assets.isHidden = item.assets.isEmpty
        image.imageScaling = .scaleProportionallyUpOrDown; image.isHidden = item.assets.isEmpty
        assetInfo.font = .systemFont(ofSize: 11); assetInfo.maximumNumberOfLines = 3; assetInfo.isHidden = item.assets.isEmpty
        let stack = NSStackView(views: [provenance, nav, scroll, assets, image, assetInfo]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200), image.widthAnchor.constraint(equalTo: stack.widthAnchor), image.heightAnchor.constraint(equalToConstant: item.assets.isEmpty ? 0 : 220)])
    }
    override func viewDidLoad() { super.viewDidLoad(); loadText(); showAsset() }
    @objc private func back() { offset = max(0, offset - 64000); loadText() }
    @objc private func forward() { offset += 64000; loadText() }
    private func loadText() {
        let requestedOffset = offset
        Task {
            do {
                let value = try await store.textPage(itemID: item.id, offset: requestedOffset)
                guard offset == requestedOffset else { return }
                text.string = value; text.scrollToBeginningOfDocument(nil)
                pageLabel.stringValue = "\(requestedOffset + 1)–\(min(item.textLength, requestedOffset + 64000)) of \(item.textLength) characters"
                previous.isEnabled = requestedOffset > 0; next.isEnabled = requestedOffset + 64000 < item.textLength
            } catch { text.string = error.localizedDescription }
        }
    }
    @objc private func showAsset() {
        imageTask?.cancel(); image.image = nil
        let index = assets.indexOfSelectedItem
        guard item.assets.indices.contains(index) else { return }
        let asset = item.assets[index]
        assetInfo.stringValue = asset.missingReason ?? "\(asset.mimeType) · \(asset.byteSize) bytes · SHA-256 \(asset.hash ?? "")"
        guard let path = asset.relativePath else { return }
        let url = store.root.appendingPathComponent(path)
        imageTask = Task { [weak self] in
            let cg = await Task.detached(priority: .utility) { Thumbnail.decode(url, pixels: 1600) }.value
            guard !Task.isCancelled, let self else { return }
            if let cg { self.image.image = NSImage(cgImage: cg, size: .zero) }
            else { self.assetInfo.stringValue += "\nNo image preview available; original bytes remain archived." }
        }
    }
}
