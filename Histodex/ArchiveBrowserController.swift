import AppKit
import HistodexCore

final class ArchiveBrowserController: NSSplitViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: ArchiveStore
    private let scope: ArchiveScope
    private let sidebar = NSTableView()
    private let transcript = NSTableView()
    private let transcriptScroll = NSScrollView()
    private let search = NSSearchField()
    private let operationProgress = NSProgressIndicator()
    private let operationLabel = NSTextField(wrappingLabelWithString: "")
    private let operationStack = NSStackView()
    private var isPreparingArchive = false
    var onIndexingStateChanged: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    private let empty = ArchiveEmptyView()
    private let libraryCount = NSTextField(labelWithString: "Local archive")
    private let conversationContext = NSTextField(labelWithString: "Conversation archive")
    private let infoButton = NSButton()
    private let latestButton = NSButton(title: "Latest Messages", target: nil, action: nil)
    private let readerStatus = NSTextField(labelWithString: "Choose a conversation to begin")
    private var sidebarRows: [SidebarRow] = []
    private enum SidebarRow { case heading(String), entry(Int) }
    private let sidebarEmpty = NSTextField(wrappingLabelWithString: "No Conversations\n\nImport your history in Settings.")
    private var isUpdatingSidebar = false
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
    private let conversationHeading = NSTextField(labelWithString: "Histodex")

    init(store: ArchiveStore, scope: ArchiveScope = .conversation) { self.store = store; self.scope = scope; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.dividerStyle = .thin; splitView.autosaveName = "ConversationSplit"
        let left = NSViewController()
        let material = NSVisualEffectView()
        material.material = .sidebar; material.blendingMode = .behindWindow
        left.view = material
        let right = NSViewController(); right.view = NSView()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: left)
        sidebarItem.minimumThickness = 260; sidebarItem.maximumThickness = 380
        sidebarItem.preferredThicknessFraction = 0.25; sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)
        let contentItem = NSSplitViewItem(viewController: right)
        contentItem.minimumThickness = 480; addSplitViewItem(contentItem)

        let brand = NSTextField(labelWithString: "Histodex")
        brand.font = .systemFont(ofSize: 21, weight: .bold)
        let importButton = symbolButton("plus", label: "Import History", action: #selector(openSettings))
        let brandRow = NSStackView(views: [brand, NSView(), importButton])
        brandRow.spacing = 12
        search.placeholderString = "Search archive"; search.delegate = self
        search.setAccessibilityIdentifier("archiveSearch")
        search.setAccessibilityLabel("Search conversations and messages")
        configure(sidebar); sidebar.style = .plain; sidebar.rowHeight = 58
        sidebar.selectionHighlightStyle = .regular
        sidebar.intercellSpacing = NSSize(width: 0, height: 2)
        sidebar.setAccessibilityIdentifier("conversationList")
        let sidebarScroll = NSScrollView()
        sidebarScroll.documentView = sidebar; sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true; sidebarScroll.drawsBackground = false
        operationProgress.style = .bar; operationProgress.minValue = 0; operationProgress.maxValue = 1
        operationProgress.setAccessibilityLabel("Archive progress")
        operationLabel.font = .systemFont(ofSize: 11); operationLabel.textColor = .secondaryLabelColor
        operationLabel.maximumNumberOfLines = 1
        operationStack.orientation = .vertical; operationStack.alignment = .leading; operationStack.spacing = 4
        operationStack.addArrangedSubview(operationProgress); operationStack.addArrangedSubview(operationLabel)
        operationStack.isHidden = true
        let settingsButton = symbolButton("gearshape", label: "Archive Settings", action: #selector(openSettings))
        let searchButton = symbolButton("magnifyingglass", label: "Search Archive", action: #selector(searchArchive))
        libraryCount.font = .systemFont(ofSize: 11); libraryCount.textColor = .secondaryLabelColor
        libraryCount.lineBreakMode = .byTruncatingTail
        libraryCount.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [settingsButton, libraryCount, NSView(), searchButton])
        footer.spacing = 8
        let navigation = NSStackView(views: [brandRow, search, operationStack, sidebarScroll, footer])
        navigation.orientation = .vertical; navigation.alignment = .leading; navigation.spacing = 16
        navigation.translatesAutoresizingMaskIntoConstraints = false
        left.view.addSubview(navigation)
        NSLayoutConstraint.activate([
            navigation.topAnchor.constraint(equalTo: left.view.topAnchor, constant: 16),
            navigation.leadingAnchor.constraint(equalTo: left.view.leadingAnchor, constant: 16),
            navigation.trailingAnchor.constraint(equalTo: left.view.trailingAnchor, constant: -12),
            navigation.bottomAnchor.constraint(equalTo: left.view.bottomAnchor, constant: -16),
            brandRow.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            brandRow.heightAnchor.constraint(equalToConstant: 32),
            search.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            sidebarScroll.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            footer.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            footer.heightAnchor.constraint(equalToConstant: 32),
            operationStack.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            operationProgress.widthAnchor.constraint(equalTo: operationStack.widthAnchor),
            operationProgress.heightAnchor.constraint(equalToConstant: 6),
            operationLabel.widthAnchor.constraint(equalTo: operationStack.widthAnchor)
        ])
        sidebarScroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let readingSurface = ArchiveSurfaceView()
        readingSurface.translatesAutoresizingMaskIntoConstraints = false
        right.view.addSubview(readingSurface)
        NSLayoutConstraint.activate([
            readingSurface.topAnchor.constraint(equalTo: right.view.topAnchor, constant: 10),
            readingSurface.leadingAnchor.constraint(equalTo: right.view.leadingAnchor, constant: 10),
            readingSurface.trailingAnchor.constraint(equalTo: right.view.trailingAnchor, constant: -10),
            readingSurface.bottomAnchor.constraint(equalTo: right.view.bottomAnchor, constant: -10)
        ])
        configure(transcript); transcript.style = .plain; transcript.selectionHighlightStyle = .none
        transcript.intercellSpacing = .zero; transcript.setAccessibilityIdentifier("transcriptList")
        transcriptScroll.documentView = transcript; transcriptScroll.hasVerticalScroller = true
        transcriptScroll.autohidesScrollers = true; transcriptScroll.drawsBackground = false
        conversationHeading.font = .systemFont(ofSize: 14, weight: .semibold)
        conversationHeading.alignment = .center; conversationHeading.lineBreakMode = .byTruncatingTail
        conversationHeading.maximumNumberOfLines = 1
        conversationHeading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        conversationContext.font = .systemFont(ofSize: 11); conversationContext.textColor = .secondaryLabelColor
        conversationContext.alignment = .center; conversationContext.lineBreakMode = .byTruncatingMiddle
        conversationContext.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let headings = NSStackView(views: [conversationHeading, conversationContext])
        headings.orientation = .vertical; headings.alignment = .center; headings.spacing = 4
        let archiveIcon = NSImageView(image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Archived conversation")!)
        archiveIcon.contentTintColor = .controlAccentColor
        infoButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Conversation Info")
        infoButton.isBordered = false; infoButton.target = self; infoButton.action = #selector(showConversationInfo)
        infoButton.toolTip = "Conversation Info and All Records"; infoButton.isEnabled = false
        infoButton.setAccessibilityLabel("Conversation Info")
        let header = NSView()
        for child in [archiveIcon, headings, infoButton] { child.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(child) }
        NSLayoutConstraint.activate([
            archiveIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            archiveIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            archiveIcon.widthAnchor.constraint(equalToConstant: 24), archiveIcon.heightAnchor.constraint(equalToConstant: 24),
            infoButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            infoButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            infoButton.widthAnchor.constraint(equalToConstant: 28), infoButton.heightAnchor.constraint(equalToConstant: 28),
            headings.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            headings.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headings.leadingAnchor.constraint(greaterThanOrEqualTo: archiveIcon.trailingAnchor, constant: 12),
            headings.trailingAnchor.constraint(lessThanOrEqualTo: infoButton.leadingAnchor, constant: -12),
            conversationHeading.widthAnchor.constraint(equalTo: headings.widthAnchor),
            conversationContext.widthAnchor.constraint(equalTo: headings.widthAnchor)
        ])
        readerStatus.font = .systemFont(ofSize: 11); readerStatus.textColor = .secondaryLabelColor
        readerStatus.lineBreakMode = .byTruncatingTail
        readerStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        latestButton.bezelStyle = .inline; latestButton.font = .systemFont(ofSize: 12)
        latestButton.target = self; latestButton.action = #selector(latest); latestButton.isEnabled = false
        let readerFooter = NSStackView(views: [readerStatus, NSView(), latestButton]); readerFooter.spacing = 12
        let topRule = NSBox(); topRule.boxType = .separator
        let bottomRule = NSBox(); bottomRule.boxType = .separator
        for child in [header, topRule, transcriptScroll, bottomRule, readerFooter] {
            child.translatesAutoresizingMaskIntoConstraints = false; readingSurface.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: readingSurface.topAnchor),
            header.leadingAnchor.constraint(equalTo: readingSurface.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: readingSurface.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 64),
            topRule.topAnchor.constraint(equalTo: header.bottomAnchor),
            topRule.leadingAnchor.constraint(equalTo: readingSurface.leadingAnchor),
            topRule.trailingAnchor.constraint(equalTo: readingSurface.trailingAnchor),
            transcriptScroll.topAnchor.constraint(equalTo: topRule.bottomAnchor, constant: 12),
            transcriptScroll.leadingAnchor.constraint(equalTo: readingSurface.leadingAnchor),
            transcriptScroll.trailingAnchor.constraint(equalTo: readingSurface.trailingAnchor),
            transcriptScroll.bottomAnchor.constraint(equalTo: bottomRule.topAnchor, constant: -8),
            bottomRule.leadingAnchor.constraint(equalTo: readingSurface.leadingAnchor),
            bottomRule.trailingAnchor.constraint(equalTo: readingSurface.trailingAnchor),
            readerFooter.topAnchor.constraint(equalTo: bottomRule.bottomAnchor, constant: 10),
            readerFooter.leadingAnchor.constraint(equalTo: readingSurface.leadingAnchor, constant: 20),
            readerFooter.trailingAnchor.constraint(equalTo: readingSurface.trailingAnchor, constant: -20),
            readerFooter.bottomAnchor.constraint(equalTo: readingSurface.bottomAnchor, constant: -10),
            readerFooter.heightAnchor.constraint(equalToConstant: 24)
        ])
        transcriptScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: transcriptScroll.contentView)
        empty.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        empty.translatesAutoresizingMaskIntoConstraints = false; readingSurface.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: transcriptScroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: transcriptScroll.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            empty.leadingAnchor.constraint(greaterThanOrEqualTo: readingSurface.leadingAnchor, constant: 24),
            empty.trailingAnchor.constraint(lessThanOrEqualTo: readingSurface.trailingAnchor, constant: -24)
        ])
        sidebarEmpty.alignment = .center; sidebarEmpty.font = .systemFont(ofSize: 13)
        sidebarEmpty.textColor = .secondaryLabelColor
        center(sidebarEmpty, in: sidebarScroll, width: 220)
        search.isEnabled = false
        sidebarEmpty.stringValue = "Updating Archive…"
        isPreparingArchive = true; onIndexingStateChanged?(true)
        showOperationProgress(ImportProgress(completed: 0, total: 0, filename: "", phase: "Preparing index"))
        Task {
            defer { isPreparingArchive = false; showOperationProgress(nil); onIndexingStateChanged?(false) }
            do {
                let report = try await store.reparseArchive(onlyOutdated: true) { [weak self] value in
                    Task { @MainActor in guard let self, self.isPreparingArchive else { return }; self.showOperationProgress(value) }
                }
                if !report.errors.isEmpty { show(ArchiveError.invalidArchive(report.errors.joined(separator: "\n"))) }
                search.isEnabled = true; reloadSidebar()
            } catch { sidebarEmpty.stringValue = "Archive Update Failed"; show(error) }
        }
    }
    func showOperationProgress(_ value: ImportProgress?) {
        operationStack.isHidden = value == nil
        guard let value else { operationProgress.stopAnimation(nil); if let selected { updateHeading(selected) } else { view.window?.subtitle = "" }; return }

        operationLabel.stringValue = value.description
        operationProgress.isIndeterminate = value.fraction == nil
        if let fraction = value.fraction { operationProgress.stopAnimation(nil); operationProgress.doubleValue = fraction }
        else { operationProgress.startAnimation(nil) }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func configure(_ table: NSTableView) {
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))); table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle; table.delegate = self; table.dataSource = self; table.backgroundColor = .clear
    }
    private func center(_ label: NSTextField, in parent: NSView, width: CGFloat) {
        label.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: parent.centerXAnchor), label.centerYAnchor.constraint(equalTo: parent.centerYAnchor), label.widthAnchor.constraint(lessThanOrEqualToConstant: width), label.leadingAnchor.constraint(greaterThanOrEqualTo: parent.leadingAnchor, constant: 20), label.trailingAnchor.constraint(lessThanOrEqualTo: parent.trailingAnchor, constant: -20)])
    }
    func configureWindow(_ window: NSWindow) {
        _ = view
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.toolbar = nil
    }
    private func symbolButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        button.isBordered = false; button.toolTip = label; button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func searchArchive() { focusSearch() }
    @objc private func showConversationInfo() {
        guard let selected, let window = view.window else { return }
        let alert = NSAlert(); alert.messageText = selected.title
        alert.informativeText = "Project: \(selected.project)\nStarted: \(ConversationDates.full(selected.startedAt))\n\(selected.itemCount) conversation items\n\(selected.warningCount) archive notices"
        alert.addButton(withTitle: "Done")
        if scope == .conversation { alert.addButton(withTitle: "Browse All Records…") }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            let controller = ArchiveBrowserController(store: self.store, scope: .allRecords)
            controller.onOpenSettings = self.onOpenSettings
            let recordsWindow = NSWindow(contentViewController: controller)
            controller.configureWindow(recordsWindow)
            recordsWindow.setContentSize(NSSize(width: 1100, height: 760)); recordsWindow.center()
            let wc = NSWindowController(window: recordsWindow); self.detailWindows.append(wc); wc.showWindow(nil)
            controller.select(selected)
        }
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
                let hits = query.isEmpty ? [] : try await store.search(query, scope: scope)
                guard !Task.isCancelled else { return }
                let oldKey = sidebarEntry(at: sidebar.selectedRow)?.key
                isUpdatingSidebar = true
                defer { isUpdatingSidebar = false }
                let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
                let hitConversations = Set(hits.map(\.conversationID))
                results = matches.filter { !hitConversations.contains($0.id) }.map { SidebarEntry(conversation: $0, hit: nil) }
                results += hits.compactMap { hit in byID[hit.conversationID].map { SidebarEntry(conversation: $0, hit: hit) } }
                rebuildSidebarRows(searching: !query.isEmpty)
                libraryCount.stringValue = "\(list.count) conversation\(list.count == 1 ? "" : "s")"
                sidebar.reloadData(); sidebarEmpty.isHidden = !results.isEmpty
                sidebarEmpty.stringValue = query.isEmpty ? "No Conversations\n\nImport your history in Settings." : "No Results\n\nTry another word, project, or date."
                if let index = sidebarRow(where: { $0.key == oldKey }) { sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
                if let current = selected, let fresh = byID[current.id] {
                    selected = fresh; updateHeading(fresh)
                    if sidebar.selectedRow < 0, let index = sidebarRow(where: { $0.conversation.id == fresh.id && $0.hit == nil }) {
                        sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    }
                }
            } catch is CancellationError {} catch { show(error) }
        }
    }
    private func sidebarEntry(at row: Int) -> SidebarEntry? {
        guard sidebarRows.indices.contains(row), case let .entry(index) = sidebarRows[row], results.indices.contains(index) else { return nil }
        return results[index]
    }
    private func sidebarRow(where predicate: (SidebarEntry) -> Bool) -> Int? {
        sidebarRows.indices.first { sidebarEntry(at: $0).map(predicate) ?? false }
    }
    private func rebuildSidebarRows(searching: Bool) {
        sidebarRows.removeAll()
        if searching {
            if !results.isEmpty { sidebarRows.append(.heading("Search Results")) }
            sidebarRows += results.indices.map { .entry($0) }
            return
        }
        // Group by creation day, as in FlowDown, preserving each exact search target separately.
        let groups = Dictionary(grouping: results.indices) { index in
            ConversationDates.date(results[index].conversation.startedAt).map { Calendar.current.startOfDay(for: $0) } ?? .distantPast
        }
        for date in groups.keys.sorted(by: >) {
            let title = date == .distantPast ? "Older Conversations" : Calendar.current.isDateInToday(date) ? "Today" : Calendar.current.isDateInYesterday(date) ? "Yesterday" : date.formatted(date: .abbreviated, time: .omitted)
            sidebarRows.append(.heading(title))
            sidebarRows += (groups[date] ?? []).map { .entry($0) }
        }
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        tableView !== sidebar || sidebarEntry(at: row) != nil
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView === sidebar ? ConversationSelectionRow() : nil
    }
    private var offset: Int { hasEarlier ? 1 : 0 }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === sidebar ? sidebarRows.count : entries.count + offset + (hasLater ? 1 : 0) }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sidebar {
            guard sidebarRows.indices.contains(row) else { return nil }
            if case let .heading(title) = sidebarRows[row] { return ConversationSectionCell(title: title) }
            guard let result = sidebarEntry(at: row) else { return nil }
            let cell = (sidebar.makeView(withIdentifier: .init("session"), owner: self) as? ConversationCell) ?? ConversationCell()
            cell.identifier = .init("session")
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
        if tableView === sidebar {
            if sidebarRows.indices.contains(row), case .heading = sidebarRows[row] { return 30 }
            return 58
        }
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
        guard !isUpdatingSidebar, notification.object as? NSTableView === sidebar, let result = sidebarEntry(at: sidebar.selectedRow) else { return }
        if result.hit == nil && selected?.id == result.conversation.id { return }
        select(result.conversation, target: result.hit?.ordinal)
    }
    private func updateHeading(_ conversation: Conversation) {
        conversationHeading.stringValue = conversation.title
        conversationHeading.toolTip = conversation.title
        view.window?.title = scope == .allRecords ? "Archive Records · " + conversation.title : conversation.title
        view.window?.subtitle = ""
        let project = URL(fileURLWithPath: conversation.project).lastPathComponent
        conversationContext.stringValue = (scope == .allRecords ? "All Records" : "Conversation") + (project.isEmpty ? "" : " · " + project)
        conversationContext.toolTip = conversation.project
        readerStatus.stringValue = scope == .allRecords ? "All archived records" : "Archived conversation · Read only"
        infoButton.isEnabled = true; latestButton.isEnabled = true
    }
    private func select(_ conversation: Conversation, target: Int? = nil) {
        positionTask?.cancel(); generation = UUID(); let token = generation
        empty.isHidden = true
        selected = conversation; updateHeading(conversation); highlightedOrdinal = target; expanded.removeAll()
        applyingPage = true; entries = []; layouts.removeAll(); hasEarlier = false; hasLater = false; transcript.reloadData()
        Task {
            do {
                let saved = scope == .conversation ? try await store.savedPosition(conversationID: conversation.id) : nil
                let start: Int
                if let target { start = try await store.precedingPageStart(conversationID: conversation.id, before: target, limit: 12, scope: scope) }
                else if let saved { start = saved }
                else { start = try await store.precedingPageStart(conversationID: conversation.id, before: Int.max, scope: scope) }
                guard generation == token else { return }
                loadPage(from: start, scrollTo: target, atEnd: target == nil && saved == nil)
            } catch { guard generation == token else { return }; applyingPage = false; show(error) }
        }
    }
    private func loadPage(from ordinal: Int, scrollTo: Int? = nil, atEnd: Bool = false) {
        guard let selected else { return }; generation = UUID(); let token = generation; applyingPage = true
        Task {
            do {
                var items = try await store.items(conversationID: selected.id, from: ordinal, scope: scope)
                if items.isEmpty && ordinal > 0 { items = try await store.items(conversationID: selected.id, scope: scope) }
                let earliest = try await store.items(conversationID: selected.id, limit: 1, scope: scope).first?.ordinal
                let later = try await store.items(conversationID: selected.id, from: (items.last?.ordinal ?? -1) + 1, limit: 1, scope: scope)
                guard generation == token else { return }
                entries = TranscriptEntry.project(items); layouts.removeAll(); hasEarlier = earliest.map { $0 < (items.first?.ordinal ?? 0) } ?? false; hasLater = !later.isEmpty
                if let target = scrollTo, let entry = entries.first(where: { $0.contains(ordinal: target) }) { expanded.insert(entry.id) }
                empty.showNoMessages(allRecords: scope == .allRecords)
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
        Task { do { let start = try await store.precedingPageStart(conversationID: selected.id, before: first.ordinal, scope: scope); guard generation == token else { return }; loadPage(from: start, atEnd: true) } catch { show(error) } }
    }
    @objc private func latest() {
        guard let selected else { return }
        let token = generation
        Task {
            do {
                let start = try await store.precedingPageStart(conversationID: selected.id, before: Int.max, scope: scope)
                guard generation == token else { return }
                loadPage(from: start, atEnd: true)
            } catch { show(error) }
        }
    }
    @objc private func later() { if let last = entries.last?.items.last { loadPage(from: last.ordinal + 1) } }
    @objc private func scrolled() {
        guard scope == .conversation, !applyingPage, let selected else { return }
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
