import Combine
import HistodexCore
import LanguageModelChatUI
import SnapKit
import UIKit

/// Archive orchestration around FlowDown's reused shell and ChatViewController.
public final class ArchiveRootController: MainController, UISearchBarDelegate, SearchControllerOpenButton.Delegate, ChatViewControllerMenuDelegate {
    private let store: ArchiveStore
    private let scope: ArchiveScope
    private var conversations: [Conversation] = []
    private var selected: Conversation?
    private var selectedKey: String?
    private var rows: [ArchiveReaderRow] = []
    private var chat: ChatViewController?
    private var chatStorage: ArchiveChatStorage?
    private var generation = UUID()
    private var sidebarTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var isApplyingPage = false
    private var hasEarlier = false
    private var hasLater = false
    private let previous = UIButton(type: .system)
    private let nextPageButton = UIButton(type: .system)
    private let latest = UIButton(type: .system)
    private let pageStatus = UILabel()
    private let chatContainer = UIView()
    private let empty = UILabel()
    private let sidebarEmpty = UILabel()
    private let settings: ArchiveSettingsController
    private var isIndexing = false
    private var archiveObserver: NSObjectProtocol?
    public var onOpenRecords: ((String) -> Void)?
    public var onConversationTitleChanged: ((String) -> Void)?

