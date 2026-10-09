import AppKit
import HistodexCore

/// AppKit reading surface; FlowDown's Catalyst layout is the design reference.
final class ArchiveSurfaceView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        }
    }
}

final class ArchiveEmptyView: NSView {
    private let title = NSTextField(labelWithString: "Your Conversation Archive")
    private let message = NSTextField(wrappingLabelWithString: "Choose a conversation in the sidebar, or import your Codex history to start reading.")
    private let button = NSButton(title: "Open Archive Settings…", target: nil, action: nil)
    var onOpenSettings: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        let icon = NSImageView(image: NSImage(systemSymbolName: "books.vertical", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 38, weight: .light)
        icon.contentTintColor = .secondaryLabelColor
        title.font = .systemFont(ofSize: 20, weight: .semibold); title.alignment = .center
        message.font = .systemFont(ofSize: 13); message.textColor = .secondaryLabelColor; message.alignment = .center
        button.bezelStyle = .rounded; button.target = self; button.action = #selector(openSettings)
        let stack = NSStackView(views: [icon, title, message, button])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor), message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            icon.heightAnchor.constraint(equalToConstant: 48), icon.widthAnchor.constraint(equalToConstant: 48)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func showNoMessages(allRecords: Bool) {
        title.stringValue = allRecords ? "No Archived Records" : "No Conversation Messages"
        message.stringValue = allRecords ? "This conversation has no records in the archive." : "Open Conversation Info to browse supporting records, including commands and reasoning."
        button.isHidden = true
    }
    @objc private func openSettings() { onOpenSettings?() }
}

final class ConversationSelectionRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.15 : 0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

final class ConversationSectionCell: NSTableCellView {
    init(title: String) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium); label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false; addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true); setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class ConversationCell: NSTableCellView {
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let context = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 20, weight: .regular); icon.contentTintColor = .controlAccentColor
        name.font = .systemFont(ofSize: 13, weight: .medium); name.lineBreakMode = .byTruncatingTail
        context.font = .systemFont(ofSize: 11); context.textColor = .secondaryLabelColor; context.lineBreakMode = .byTruncatingTail
        for child in [icon, name, context] { addSubview(child) }
        textField = name
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 12, y: (bounds.height - 24) / 2, width: 24, height: 24)
        name.frame = NSRect(x: 48, y: bounds.height - 27, width: max(0, bounds.width - 60), height: 18)
        context.frame = NSRect(x: 48, y: 10, width: max(0, bounds.width - 60), height: 15)
    }
    func configure(_ conversation: Conversation, snippet: String?) {
        name.stringValue = conversation.title; name.toolTip = conversation.title
        let project = URL(fileURLWithPath: conversation.project).lastPathComponent
        context.stringValue = snippet?.replacingOccurrences(of: "\n", with: " ") ?? [project, ConversationDates.short(conversation.updatedAt)].filter { !$0.isEmpty }.joined(separator: " · ")
        context.toolTip = snippet ?? conversation.project
        setAccessibilityLabel(conversation.title + ", " + context.stringValue)
    }
}
