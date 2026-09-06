import AppKit
import HistodexCore

final class ArchiveBrowserController: NSSplitViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate {
    private let store: ArchiveStore
    private let sidebar = NSTableView()
    private let transcript = NSTableView()
    private let transcriptScroll = NSScrollView()
    private let search = NSSearchField()
    private let titleLabel = NSTextField(labelWithString: "Histodex")
    private let subtitle = NSTextField(labelWithString: "")
    private let empty = NSTextField(wrappingLabelWithString: "Select a Conversation\n\nChoose a conversation in the sidebar.\nTo import history, open Histodex → Settings.")
    private let sidebarEmpty = NSTextField(wrappingLabelWithString: "No Conversations\n\nImport your history in Settings.")
    private var allConversations: [Conversation] = []
    private struct SidebarEntry { let conversation: Conversation; let hit: SearchHit?; var key: String { conversation.id + "/" + (hit.map { String($0.id) } ?? "session") } }
    private var results: [SidebarEntry] = []
    private var selected: Conversation?
    private var entries: [TranscriptEntry] = []
    private var expanded: Set<Int64> = []
    private var layouts: [Int64: TranscriptLayout] = [:]
    private var hasEarlier = false
    private var hasLater = false
    private var highlightedOrdinal: Int?
    private var generation = UUID()
    private var searchTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var applyingPage = false
    private var lastWidth: CGFloat = 0
    private var detailWindows: [NSWindowController] = []
    private var headerItem: NSToolbarItem?
    private var infoItem: NSToolbarItem?

