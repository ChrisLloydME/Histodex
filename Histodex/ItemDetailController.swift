import AppKit
import ImageIO
import HistodexCore

nonisolated enum Thumbnail {
    static func decode(_ url: URL, pixels: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary)
    }
}

final class ItemDetailController: NSViewController {
    private let items: [ArchiveItem]
    private var item: ArchiveItem { items[max(0, records.indexOfSelectedItem)] }
    private let records = NSPopUpButton()
    private let mode = NSSegmentedControl(labels: ["Readable", "Archived Text"], trackingMode: .selectOne, target: nil, action: nil)
    private let provenance = NSTextField(wrappingLabelWithString: "")
    private let initialIndex: Int
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
    init(items: [ArchiveItem], store: ArchiveStore, selectedOrdinal: Int?) {
        self.items = items; self.store = store; initialIndex = items.firstIndex(where: { $0.ordinal == selectedOrdinal }) ?? 0
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView()
        text.isEditable = false; text.isSelectable = true; text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = text
        previous.target = self; previous.action = #selector(back); next.target = self; next.action = #selector(forward)
        let nav = NSStackView(views: [previous, next, pageLabel]); nav.spacing = 12
        for record in items { records.addItem(withTitle: TranscriptEntry.project([record])[0].title + " · " + ConversationDates.full(record.timestamp)) }
        records.selectItem(at: initialIndex); records.target = self; records.action = #selector(recordChanged); records.isHidden = items.count == 1
        mode.selectedSegment = 0; mode.target = self; mode.action = #selector(modeChanged)
        provenance.font = .systemFont(ofSize: 11); provenance.textColor = .secondaryLabelColor; provenance.isSelectable = true
        assets.target = self; assets.action = #selector(showAsset); assets.isHidden = item.assets.isEmpty
        image.imageScaling = .scaleProportionallyUpOrDown; image.isHidden = item.assets.isEmpty
        assetInfo.font = .systemFont(ofSize: 11); assetInfo.maximumNumberOfLines = 3; assetInfo.isHidden = item.assets.isEmpty
        let stack = NSStackView(views: [records, mode, nav, scroll, assets, image, assetInfo, provenance]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), provenance.widthAnchor.constraint(equalTo: stack.widthAnchor), assetInfo.widthAnchor.constraint(equalTo: stack.widthAnchor), assets.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor), records.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200), image.widthAnchor.constraint(equalTo: stack.widthAnchor), image.heightAnchor.constraint(equalToConstant: item.assets.isEmpty ? 0 : 220)])
    }
    override func viewDidLoad() { super.viewDidLoad(); recordChanged() }
    @objc private func recordChanged() {
        offset = 0; assets.removeAllItems()
        for (i, asset) in item.assets.enumerated() { assets.addItem(withTitle: "\(i + 1). \(asset.sourceReference.prefix(90))") }
        assets.isHidden = item.assets.isEmpty; image.isHidden = item.assets.isEmpty; assetInfo.isHidden = item.assets.isEmpty
        provenance.stringValue = "\(item.sourceType) · \(ConversationDates.full(item.timestamp))\n\(item.rawPath) · bytes \(item.rawOffset)–\(item.rawOffset + item.rawLength)"
        loadText(); showAsset()
    }
    @objc private func modeChanged() { loadText() }
    @objc private func back() { offset = max(0, offset - 64000); loadText() }
    @objc private func forward() { offset += 64000; loadText() }
    private func loadText() {
        let requestedOffset = offset; let requestedID = item.id; let readable = mode.selectedSegment == 0
        Task {
            do {
                let value = try await store.textPage(itemID: requestedID, offset: requestedOffset)
                guard offset == requestedOffset, item.id == requestedID, (mode.selectedSegment == 0) == readable else { return }
                var display = item; display.text = value
                if readable {
                    let entry = TranscriptEntry.project([display])[0]
                    text.textStorage?.setAttributedString(NativeMarkdown.render(entry.body, monospaced: entry.usesMonospacedText))
                } else { text.textStorage?.setAttributedString(NSAttributedString(string: value, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.textColor])) }
                text.scrollToBeginningOfDocument(nil)
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
