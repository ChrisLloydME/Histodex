import HistodexCore
import QuickLook
import UIKit

/// Original archive bytes, bounded full-text pages and attachment inspection.
final class ArchiveItemController: UIViewController, QLPreviewControllerDataSource {
    private let items: [ArchiveItem]
    private let store: ArchiveStore
    private var recordIndex = 0
    private var item: ArchiveItem { items[recordIndex] }
    private let mode = UISegmentedControl(items: ["Readable", "Archived Text"])
    private let text = UITextView()
    private let provenance = UILabel()
    private let pageLabel = UILabel()
    private let previous = UIButton(type: .system)
    private let nextPageButton = UIButton(type: .system)
    private let records = UIButton(type: .system)
    private let assets = UIButton(type: .system)
    private var offset = 0
    private var previewURL: URL?
    init(items: [ArchiveItem], store: ArchiveStore) { self.items = items; self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        text.isEditable = false; text.isSelectable = true; text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        mode.selectedSegmentIndex = 0; mode.addAction(UIAction { [weak self] _ in self?.loadText() }, for: .valueChanged)
        previous.setTitle("Previous text page", for: .normal); previous.addAction(UIAction { [weak self] _ in guard let self else { return }; offset = max(0, offset - 64000); loadText() }, for: .touchUpInside)
        nextPageButton.setTitle("Next text page", for: .normal); nextPageButton.addAction(UIAction { [weak self] _ in guard let self else { return }; offset += 64000; loadText() }, for: .touchUpInside)
        pageLabel.font = .preferredFont(forTextStyle: .caption1)
        let pages = UIStackView(arrangedSubviews: [previous, nextPageButton, pageLabel]); pages.spacing = 12
        provenance.numberOfLines = 4; provenance.lineBreakMode = .byTruncatingMiddle; provenance.font = .preferredFont(forTextStyle: .caption2); provenance.textColor = .secondaryLabel
        records.showsMenuAsPrimaryAction = true
        records.menu = UIMenu(children: items.enumerated().map { index, record in
            UIAction(title: TranscriptEntry.project([record])[0].title + " · " + ArchiveDates.full(record.timestamp)) { [weak self] _ in
                guard let self else { return }; recordIndex = index; offset = 0; refreshRecord()
            }
        }); records.isHidden = items.count == 1
        let stack = UIStackView(arrangedSubviews: [records, mode, pages, text, assets, provenance]); stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18), text.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
        assets.showsMenuAsPrimaryAction = true; refreshRecord()
    }
    private func refreshRecord() {
        title = TranscriptEntry.project([item])[0].title; records.setTitle("Record \(recordIndex + 1) of \(items.count)", for: .normal)
        provenance.text = "\(item.category.rawValue.capitalized) · \(item.sourceType) · \(ArchiveDates.full(item.timestamp))\n\(item.rawPath) · bytes \(item.rawOffset)–\(item.rawOffset + item.rawLength)"
        assets.isHidden = item.assets.isEmpty; assets.setTitle("\(item.assets.count) attachments…", for: .normal)
        assets.menu = UIMenu(children: item.assets.map { asset in
            UIAction(title: asset.sourceReference + (asset.missingReason == nil ? "" : " (unavailable)")) { [weak self] _ in
                guard let self else { return }
                if let path = asset.relativePath {
                    previewURL = store.root.appendingPathComponent(path)
                    let controller = QLPreviewController(); controller.dataSource = self; present(controller, animated: true)
                } else {
                    let alert = UIAlertController(title: "Unavailable Attachment", message: asset.missingReason ?? "Original asset bytes are not available.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
                }
            }
        }); loadText()
    }
    private func loadText() {
        let id = item.id; let page = offset; let readable = mode.selectedSegmentIndex == 0
        Task {
            do {
                let value = try await store.textPage(itemID: id, offset: page)
                guard item.id == id, offset == page, (mode.selectedSegmentIndex == 0) == readable else { return }
                var display = item; display.text = value
                text.text = readable ? TranscriptEntry.readableText(display) : value
                text.setContentOffset(.zero, animated: false)
                pageLabel.text = "\(min(page + 1, item.textLength))–\(min(item.textLength, page + 64000)) of \(item.textLength)"
                previous.isEnabled = page > 0; nextPageButton.isEnabled = page + 64000 < item.textLength
            } catch { text.text = error.localizedDescription }
        }
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { previewURL! as NSURL }
}