    init(store: ArchiveStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.dividerStyle = .thin; splitView.autosaveName = "ConversationSplit"
        let left = NSViewController(); let material = NSVisualEffectView(); material.material = .sidebar; material.blendingMode = .behindWindow; left.view = material
        let right = NSViewController(); right.view = NSView(); right.view.wantsLayer = true
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: left); sidebarItem.minimumThickness = 250; sidebarItem.maximumThickness = 380; sidebarItem.preferredThicknessFraction = 0.28; sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)
        let contentItem = NSSplitViewItem(viewController: right); contentItem.minimumThickness = 480; addSplitViewItem(contentItem)

        search.placeholderString = "Search"; search.delegate = self; search.setAccessibilityIdentifier("archiveSearch"); search.setAccessibilityLabel("Search conversations and messages")
        search.translatesAutoresizingMaskIntoConstraints = false; left.view.addSubview(search)
        configure(sidebar); sidebar.style = .sourceList; sidebar.rowHeight = 78; sidebar.intercellSpacing = NSSize(width: 0, height: 2); sidebar.setAccessibilityIdentifier("conversationList")
        let sidebarScroll = NSScrollView(); sidebarScroll.documentView = sidebar; sidebarScroll.hasVerticalScroller = true; sidebarScroll.drawsBackground = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false; left.view.addSubview(sidebarScroll)
        NSLayoutConstraint.activate([search.topAnchor.constraint(equalTo: left.view.topAnchor, constant: 10), search.leadingAnchor.constraint(equalTo: left.view.leadingAnchor, constant: 12), search.trailingAnchor.constraint(equalTo: left.view.trailingAnchor, constant: -12), sidebarScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10), sidebarScroll.leadingAnchor.constraint(equalTo: left.view.leadingAnchor), sidebarScroll.trailingAnchor.constraint(equalTo: left.view.trailingAnchor), sidebarScroll.bottomAnchor.constraint(equalTo: left.view.bottomAnchor)])
        configure(transcript); transcript.style = .plain; transcript.selectionHighlightStyle = .none; transcript.intercellSpacing = .zero; transcript.setAccessibilityIdentifier("transcriptList")
        transcriptScroll.documentView = transcript; transcriptScroll.hasVerticalScroller = true; transcriptScroll.drawsBackground = false
        fill(transcriptScroll, in: right.view)
        transcriptScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: transcriptScroll.contentView)
        empty.alignment = .center; empty.font = .systemFont(ofSize: 14); empty.textColor = .secondaryLabelColor
        sidebarEmpty.alignment = .center; sidebarEmpty.font = .systemFont(ofSize: 13); sidebarEmpty.textColor = .secondaryLabelColor
        center(empty, in: right.view, width: 350); center(sidebarEmpty, in: left.view, width: 220)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold); titleLabel.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor; subtitle.lineBreakMode = .byTruncatingMiddle
        reloadSidebar()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func configure(_ table: NSTableView) {
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))); table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle; table.delegate = self; table.dataSource = self; table.backgroundColor = .clear
    }
    private func fill(_ child: NSView, in parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child)
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor), child.topAnchor.constraint(equalTo: parent.topAnchor), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)])
    }
    private func center(_ label: NSTextField, in parent: NSView, width: CGFloat) {
        label.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: parent.centerXAnchor), label.centerYAnchor.constraint(equalTo: parent.centerYAnchor), label.widthAnchor.constraint(lessThanOrEqualToConstant: width), label.leadingAnchor.constraint(greaterThanOrEqualTo: parent.leadingAnchor, constant: 20), label.trailingAnchor.constraint(lessThanOrEqualTo: parent.trailingAnchor, constant: -20)])
    }
    func configureWindow(_ window: NSWindow) {
        _ = view
        window.toolbarStyle = .unified; window.titleVisibility = .hidden
        let toolbar = NSToolbar(identifier: "Conversations"); toolbar.delegate = self; toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false; window.toolbar = toolbar
    }
    private static let headingID = NSToolbarItem.Identifier("ConversationHeading")
    private static let separatorID = NSToolbarItem.Identifier("ConversationSeparator")
    private static let infoID = NSToolbarItem.Identifier("ConversationInfo")
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.toggleSidebar, Self.separatorID, Self.headingID, .flexibleSpace, Self.infoID] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == Self.separatorID { return NSTrackingSeparatorToolbarItem(identifier: id, splitView: splitView, dividerIndex: 0) }
        if id == Self.headingID {
            let item = NSToolbarItem(itemIdentifier: id)
            let stack = NSStackView(views: [titleLabel, subtitle]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 1
            stack.widthAnchor.constraint(equalToConstant: 320).isActive = true
            item.view = stack; item.label = "Conversation"; headerItem = item; return item
        }
        if id == Self.infoID {
            let item = NSToolbarItem(itemIdentifier: id); item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Conversation Info")
            item.autovalidates = false; item.label = "Conversation Info"; item.toolTip = "Conversation Info"; item.target = self; item.action = #selector(showConversationInfo); item.isEnabled = selected != nil; infoItem = item; return item
        }
        return nil
    }
    @objc private func showConversationInfo() {
        guard let selected, let window = view.window else { return }
        let alert = NSAlert(); alert.messageText = selected.title
        alert.informativeText = "Project: \(selected.project)\nStarted: \(ConversationDates.full(selected.startedAt))\n\(selected.itemCount) archived records\n\(selected.warningCount) archive notices"
        alert.beginSheetModal(for: window)
    }
    func focusSearch() { if splitViewItems[0].isCollapsed { splitViewItems[0].isCollapsed = false }; view.window?.makeFirstResponder(search) }
    func controlTextDidChange(_ obj: Notification) { reloadSidebar(debounce: true) }
    private func reloadSidebar(debounce: Bool = false) {
        searchTask?.cancel(); let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task {
            do {
                if debounce { try await Task.sleep(for: .milliseconds(180)) }
                let list = try await store.conversations()
                let matches = query.isEmpty ? list : try await store.conversations(filter: query)
                let hits = query.isEmpty ? [] : try await store.search(query)
                guard !Task.isCancelled else { return }
                let oldKey = results.indices.contains(sidebar.selectedRow) ? results[sidebar.selectedRow].key : nil
                allConversations = list
                let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
                let hitConversations = Set(hits.map(\.conversationID))
                results = matches.filter { !hitConversations.contains($0.id) }.map { SidebarEntry(conversation: $0, hit: nil) }
                results += hits.compactMap { hit in byID[hit.conversationID].map { SidebarEntry(conversation: $0, hit: hit) } }
                sidebar.reloadData(); sidebarEmpty.isHidden = !results.isEmpty
                sidebarEmpty.stringValue = query.isEmpty ? "No Conversations\n\nImport your history in Settings." : "No Results\n\nTry another word, project, or date."
                if let index = results.firstIndex(where: { $0.key == oldKey }) { sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
                if let current = selected, let fresh = byID[current.id] { selected = fresh; updateHeading(fresh) }
            } catch is CancellationError {} catch { show(error) }
        }
    }
    private var offset: Int { hasEarlier ? 1 : 0 }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === sidebar ? results.count : entries.count + offset + (hasLater ? 1 : 0) }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sidebar {
            guard results.indices.contains(row) else { return nil }
            let cell = (sidebar.makeView(withIdentifier: .init("session"), owner: self) as? ConversationCell) ?? ConversationCell()
            cell.identifier = .init("session"); let result = results[row]
            cell.configure(result.conversation, snippet: result.hit?.snippet); return cell
        }
        let index = row - offset
        guard entries.indices.contains(index) else {
            let button = NSButton(title: row == 0 && hasEarlier ? "Show Earlier Messages" : "Show Later Messages", target: self, action: row == 0 && hasEarlier ? #selector(earlier) : #selector(later))
            button.bezelStyle = .inline; button.font = .systemFont(ofSize: 12); button.contentTintColor = .linkColor
            return button
        }
        let entry = entries[index]
        let cell = (transcript.makeView(withIdentifier: .init("transcript"), owner: self) as? TranscriptCell) ?? TranscriptCell()
        cell.identifier = .init("transcript")
        cell.configure(entry, layout: layout(at: index), archiveRoot: store.root)
        cell.onToggle = { [weak self] in self?.toggle(entry.id) }
        cell.onRead = { [weak self] in self?.openDetail(entry, preferredOrdinal: self?.highlightedOrdinal) }
        return cell
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView === sidebar { return 78 }
        let index = row - offset
        return entries.indices.contains(index) ? layout(at: index).height : 44
    }
    private func layout(at index: Int) -> TranscriptLayout {
        let entry = entries[index]
        if let cached = layouts[entry.id] { return cached }
        let previous = index > 0 ? entries[index - 1].items.last?.timestamp : nil
        let date = ConversationDates.separator(entry.items[0].timestamp, after: previous)
        let layout = TranscriptLayout(entry: entry, expanded: expanded.contains(entry.id), width: max(440, transcript.bounds.width), date: date, highlighted: highlightedOrdinal.map(entry.contains) ?? false)
        layouts[entry.id] = layout; return layout
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        if abs(transcript.bounds.width - lastWidth) > 1 { lastWidth = transcript.bounds.width; invalidateLayouts() }
    }
    private func invalidateLayouts() {
        layouts.removeAll()
        guard !entries.isEmpty else { return }
        transcript.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<numberOfRows(in: transcript)))
        let visible = transcript.rows(in: transcript.visibleRect).indexSet.intersection(IndexSet(integersIn: 0..<numberOfRows(in: transcript)))
        transcript.reloadData(forRowIndexes: visible, columnIndexes: IndexSet(integer: 0))
    }
    private func toggle(_ id: Int64) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        layouts.removeValue(forKey: id)
        let row = index + offset
        transcript.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row)); transcript.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === sidebar, results.indices.contains(sidebar.selectedRow) else { return }
        let result = results[sidebar.selectedRow]
        if result.hit == nil && selected?.id == result.conversation.id { return }
        select(result.conversation, target: result.hit?.ordinal)
    }
    private func updateHeading(_ conversation: Conversation) {
        titleLabel.stringValue = conversation.title; subtitle.stringValue = URL(fileURLWithPath: conversation.project).lastPathComponent
        titleLabel.toolTip = conversation.title; subtitle.toolTip = conversation.project; view.window?.title = conversation.title; infoItem?.isEnabled = true
    }
    private func select(_ conversation: Conversation, target: Int? = nil) {
        positionTask?.cancel(); generation = UUID(); let token = generation
        selected = conversation; updateHeading(conversation); highlightedOrdinal = target; expanded.removeAll()
        applyingPage = true; entries = []; layouts.removeAll(); hasEarlier = false; hasLater = false; transcript.reloadData()
        Task {
            do {
                let saved = try await store.savedPosition(conversationID: conversation.id)
                let start: Int
                if let target { start = try await store.precedingPageStart(conversationID: conversation.id, before: target, limit: 12) }
                else if let saved { start = saved }
                else { start = try await store.precedingPageStart(conversationID: conversation.id, before: Int.max) }
                guard generation == token else { return }
                loadPage(from: start, scrollTo: target, atEnd: target == nil && saved == nil)
            } catch { guard generation == token else { return }; applyingPage = false; show(error) }
        }
    }
    private func loadPage(from ordinal: Int, scrollTo: Int? = nil, atEnd: Bool = false) {
        guard let selected else { return }; generation = UUID(); let token = generation; applyingPage = true
        Task {
            do {
                var items = try await store.items(conversationID: selected.id, from: ordinal)
                if items.isEmpty && ordinal > 0 { items = try await store.items(conversationID: selected.id) }
                let earliest = try await store.items(conversationID: selected.id, limit: 1).first?.ordinal
                let later = try await store.items(conversationID: selected.id, from: (items.last?.ordinal ?? -1) + 1, limit: 1)
                guard generation == token else { return }
                entries = TranscriptEntry.project(items); layouts.removeAll(); hasEarlier = earliest.map { $0 < (items.first?.ordinal ?? 0) } ?? false; hasLater = !later.isEmpty
                if let target = scrollTo, let entry = entries.first(where: { $0.contains(ordinal: target) }) { expanded.insert(entry.id) }
                transcript.reloadData(); view.layoutSubtreeIfNeeded(); empty.isHidden = !items.isEmpty
                if let target = scrollTo, let index = entries.firstIndex(where: { $0.contains(ordinal: target) }) { transcript.scrollRowToVisible(index + offset) }
                else if atEnd && !entries.isEmpty { transcript.scrollRowToVisible(entries.count - 1 + offset) }
                else { transcriptScroll.contentView.scroll(to: .zero); transcriptScroll.reflectScrolledClipView(transcriptScroll.contentView) }
                applyingPage = false
            } catch { guard generation == token else { return }; applyingPage = false; show(error) }
        }
    }
    @objc private func earlier() {
        guard let selected, let first = entries.first?.items.first else { return }
        let token = generation
        Task { do { let start = try await store.precedingPageStart(conversationID: selected.id, before: first.ordinal); guard generation == token else { return }; loadPage(from: start, atEnd: true) } catch { show(error) } }
    }
    @objc private func later() { if let last = entries.last?.items.last { loadPage(from: last.ordinal + 1) } }
    @objc private func scrolled() {
        guard !applyingPage, let selected else { return }
        let row = transcript.rows(in: transcript.visibleRect).location - offset
        guard entries.indices.contains(row) else { return }
        let ordinal = entries[row].items[0].ordinal; positionTask?.cancel()
        positionTask = Task { do { try await Task.sleep(for: .milliseconds(250)); try await store.savePosition(conversationID: selected.id, ordinal: ordinal) } catch {} }
    }
    func archiveDidChange() {
        detailWindows.forEach { $0.close() }; detailWindows.removeAll()
        reloadSidebar(); if let selected { select(selected) }
    }
    private func openDetail(_ entry: TranscriptEntry, preferredOrdinal: Int?) {
        detailWindows.removeAll { $0.window?.isVisible != true }
        let controller = ItemDetailController(items: entry.items, store: store, selectedOrdinal: preferredOrdinal)
        let window = NSWindow(contentViewController: controller); window.title = entry.title; window.setContentSize(NSSize(width: 800, height: 700)); window.center()
        let wc = NSWindowController(window: window); detailWindows.append(wc); wc.showWindow(nil)
    }
    private func show(_ error: Error) { if let window = view.window { NSAlert(error: error).beginSheetModal(for: window) } }
}

