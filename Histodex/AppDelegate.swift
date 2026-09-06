import AppKit
import HistodexCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }

    private var windowController: NSWindowController?
    private var browser: ArchiveBrowserController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        do {
            let root: URL
            #if DEBUG
            if let path = ProcessInfo.processInfo.environment["HISTODEX_ARCHIVE_PATH"] { root = URL(fileURLWithPath: path) }
            else { root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Histodex") }
            #else
            root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Histodex")
            #endif
            let store = try ArchiveStore(root: root)
            let content = ArchiveBrowserController(store: store); browser = content
            let window = NSWindow(contentViewController: content)
            window.title = "Histodex"; window.setContentSize(NSSize(width: 1180, height: 820)); window.minSize = NSSize(width: 850, height: 550)
            window.center(); window.setFrameAutosaveName("ArchiveWindow")
            let controller = NSWindowController(window: window); windowController = controller
            controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
            #if DEBUG
            if let source = ProcessInfo.processInfo.environment["HISTODEX_IMPORT_PATH"] { content.importSource(URL(fileURLWithPath: source)) }
            #endif
        } catch { NSAlert(error: error).runModal(); NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    @objc private func importFolder() { browser?.chooseSource(nil) }
    @objc private func focusSearch() { browser?.focusSearch() }
    @objc private func reparse() { browser?.reparse(nil) }
    @objc private func showNotices() {
        let alert = NSAlert(); alert.messageText = "Histodex"
        alert.informativeText = "An independent, offline Codex history archive.\n\nBuilt with GRDB (MIT), swift-markdown and cmark (Apache-2.0 / BSD), and Zstandard (BSD-3-Clause). Full license notices are bundled with the application."
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    private func buildMenu() {
        let bar = NSMenu()
        let application = NSMenu(); let app = NSMenuItem(); app.submenu = application; bar.addItem(app)
        application.addItem(withTitle: "About Histodex", action: #selector(showNotices), keyEquivalent: "").target = self
        application.addItem(.separator())
        application.addItem(withTitle: "Quit Histodex", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileMenu = NSMenu(title: "File"); let file = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); file.submenu = fileMenu; bar.addItem(file)
        fileMenu.addItem(withTitle: "Import Codex Folder…", action: #selector(importFolder), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: "Reparse Archived Snapshots", action: #selector(reparse), keyEquivalent: "").target = self
        let editMenu = NSMenu(title: "Edit"); let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); edit.submenu = editMenu; bar.addItem(edit)
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Search Archive", action: #selector(focusSearch), keyEquivalent: "f").target = self
        NSApp.mainMenu = bar
    }
}
