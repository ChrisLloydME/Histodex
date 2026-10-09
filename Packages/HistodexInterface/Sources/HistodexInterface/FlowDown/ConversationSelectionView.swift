// Derived from FlowDown/Interface/ConversationSelectionView/ConversationSelectionView.swift.
// Copyright FlowDown contributors. AGPL-3.0; see FlowDown-LICENSE.
// Histodex changes: archive rows and selection callbacks replace ConversationManager/ChatSelection.
import UIKit
import LanguageModelChatUI
import SnapKit

struct ArchiveSidebarItem {
    let id: String
    let conversationID: String
    let displayTitle: String
    let accessibilityLabel: String
    let creation: Date
    let ordinal: Int?
    var isSearchHit: Bool { ordinal != nil }
}

private class GroundedTableView: UITableView {
    @objc var allowsHeaderViewsToFloat: Bool { false }
    @objc var allowsFooterViewsToFloat: Bool { false }
}

class ConversationSelectionView: UIView, UITableViewDelegate {
    let tableView: UITableView
    private var items: [String: ArchiveSidebarItem] = [:]
    var onSelect: ((ArchiveSidebarItem) -> Void)?
    var menuProvider: ((String) -> UIMenu?)?

    init() {
        tableView = GroundedTableView(frame: .zero, style: .plain)
        tableView.register(Cell.self, forCellReuseIdentifier: "Cell")
        super.init(frame: .zero)
        dataSource.defaultRowAnimation = .fade
        addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.separatorInset = .zero
        tableView.separatorColor = .clear
        tableView.contentInset = .zero
        tableView.allowsMultipleSelection = false
        tableView.selectionFollowsFocus = true
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.accessibilityIdentifier = "conversationList"
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private lazy var dataSource: UITableViewDiffableDataSource<Date, String> = .init(tableView: tableView) { [weak self] tableView, indexPath, id in
        guard let self, let item = items[id] else { return nil }
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! Cell
        cell.use(item)
        cell.onSelect = { [weak self] id in
            guard let self, let item = items[id] else { return }
            if let path = dataSource.indexPath(for: id) { tableView.selectRow(at: path, animated: false, scrollPosition: .none) }
            onSelect?(item)
        }
        cell.menuProvider = menuProvider
        return cell
    }
    func apply(_ rows: [ArchiveSidebarItem], selected: String?, searching: Bool) {
        let oldOffset = tableView.contentOffset
        items = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var snapshot = NSDiffableDataSourceSnapshot<Date, String>()
        let groups = Dictionary(grouping: rows) { searching ? Date.distantPast : Calendar.current.startOfDay(for: $0.creation) }
        for day in groups.keys.sorted(by: >) {
            snapshot.appendSections([day])
            snapshot.appendItems((groups[day] ?? []).map(\.id), toSection: day)
        }
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { dataSource.snapshot().indexOfItem($0) != nil })
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            tableView.setContentOffset(oldOffset, animated: false)
            if let selected, let path = dataSource.indexPath(for: selected) {
                tableView.selectRow(at: path, animated: false, scrollPosition: .none)
            } else if let path = tableView.indexPathForSelectedRow { tableView.deselectRow(at: path, animated: false) }
        }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath), let item = items[id] else { return }
        onSelect?(item)
    }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sections = dataSource.snapshot().sectionIdentifiers
        guard sections.indices.contains(section) else { return nil }
        let day = sections[section]
        if day == .distantPast { return nil }
        return SectionDateHeaderView().with { $0.updateTitle(date: day) }
    }
    func select(conversationID: String) {
        guard let id = dataSource.snapshot().itemIdentifiers.first(where: { items[$0]?.conversationID == conversationID }), let path = dataSource.indexPath(for: id) else { return }
        tableView.selectRow(at: path, animated: false, scrollPosition: .none)
    }
}