private extension NSRange {
    var indexSet: IndexSet { location == NSNotFound || length == 0 ? [] : IndexSet(integersIn: location..<(location + length)) }
}

@MainActor enum ConversationDates {
    private static let iso = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions.insert(.withFractionalSeconds); return f }()
    static func date(_ value: String) -> Date? { fractional.date(from: value) ?? iso.date(from: value) }
    static func full(_ value: String) -> String { date(value)?.formatted(date: .abbreviated, time: .shortened) ?? value }
    static func short(_ value: String) -> String {
        guard let date = date(value) else { return "" }
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    static func separator(_ value: String, after previous: String?) -> String? {
        guard let date = date(value) else { return nil }
        if let previous, let prior = self.date(previous), Calendar.current.isDate(date, inSameDayAs: prior), abs(date.timeIntervalSince(prior)) < 900 { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

final class ConversationCell: NSTableCellView {
    private let avatar = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private let preview = NSTextField(wrappingLabelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        avatar.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil); avatar.symbolConfiguration = .init(pointSize: 18, weight: .medium); avatar.contentTintColor = .secondaryLabelColor
        name.font = .systemFont(ofSize: 13, weight: .semibold); name.lineBreakMode = .byTruncatingTail
        date.font = .systemFont(ofSize: 11); date.alignment = .right
        preview.font = .systemFont(ofSize: 12); preview.maximumNumberOfLines = 2; preview.lineBreakMode = .byTruncatingTail
        for child in [avatar, name, date, preview] { addSubview(child) }; textField = name
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout(); let width = bounds.width
        avatar.frame = NSRect(x: 12, y: 25, width: 32, height: 32)
        name.frame = NSRect(x: 54, y: bounds.height - 28, width: max(40, width - 130), height: 18)
        date.frame = NSRect(x: width - 74, y: bounds.height - 27, width: 62, height: 16)
        preview.frame = NSRect(x: 54, y: 10, width: max(40, width - 66), height: 34)
    }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { updateColors() } }
    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        name.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        for field in [date, preview] { field.textColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor }
        avatar.contentTintColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
    func configure(_ conversation: Conversation, snippet: String?) {
        name.stringValue = conversation.title; name.toolTip = conversation.title; date.stringValue = ConversationDates.short(conversation.updatedAt)
        let project = URL(fileURLWithPath: conversation.project).lastPathComponent
        preview.stringValue = snippet ?? (project + "\n" + conversation.preview.replacingOccurrences(of: "\n", with: " "))
        setAccessibilityLabel(conversation.title + ", " + (snippet ?? project)); updateColors()
    }
}