    public init(store: ArchiveStore, scope: ArchiveScope = .conversation) {
        self.store = store; self.scope = scope
        settings = ArchiveSettingsController(store: store)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override public func viewDidLoad() {
        super.viewDidLoad()
        sidebar.searchButton.delegate = self
        sidebar.searchBar.delegate = self
        sidebar.settingButton.onOpenSettings = { [weak self] in self?.openSettings() }
        sidebar.newChatButton.addAction(UIAction { [weak self] _ in self?.openSettings() }, for: .touchUpInside)
        sidebar.conversationSelectionView.onSelect = { [weak self] item in
            guard let self, let conversation = conversations.first(where: { $0.id == item.conversationID }) else { return }
            selectedKey = item.id; select(conversation, target: item.ordinal)
        }
        sidebar.conversationSelectionView.menuProvider = { [weak self] id in
            guard let self else { return nil }
            return UIMenu(children: [UIAction(title: "Copy Conversation Title", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                guard let self, let conversation = conversations.first(where: { id == $0.id || id.hasPrefix($0.id + "/") }) else { return }
                UIPasteboard.general.string = conversation.title
            }])
        }
        contentView.contentView.addSubview(chatContainer)
        let footer = UIStackView(arrangedSubviews: [previous, nextPageButton, UIView(), pageStatus, latest])
        footer.spacing = 12; footer.alignment = .center
        contentView.contentView.addSubview(footer)
        chatContainer.snp.makeConstraints { make in make.left.top.right.equalToSuperview(); make.bottom.equalTo(footer.snp.top).offset(-8) }
        footer.snp.makeConstraints { make in make.left.right.equalToSuperview().inset(20); make.bottom.equalToSuperview().inset(8); make.height.equalTo(32) }
        for (button, title) in [(previous, "Earlier"), (nextPageButton, "Later"), (latest, scope == .conversation ? "Latest Messages" : "Latest Records")] {
            button.setTitle(title, for: .normal); button.titleLabel?.font = .preferredFont(forTextStyle: .caption1); button.isEnabled = false
        }
        previous.addAction(UIAction { [weak self] _ in self?.earlier() }, for: .touchUpInside)
        nextPageButton.addAction(UIAction { [weak self] _ in self?.later() }, for: .touchUpInside)
        latest.addAction(UIAction { [weak self] _ in self?.latestPage() }, for: .touchUpInside)
        pageStatus.font = .preferredFont(forTextStyle: .caption1); pageStatus.textColor = .secondaryLabel; pageStatus.text = "Read-only archive"
        empty.numberOfLines = 0; empty.textAlignment = .center; empty.textColor = .secondaryLabel
        empty.text = "Select a Conversation\n\nChoose a conversation in the sidebar.\nUse + or Settings to import your history."
        chatContainer.addSubview(empty)
        empty.snp.makeConstraints { make in make.center.equalToSuperview(); make.width.lessThanOrEqualTo(360); make.left.greaterThanOrEqualToSuperview().inset(24); make.right.lessThanOrEqualToSuperview().inset(24) }
        sidebarEmpty.numberOfLines = 0; sidebarEmpty.textAlignment = .center; sidebarEmpty.textColor = .secondaryLabel; sidebarEmpty.font = .preferredFont(forTextStyle: .caption1)
        sidebar.conversationSelectionView.addSubview(sidebarEmpty)
        sidebarEmpty.snp.makeConstraints { make in make.center.equalToSuperview(); make.left.right.equalToSuperview().inset(12) }
        settings.onProgress = { [weak self] progress in self?.displayProgress(progress) }
        archiveObserver = NotificationCenter.default.addObserver(forName: .archiveDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.archiveChanged() }
        }
        if scope == .conversation { prepareIndex() } else { reloadSidebar() }
    }
    private func prepareIndex() {
        isIndexing = true; settings.setExternalBusy(true); sidebarEmpty.text = "Updating Archive…"
        sidebar.searchBar.isUserInteractionEnabled = false
        Task {
            defer { isIndexing = false; settings.setExternalBusy(false); sidebar.searchBar.isUserInteractionEnabled = true; displayProgress(nil) }
            do {
                let report = try await store.reparseArchive(onlyOutdated: true) { [weak self] progress in
                    Task { @MainActor in guard let self, self.isIndexing else { return }; self.displayProgress(progress) }
                }
                reloadSidebar()
                if !report.errors.isEmpty { showError(ArchiveError.invalidArchive(report.errors.joined(separator: "\n"))) }
            } catch { sidebarEmpty.text = "Archive Update Failed"; showError(error) }
        }
    }
    private func displayProgress(_ value: ImportProgress?) {
        sidebar.syncIndicator.text = value?.description ?? "\(conversations.count) conversations"
        sidebar.syncIndicator.accessibilityLabel = sidebar.syncIndicator.text
    }
    public func openSettings() {
        guard presentedViewController == nil else { return }
        let navigation = UINavigationController(rootViewController: settings)
        navigation.modalPresentationStyle = .formSheet; navigation.preferredContentSize = CGSize(width: 620, height: 620)
        present(navigation, animated: true)
    }
    public func focusSearch() { sidebar.showSearch() }
    func searchButtonDidTap() { focusSearch() }
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { reloadSidebar(debounce: true) }
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
    override public var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(title: "Search Archive", action: #selector(searchFromKeyboard), input: "f", modifierFlags: .command), UIKeyCommand(title: "Settings…", action: #selector(settingsFromKeyboard), input: ",", modifierFlags: .command)]
    }
    @objc private func searchFromKeyboard() { focusSearch() }
    @objc private func settingsFromKeyboard() { openSettings() }

