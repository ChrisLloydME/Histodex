import AppKit
import HistodexCore

final class ArchiveBrowserController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let store: ArchiveStore
    private let sidebar = NSTableView()
    private let transcript = NSTableView()
    private let transcriptScroll = NSScrollView()
    private let search = NSSearchField()
    private let scope = NSSegmentedControl(labels: ["Sessions", "Contents"], trackingMode: .selectOne, target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "Your independent archive")
    private let subtitle = NSTextField(labelWithString: "Import a Codex folder to begin.")
    private let status = NSTextField(labelWithString: "Offline · Source files are read-only")
    private let empty = NSTextField(wrappingLabelWithString: "Keep your development history.\n\nImport a Codex data folder to archive conversations, tools, and images on this Mac.\n\nYour archive remains available when the source is gone.")
    private let previous = NSButton(title: "Previous 100", target: nil, action: nil)
    private let next = NSButton(title: "Next 100", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")
    private var conversations: [Conversation] = []
    private var hits: [SearchHit] = []
    private var page: [ArchiveItem] = []
    private var selected: Conversation?
    private var expanded: Set<Int64> = []
    private var generation = UUID()
    private var searchGeneration = UUID()
    private var detailWindows: [NSWindowController] = []
    private var showingSearch: Bool { scope.selectedSegment == 1 && !search.stringValue.isEmpty }

    init(store: ArchiveStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func loadView() {
        view = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        let left = NSView(); let right = NSView()
        split.addArrangedSubview(left); split.addArrangedSubview(right)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        split.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(split)
        NSLayoutConstraint.activate([split.leadingAnchor.constraint(equalTo: view.leadingAnchor), split.trailingAnchor.constraint(equalTo: view.trailingAnchor), split.topAnchor.constraint(equalTo: view.topAnchor), split.bottomAnchor.constraint(equalTo: view.bottomAnchor), left.widthAnchor.constraint(greaterThanOrEqualToConstant: 260), left.widthAnchor.constraint(lessThanOrEqualToConstant: 420), right.widthAnchor.constraint(greaterThanOrEqualToConstant: 540)])
        let leftWidth = left.widthAnchor.constraint(equalToConstant: 300); leftWidth.priority = .defaultHigh; leftWidth.isActive = true
        search.placeholderString = "Title, project, or date"; search.delegate = self; search.sendsSearchStringImmediately = false
        search.setAccessibilityIdentifier("archiveSearch")
        scope.selectedSegment = 0; scope.target = self; scope.action = #selector(scopeChanged)
        configure(sidebar); sidebar.rowHeight = 76; sidebar.setAccessibilityIdentifier("conversationList")
        let sideScroll = NSScrollView(); sideScroll.hasVerticalScroller = true; sideScroll.documentView = sidebar
        let leftStack = NSStackView(views: [search, scope, sideScroll]); leftStack.orientation = .vertical; leftStack.alignment = .leading; leftStack.spacing = 10
        pin(leftStack, to: left, inset: 14)
        search.widthAnchor.constraint(equalTo: leftStack.widthAnchor).isActive = true
        sideScroll.widthAnchor.constraint(equalTo: leftStack.widthAnchor).isActive = true
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold); titleLabel.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor; subtitle.lineBreakMode = .byTruncatingMiddle
        previous.target = self; previous.action = #selector(previousPage); next.target = self; next.action = #selector(nextPage)
        previous.bezelStyle = .rounded; next.bezelStyle = .rounded; previous.isEnabled = false; next.isEnabled = false
        pageLabel.font = .systemFont(ofSize: 11); pageLabel.textColor = .secondaryLabelColor
        let navigation = NSStackView(views: [previous, next, pageLabel]); navigation.spacing = 10
        configure(transcript); transcript.intercellSpacing = NSSize(width: 0, height: 14); transcript.selectionHighlightStyle = .none
        transcript.setAccessibilityIdentifier("transcriptList")
        transcriptScroll.documentView = transcript; transcriptScroll.hasVerticalScroller = true; transcriptScroll.drawsBackground = false
        transcriptScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: transcriptScroll.contentView)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingMiddle
        let footer = NSStackView(views: [status]); footer.spacing = 8
        let rightStack = NSStackView(views: [titleLabel, subtitle, navigation, transcriptScroll, footer]); rightStack.orientation = .vertical; rightStack.alignment = .leading; rightStack.spacing = 12
        pin(rightStack, to: right, inset: 20)
        for child in [titleLabel, subtitle, transcriptScroll, footer] { child.widthAnchor.constraint(equalTo: rightStack.widthAnchor).isActive = true }
        empty.font = .systemFont(ofSize: 17); empty.textColor = .secondaryLabelColor; empty.alignment = .center
        empty.translatesAutoresizingMaskIntoConstraints = false; right.addSubview(empty)
        NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: transcriptScroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: transcriptScroll.centerYAnchor), empty.widthAnchor.constraint(lessThanOrEqualToConstant: 440), empty.leadingAnchor.constraint(greaterThanOrEqualTo: right.leadingAnchor, constant: 30)])
    }
    override func viewDidLoad() { super.viewDidLoad(); reloadSidebar() }
    override func viewDidLayout() {
        super.viewDidLayout()
        if !page.isEmpty { transcript.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<page.count)) }
    }
    private func configure(_ table: NSTableView) {
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content")))
        table.headerView = nil; table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.delegate = self; table.dataSource = self; table.backgroundColor = .clear
    }
    private func pin(_ child: NSView, to parent: NSView, inset: CGFloat) {
        child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child)
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }
    func focusSearch() { view.window?.makeFirstResponder(search) }
    func controlTextDidChange(_ obj: Notification) { reloadSidebar() }
    @objc private func scopeChanged() { search.placeholderString = scope.selectedSegment == 0 ? "Title, project, or date" : "Search archived contents"; reloadSidebar() }
    private func reloadSidebar() {
        let token = UUID(); searchGeneration = token
        let query = search.stringValue; let searching = showingSearch
        Task {
            do {
                let list = try await store.conversations(filter: searching ? "" : query)
                let results = searching ? try await store.search(query) : []
                guard searchGeneration == token else { return }
                conversations = list; hits = results; sidebar.reloadData()
                if searching && hits.isEmpty { status.stringValue = "No matching archived content" }
                else if searching { status.stringValue = "\(hits.count) results · Select one to jump to its exact item" }
                else { status.stringValue = "\(list.count) archived conversations" }
                if let current = selected, let updated = list.first(where: { $0.id == current.id }) {
                    selected = updated
                    titleLabel.stringValue = updated.title
                    subtitle.stringValue = "\(updated.project) · \(updated.startedAt.prefix(10)) · \(updated.itemCount) archived items" + (updated.warningCount > 0 ? " · \(updated.warningCount) import notices" : "")
                }
            } catch { show(error) }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === sidebar ? (showingSearch ? hits.count : conversations.count) : page.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sidebar {
            let id = NSUserInterfaceItemIdentifier("session")
            let cell = (sidebar.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? NSTableCellView()
            cell.identifier = id
            let label: NSTextField
            if let existing = cell.textField { label = existing }
            else { label = NSTextField(wrappingLabelWithString: ""); cell.textField = label; pin(label, to: cell, inset: 7) }
            let name: String; let detail: String
            if showingSearch { guard row < hits.count else { return nil }; name = hits[row].title; detail = hits[row].snippet }
            else {
                guard row < conversations.count else { return nil }; let c = conversations[row]; name = c.title
                detail = "\(c.startedAt.prefix(10)) · \(URL(fileURLWithPath: c.project).lastPathComponent)\n\(c.itemCount) items" + (c.warningCount > 0 ? " · \(c.warningCount) notices" : "")
            }
            let text = NSMutableAttributedString(string: name + "\n", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
            text.append(NSAttributedString(string: detail, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            label.attributedStringValue = text; label.maximumNumberOfLines = 4
            return cell
        }
        guard row < page.count else { return nil }
        let id = NSUserInterfaceItemIdentifier("transcript")
        let cell = (transcript.makeView(withIdentifier: id, owner: self) as? TranscriptCell) ?? TranscriptCell()
        cell.identifier = id
        let item = page[row]
        cell.configure(item, expanded: expanded.contains(item.id), archiveRoot: store.root)
        cell.onToggle = { [weak self] in
            guard let self else { return }
            if self.expanded.contains(item.id) { self.expanded.remove(item.id) } else { self.expanded.insert(item.id) }
            self.transcript.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
            self.transcript.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        }
        cell.onRead = { [weak self] in self?.openDetail(item) }
        return cell
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView === sidebar { return 82 }
        guard row < page.count else { return 70 }
        return TranscriptCell.height(page[row], expanded: expanded.contains(page[row].id), width: max(300, transcript.bounds.width - 36))
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === sidebar, sidebar.selectedRow >= 0 else { return }
        let row = sidebar.selectedRow
        if showingSearch {
            guard row < hits.count, let conversation = conversations.first(where: { $0.id == hits[row].conversationID }) else { return }
            select(conversation, ordinal: hits[row].ordinal)
        } else { guard row < conversations.count else { return }; select(conversations[row]) }
    }
    private func select(_ conversation: Conversation, ordinal: Int? = nil) {
        selected = conversation; page = []; transcript.reloadData(); expanded.removeAll(); generation = UUID(); let token = generation
        titleLabel.stringValue = conversation.title
        subtitle.stringValue = "\(conversation.project) · \(conversation.startedAt.prefix(10)) · \(conversation.itemCount) archived items" + (conversation.warningCount > 0 ? " · \(conversation.warningCount) import notices" : "")
        Task {
            do {
                let position: Int
                if let ordinal { position = ordinal } else { position = try await store.position(conversationID: conversation.id) }
                guard generation == token else { return }
                loadPage(from: position)
            } catch { show(error) }
        }
    }
    private func loadPage(from ordinal: Int) {
        guard let selected else { return }
        generation = UUID(); let token = generation
        Task {
            do {
                var items = try await store.items(conversationID: selected.id, from: ordinal)
                if items.isEmpty && ordinal > 0 { items = try await store.items(conversationID: selected.id) }
                let hasMore: Bool
                if let last = items.last { hasMore = !(try await store.items(conversationID: selected.id, from: last.ordinal + 1, limit: 1)).isEmpty } else { hasMore = false }
                guard generation == token else { return }
                page = items; transcript.reloadData(); transcriptScroll.contentView.scroll(to: .zero); transcriptScroll.reflectScrolledClipView(transcriptScroll.contentView)
                empty.isHidden = !items.isEmpty
                if items.isEmpty { empty.stringValue = "No items on this page. Use Previous to return to archived content." }
                previous.isEnabled = (items.first?.ordinal ?? ordinal) > 0
                next.isEnabled = hasMore
                pageLabel.stringValue = items.isEmpty ? "" : "Records \(items[0].ordinal + 1)–\(items.last!.ordinal + 1)"
            } catch { show(error) }
        }
    }
    @objc private func previousPage() {
        guard let selected, let first = page.first else { return }
        Task { do { let start = try await store.precedingPageStart(conversationID: selected.id, before: first.ordinal); guard self.selected?.id == selected.id else { return }; loadPage(from: start) } catch { show(error) } }
    }
    @objc private func nextPage() { if let last = page.last { loadPage(from: last.ordinal + 1) } }
    @objc private func scrolled() {
        guard let selected else { return }
        let range = transcript.rows(in: transcript.visibleRect)
        guard range.location != NSNotFound, range.location < page.count else { return }
        let ordinal = page[range.location].ordinal
        Task { try? await store.savePosition(conversationID: selected.id, ordinal: ordinal) }
    }
    func archiveDidChange() {
        reloadSidebar()
        if let selected { select(selected) }
    }
    private func openDetail(_ item: ArchiveItem) {
        detailWindows.removeAll { $0.window?.isVisible != true }
        let controller = ItemDetailController(item: item, store: store)
        let window = NSWindow(contentViewController: controller); window.title = item.toolName.isEmpty ? "Archived \(item.kind.rawValue)" : item.toolName
        window.setContentSize(NSSize(width: 800, height: 700)); window.center()
        let wc = NSWindowController(window: window); detailWindows.append(wc); wc.showWindow(nil)
    }
    private func show(_ error: Error) { status.stringValue = error.localizedDescription; if let window = view.window { NSAlert(error: error).beginSheetModal(for: window) } }
}
