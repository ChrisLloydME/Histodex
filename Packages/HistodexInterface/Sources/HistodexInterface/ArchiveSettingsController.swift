import HistodexCore
import UIKit
import UniformTypeIdentifiers

/// Catalyst access/maintenance adapter; archive parsing and persistence stay in HistodexCore.
final class ArchiveSettingsController: UIViewController, UIDocumentPickerDelegate {
    private let store: ArchiveStore
    private var operation: Task<Void, Never>?
    private var externalBusy = false
    private var operationID = UUID()
    private let source = UILabel()
    private let status = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let errors = UITextView()
    private let choose = UIButton(type: .system)
    private let update = UIButton(type: .system)
    private let rebuild = UIButton(type: .system)
    private let cancel = UIButton(type: .system)
    var onProgress: ((ImportProgress?) -> Void)?
    init(store: ArchiveStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Archive Settings"; view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        source.numberOfLines = 2; source.lineBreakMode = .byTruncatingMiddle
        source.text = UserDefaults.standard.string(forKey: "sourceDisplayPath") ?? "No folder selected"
        status.numberOfLines = 0; status.font = .preferredFont(forTextStyle: .footnote); status.textColor = .secondaryLabel
        status.text = "Choose your Codex folder to import conversations."
        let permissions = label("Histodex reads the selected folder and copies conversations and attachments into an independent archive on this Mac. In the folder picker, use ⌘⇧G to enter ~/.codex, or ⌘⇧. to show hidden folders.")
        let location = label(store.root.path)
        let maintenance = label("Rebuild the conversation index from owned snapshots, even without your Codex folder.")
        choose.setTitle("Choose Folder…", for: .normal); choose.addAction(UIAction { [weak self] _ in self?.chooseFolder() }, for: .touchUpInside)
        update.setTitle("Update Archive", for: .normal); update.addAction(UIAction { [weak self] _ in self?.importUpdates() }, for: .touchUpInside)
        rebuild.setTitle("Rebuild Conversation Index", for: .normal); rebuild.addAction(UIAction { [weak self] _ in self?.reparse() }, for: .touchUpInside)
        cancel.setTitle("Cancel", for: .normal); cancel.addAction(UIAction { [weak self] _ in self?.operation?.cancel() }, for: .touchUpInside)
        errors.isEditable = false; errors.font = .monospacedSystemFont(ofSize: 11, weight: .regular); errors.isHidden = true
        let buttons = UIStackView(arrangedSubviews: [choose, update]); buttons.spacing = 16
        let licenses = UIButton(type: .system)
        licenses.setTitle("Acknowledgements and Licenses…", for: .normal)
        licenses.addAction(UIAction { [weak self] _ in self?.showLicenses() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [heading("Import Source"), source, buttons, permissions, heading("Archive"), location, rebuild, maintenance, progress, cancel, status, errors, licenses])
        stack.axis = .vertical; stack.spacing = 14; stack.alignment = .fill
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
            errors.heightAnchor.constraint(equalToConstant: 100)
        ])
        refreshControls()
    }
    private func label(_ text: String) -> UILabel {
        let label = UILabel(); label.text = text; label.numberOfLines = 0; label.font = .preferredFont(forTextStyle: .footnote); label.textColor = .secondaryLabel; return label
    }
    private func heading(_ text: String) -> UILabel { let label = label(text); label.font = .preferredFont(forTextStyle: .headline); label.textColor = .label; return label }
    private func chooseFolder() {
        guard operation == nil, !externalBusy else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self; picker.allowsMultipleSelection = false
        picker.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let url = urls.first { importSource(url) } }
    private func importUpdates() {
        guard let data = UserDefaults.standard.data(forKey: "sourceBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            importSource(url)
        } catch { reportError(error, status: "Select the source folder again to restore read access.") }
    }
    func importSource(_ url: URL) {
        loadViewIfNeeded(); guard operation == nil, !externalBusy else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "sourceBookmark")
            UserDefaults.standard.set(url.path, forKey: "sourceDisplayPath"); source.text = url.path
        } catch { source.text = url.path }
        errors.isHidden = true; displayProgress(.init(completed: 0, total: 0, filename: "", phase: "Preparing archive update"))
        operationID = UUID(); let token = operationID
        operation = Task {
            defer { if accessed { url.stopAccessingSecurityScopedResource() }; operationID = UUID(); operation = nil; refreshControls(); onProgress?(nil) }
            do {
                let report = try await store.importDirectory(url) { [weak self] value in Task { @MainActor in guard let self, self.operationID == token, self.operation != nil else { return }; self.displayProgress(value) } }
                finish(report)
            } catch is CancellationError { status.text = "Import canceled. Completed conversations remain in your archive."; archiveChanged() }
            catch { reportError(error, status: "Import could not finish."); archiveChanged() }
        }
        refreshControls()
    }
    private func reparse() {
        guard operation == nil, !externalBusy else { return }
        errors.isHidden = true; displayProgress(.init(completed: 0, total: 0, filename: "", phase: "Preparing conversation index"))
        operationID = UUID(); let token = operationID
        operation = Task {
            defer { operationID = UUID(); operation = nil; refreshControls(); onProgress?(nil) }
            do {
                let report = try await store.reparseArchive { [weak self] value in Task { @MainActor in guard let self, self.operationID == token, self.operation != nil else { return }; self.displayProgress(value) } }
                finish(report)
            } catch is CancellationError { status.text = "Rebuild canceled."; archiveChanged() }
            catch { reportError(error, status: "Index could not be rebuilt."); archiveChanged() }
        }
        refreshControls()
    }
    func setExternalBusy(_ busy: Bool) { externalBusy = busy; if isViewLoaded { refreshControls() } }
    private func displayProgress(_ value: ImportProgress) {
        progress.progress = Float(value.fraction ?? 0); status.text = value.description; onProgress?(value)
    }
    private func refreshControls() {
        let busy = operation != nil
        choose.isEnabled = !busy && !externalBusy; update.isEnabled = !busy && !externalBusy && UserDefaults.standard.data(forKey: "sourceBookmark") != nil; rebuild.isEnabled = !busy && !externalBusy
        cancel.isHidden = !busy; progress.isHidden = !busy
    }
    private func finish(_ report: ImportReport) {
        status.text = "\(report.imported) imported · \(report.unchanged) unchanged · \(report.errors.count) failed"
        errors.text = report.errors.joined(separator: "\n\n"); errors.isHidden = report.errors.isEmpty; archiveChanged()
    }
    private func reportError(_ error: Error, status text: String) { status.text = text; errors.text = error.localizedDescription; errors.isHidden = false }
    private func showLicenses() {
        let controller = UIViewController(); controller.title = "Acknowledgements"
        let text = UITextView(); text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let files = (Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? []).filter { $0.lastPathComponent.lowercased().contains("license") || $0.lastPathComponent.lowercased().contains("copying") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        text.text = "Histodex reuses FlowDown (AGPL-3.0) and LanguageModelChatUI (MIT).\n\n" + files.compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { url.lastPathComponent + "\n\n" + $0 } }.joined(separator: "\n\n")
        controller.view = text; navigationController?.pushViewController(controller, animated: true)
    }
    private func archiveChanged() { NotificationCenter.default.post(name: .archiveDidChange, object: nil) }
}