    private func reloadSidebar(debounce: Bool = false) {
        sidebarTask?.cancel()
        let query = (sidebar.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        sidebarTask = Task {
            do {
                if debounce { try await Task.sleep(for: .milliseconds(180)) }
                let list = try await store.conversations()
                let matches = query.isEmpty ? list : try await store.conversations(filter: query)
                let hits = query.isEmpty ? [] : try await store.search(query, scope: scope)
                guard !Task.isCancelled else { return }
                conversations = list
                let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
                let hitIDs = Set(hits.map(\.conversationID))
                var items = matches.filter { !hitIDs.contains($0.id) }.map { conversation in
                    ArchiveSidebarItem(id: conversation.id, conversationID: conversation.id, displayTitle: conversation.title, accessibilityLabel: conversation.title + ", " + conversation.project, creation: ArchiveDates.date(conversation.startedAt) ?? .distantPast, ordinal: nil)
                }
                items += hits.compactMap { hit in
                    guard let conversation = byID[hit.conversationID] else { return nil }
                    let snippet = hit.snippet.replacingOccurrences(of: "\n", with: " ")
                    return ArchiveSidebarItem(id: conversation.id + "/" + String(hit.id), conversationID: conversation.id, displayTitle: conversation.title + " · " + snippet, accessibilityLabel: conversation.title + ", " + snippet, creation: ArchiveDates.date(conversation.startedAt) ?? .distantPast, ordinal: hit.ordinal)
                }
                sidebar.conversationSelectionView.apply(items, selected: selectedKey ?? selected?.id, searching: !query.isEmpty)
                sidebarEmpty.isHidden = !items.isEmpty
                sidebarEmpty.text = query.isEmpty ? "No Conversations\n\nImport your history in Settings." : "No Results\n\nTry another word, project, or date."
                if !isIndexing { displayProgress(nil) }
                if let current = selected, let fresh = byID[current.id] { selected = fresh; onConversationTitleChanged?(fresh.title) }
            } catch is CancellationError {} catch { showError(error) }
        }
    }
    public func openConversation(_ id: String) {
        loadViewIfNeeded()
        Task {
            do {
                if let conversation = try await store.conversations().first(where: { $0.id == id }) {
                    selectedKey = id; select(conversation); sidebar.conversationSelectionView.select(conversationID: id)
                }
            } catch { showError(error) }
        }
    }
    private func select(_ conversation: Conversation, target: Int? = nil) {
        pageTask?.cancel(); positionTask?.cancel(); generation = UUID(); let token = generation
        let changed = selected?.id != conversation.id
        selected = conversation; onConversationTitleChanged?(conversation.title)
        isApplyingPage = true; rows = []; empty.isHidden = true
        previous.isEnabled = false; nextPageButton.isEnabled = false; latest.isEnabled = false
        if changed || chat == nil { installChat(for: conversation) }
        pageTask = Task {
            do {
                let saved = scope == .conversation && target == nil ? try await store.savedPosition(conversationID: conversation.id) : nil
                let start = if let target { try await store.precedingPageStart(conversationID: conversation.id, before: target, limit: 12, scope: scope) } else if let saved { saved } else { try await store.precedingPageStart(conversationID: conversation.id, before: Int.max, scope: scope) }
                guard generation == token, !Task.isCancelled else { return }
                loadPage(from: start, target: target, atEnd: target == nil && saved == nil)
            } catch is CancellationError {} catch { guard generation == token else { return }; isApplyingPage = false; showError(error) }
        }
    }
    private func installChat(for conversation: Conversation) {
        chat?.willMove(toParent: nil); chat?.view.removeFromSuperview(); chat?.removeFromParent()
        let storage = ArchiveChatStorage(); storage.replace(messages: [], title: conversation.title); chatStorage = storage
        let controller = ChatViewController(conversationID: conversation.id, sessionConfiguration: .init(storage: storage), configuration: .init(isReadOnly: true))
        controller.menuDelegate = self
        addChild(controller); chatContainer.insertSubview(controller.view, belowSubview: empty)
        controller.view.snp.makeConstraints { $0.edges.equalToSuperview() }; controller.didMove(toParent: self); chat = controller
        controller.messageListView.accessibilityIdentifier = "transcriptList"
        controller.messageListView.archiveMenuProvider = { [weak self] id in self?.messageMenu(id) }
        controller.messageListView.onVisibleArchiveMessage = { [weak self] id in self?.savePosition(id) }
    }
    private func loadPage(from ordinal: Int, target: Int? = nil, atEnd: Bool = false) {
        guard let conversation = selected else { return }
        pageTask?.cancel(); positionTask?.cancel(); generation = UUID(); let token = generation; isApplyingPage = true
        pageTask = Task {
            do {
                var items = try await store.items(conversationID: conversation.id, from: ordinal, scope: scope)
                if items.isEmpty && ordinal > 0 { items = try await store.items(conversationID: conversation.id, scope: scope) }
                let earliest = try await store.items(conversationID: conversation.id, limit: 1, scope: scope).first?.ordinal
                let following = try await store.items(conversationID: conversation.id, from: (items.last?.ordinal ?? -1) + 1, limit: 1, scope: scope)
                let pageRows = ArchiveReaderPage.rows(items)
                let messages = await ArchiveChatProjection.messages(rows: pageRows, conversationID: conversation.id, root: store.root, targetOrdinal: target)
                guard generation == token, !Task.isCancelled else { return }
                rows = pageRows; hasEarlier = earliest.map { $0 < (items.first?.ordinal ?? 0) } ?? false; hasLater = !following.isEmpty
                chatStorage?.replace(messages: messages, title: conversation.title)
                let targetRow = target.flatMap { ordinal in rows.first(where: { $0.entry.contains(ordinal: ordinal) }) }
                chat?.messageListView.highlightedArchiveMessageID = target == nil ? nil : targetRow?.id
                chat?.reloadArchive()
                empty.text = scope == .conversation ? "No Conversation Messages\n\nOpen Conversation Info to browse supporting records." : "No Archived Records"
                empty.isHidden = !items.isEmpty
                previous.isEnabled = hasEarlier; nextPageButton.isEnabled = hasLater; latest.isEnabled = !items.isEmpty
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == token else { return }
                    chat?.messageListView.scrollToArchiveMessage(targetRow?.id ?? rows.first?.id, atEnd: atEnd)
                    isApplyingPage = false
                }
            } catch is CancellationError {} catch { guard generation == token else { return }; isApplyingPage = false; showError(error) }
        }
    }
    private func earlier() {
        guard let conversation = selected, let first = rows.first else { return }; let token = generation
        Task { do { let start = try await store.precedingPageStart(conversationID: conversation.id, before: first.ordinal, scope: scope); guard generation == token else { return }; loadPage(from: start, atEnd: true) } catch { showError(error) } }
    }
    private func later() { if let last = rows.last?.entry.items.last { loadPage(from: last.ordinal + 1) } }
    private func latestPage() {
        guard let conversation = selected else { return }; let token = generation
        Task { do { let start = try await store.precedingPageStart(conversationID: conversation.id, before: Int.max, scope: scope); guard generation == token else { return }; loadPage(from: start, atEnd: true) } catch { showError(error) } }
    }
    private func savePosition(_ id: String) {
        guard scope == .conversation, !isApplyingPage, let conversation = selected, let row = rows.first(where: { $0.id == id }) else { return }
        positionTask?.cancel(); let ordinal = row.ordinal
        positionTask = Task { do { try await Task.sleep(for: .milliseconds(250)); try await store.savePosition(conversationID: conversation.id, ordinal: ordinal) } catch {} }
    }
    private func messageMenu(_ id: String) -> UIMenu? {
        guard let row = rows.first(where: { $0.id == id }) else { return nil }
        return UIMenu(children: [
            UIAction(title: "Copy Displayed Text", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = row.preview },
            UIAction(title: row.isTruncated ? "Read Full Text…" : "Message Details…", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.openDetail(row) }
        ])
    }
    private func openDetail(_ row: ArchiveReaderRow) {
        guard presentedViewController == nil else { return }
        let controller = ArchiveItemController(items: row.entry.items, store: store)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet; navigation.preferredContentSize = CGSize(width: 800, height: 700)
        present(navigation, animated: true)
    }
    public func chatViewControllerMenu(_ controller: ChatViewController) -> UIMenu? {
        guard let selected else { return nil }
        var actions: [UIMenuElement] = [UIAction(title: "Conversation Info…", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.showInfo(selected) }]
        if scope == .conversation { actions.append(UIAction(title: "Browse All Records…", image: UIImage(systemName: "doc.text.magnifyingglass")) { [weak self] _ in self?.onOpenRecords?(selected.id) }) }
        return UIMenu(children: actions)
    }
    private func showInfo(_ conversation: Conversation) {
        let alert = UIAlertController(title: conversation.title, message: "Project: \(conversation.project)\nStarted: \(ArchiveDates.full(conversation.startedAt))\n\(conversation.itemCount) conversation items\n\(conversation.warningCount) archive notices", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .cancel)); present(alert, animated: true)
    }
    private func archiveChanged() { reloadSidebar(); if let selected { select(selected) } }
    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Archive Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        (presentedViewController ?? self).present(alert, animated: true)
    }
}

extension Notification.Name { static let archiveDidChange = Notification.Name("HistodexArchiveDidChange") }
