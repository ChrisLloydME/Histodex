import AppKit
import HistodexCore

/// Source permissions and archive maintenance live outside the reading window.
final class ArchiveSettingsController: NSViewController {
    private let store: ArchiveStore
    var onArchiveChanged: (() -> Void)?
    private let source = NSTextField(labelWithString: "No folder selected")
    private let choose = NSButton(title: "Choose Folder…", target: nil, action: nil)
    private let update = NSButton(title: "Import Updates", target: nil, action: nil)
    private let rebuild = NSButton(title: "Rebuild Conversation Index", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let status = NSTextField(wrappingLabelWithString: "Choose your Codex folder to import conversations.")
    private let errors = NSTextView(usingTextLayoutManager: true)
    private let errorScroll = NSScrollView()
    private var operation: Task<Void, Never>?
    private var operationID = UUID()

    init(store: ArchiveStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 580))
        source.lineBreakMode = .byTruncatingMiddle; source.isSelectable = true
        choose.target = self; choose.action = #selector(chooseFolder)
        update.target = self; update.action = #selector(importUpdates)
        rebuild.target = self; rebuild.action = #selector(reparse)
        cancel.target = self; cancel.action = #selector(cancelImportTask); cancel.isHidden = true
        for button in [choose, update, rebuild, cancel] { button.bezelStyle = .rounded }
        let sourceButtons = NSStackView(views: [choose, update]); sourceButtons.spacing = 8
        let permissions = note("Histodex only reads the selected folder. Imported conversations and attachments are copied into an independent archive on this Mac.")
        let location = note(store.root.path); location.isSelectable = true
        let maintenance = note("Rebuild the index from archived snapshots when a parser update becomes available. Your Codex folder is not needed.")
        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1; progress.isHidden = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.maximumNumberOfLines = 3
        let progressRow = NSStackView(views: [progress, cancel]); progressRow.spacing = 10
        errors.isEditable = false; errors.isSelectable = true; errors.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        errors.textContainer?.widthTracksTextView = true; errors.autoresizingMask = [.width]; errors.isVerticallyResizable = true
        errorScroll.isHidden = true; errorScroll.hasVerticalScroller = true; errorScroll.documentView = errors; errorScroll.borderType = .bezelBorder
        let stack = NSStackView(views: [heading("Import Source"), source, sourceButtons, permissions, separator(), heading("Archive"), location, rebuild, maintenance, progressRow, status, errorScroll])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 22), stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -22), errorScroll.heightAnchor.constraint(equalToConstant: 100), progress.widthAnchor.constraint(greaterThanOrEqualToConstant: 350)])
        for child in [source, permissions, location, maintenance, status, errorScroll] { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        source.stringValue = UserDefaults.standard.string(forKey: "sourceDisplayPath") ?? "No folder selected"
        setBusy(false)
    }
    private func heading(_ title: String) -> NSTextField { let field = NSTextField(labelWithString: title); field.font = .systemFont(ofSize: 13, weight: .semibold); return field }
    private func note(_ title: String) -> NSTextField { let field = NSTextField(wrappingLabelWithString: title); field.font = .systemFont(ofSize: 12); field.textColor = .secondaryLabelColor; return field }
    private func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }

    @objc func chooseFolder() {
        guard operation == nil, let window = view.window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.title = "Choose Codex Folder"; panel.message = "Select your .codex folder. Its files will only be read."; panel.prompt = "Choose"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.importSource(url) }
        }
    }
    @objc private func importUpdates() {
        guard operation == nil, let data = UserDefaults.standard.data(forKey: "sourceBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            importSource(url)
        } catch { status.stringValue = "Select the source folder again to restore read access."; errors.string = error.localizedDescription; errorScroll.isHidden = false }
    }
    func importSource(_ url: URL) {
        _ = view
        guard operation == nil else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "sourceBookmark")
            UserDefaults.standard.set(url.path, forKey: "sourceDisplayPath"); source.stringValue = url.path
        } catch { /* One-time import remains available if saving the bookmark fails. */ }
        operationID = UUID(); let token = operationID
        setBusy(true); errors.string = ""; errorScroll.isHidden = true; status.stringValue = "Preparing import…"
        operation = Task {
            defer { if accessed { url.stopAccessingSecurityScopedResource() }; operation = nil; setBusy(false) }
            do {
                let report = try await store.importDirectory(url) { [self] value in
                    Task { @MainActor in
                        guard self.operationID == token, self.operation != nil else { return }
                        self.progress.doubleValue = Double(value.completed) / Double(max(1, value.total))
                        self.status.stringValue = value.filename
                    }
                }
                operationID = UUID(); finish(report)
            } catch is CancellationError { operationID = UUID(); status.stringValue = "Import canceled. Completed conversations remain in your archive."; onArchiveChanged?() }
            catch { operationID = UUID(); status.stringValue = "Import could not finish."; errors.string = error.localizedDescription; errorScroll.isHidden = false; onArchiveChanged?() }
        }
    }
    @objc func reparse() {
        guard operation == nil else { return }
        setBusy(true); errors.string = ""; errorScroll.isHidden = true; progress.isIndeterminate = true; progress.startAnimation(nil); status.stringValue = "Rebuilding conversation index…"
        operation = Task {
            defer { operation = nil; setBusy(false) }
            do { finish(try await store.reparseArchive()) }
            catch { status.stringValue = error is CancellationError ? "Rebuild canceled." : "Index could not be rebuilt."; errors.string = error.localizedDescription; errorScroll.isHidden = false }
        }
    }
    @objc private func cancelImportTask() { operation?.cancel() }
    private func finish(_ report: ImportReport) {
        status.stringValue = "\(report.imported) imported · \(report.unchanged) unchanged · \(report.errors.count) failed"
        errors.string = report.errors.joined(separator: "\n\n"); errorScroll.isHidden = report.errors.isEmpty; onArchiveChanged?()
    }
    private func setBusy(_ busy: Bool) {
        choose.isEnabled = !busy; update.isEnabled = !busy && UserDefaults.standard.data(forKey: "sourceBookmark") != nil; rebuild.isEnabled = !busy
        cancel.isHidden = !busy; progress.isHidden = !busy
        if !busy { progress.stopAnimation(nil); progress.isIndeterminate = false; progress.doubleValue = 0 }
    }
}
