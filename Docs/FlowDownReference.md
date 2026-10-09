# FlowDown code reuse

The initial AppKit imitation has been replaced by actual upstream code. Histodex now uses UIKit on Mac Catalyst so it can run FlowDown's UI components without translating them into another UI framework.

## Reused chat framework

`Packages/LanguageModelChatUI` contains the complete `Sources/` tree of [LanguageModelChatUI](https://github.com/Lakr233/LanguageModelChatUI/tree/e7bfb39f42804e1fd8b6fb22fa64ee987f5a9fa4), commit `e7bfb39f42804e1fd8b6fb22fa64ee987f5a9fa4`. This MIT-licensed library was extracted by the FlowDown authors from their application. Histodex instantiates its `ChatViewController`, `MessageListView`, user-message rows, response rows, reasoning rows and attachment views. Markdown rendering is provided by its actual MarkdownView/Litext dependencies, including code highlighting and tables. The former Histodex transcript cells and hand-written main window have been removed.

Local changes to the vendored package are limited to archive integration: a read-only controller configuration, page refresh, message menus, exact-item scrolling/highlighting, visible-item callbacks, assistant attachment display and avoiding live-inference indicators for archived records. Direct dependency versions are pinned to the upstream minimum versions, and the library links statically to avoid duplicate shared C Markdown products. `UPSTREAM.json` records the revision and changes. No model/client is configured, and the input view is hidden and inactive.

## Reused application navigation

`Packages/HistodexInterface/Sources/HistodexInterface/FlowDown` contains adapted sources from [FlowDown](https://github.com/Lakr233/FlowDown/tree/1762159fee5821298fdbc1e47d9a07da64d7ab33), commit `1762159fee5821298fdbc1e47d9a07da64d7ab33`:

- `Sidebar.swift`, `ConversationSelectionView.swift` and its `Cell`, and `SectionDateHeaderView.swift` retain the actual UIKit/SnapKit sidebar and conversation list components.
- `MainController.swift` and the Catalyst portion of `MainController+Layout.swift` retain the macOS composition and layout; mobile gestures and application startup/inference are removed.
- `SidebarDraggerView.swift` retains the upstream drag, hover, width persistence and double-click reset implementation. Histodex keeps the sidebar visible.
- `SafeInputView.swift`, `SettingButton.swift` and `SearchControllerOpenButton.swift` retain upstream view/control implementations. Archive callbacks replace FlowDown services.

`HistodexInterface/UPSTREAM.json` maps each reused file to its original source. These application components are AGPL-3.0; that license is included in the package, root `LICENSE` and app notices. The MIT library and other dependency notices are also bundled. No proprietary FlowDown name, app icon, background artwork or installed application resources are reused.

## Archive boundary

The new archive adapter supplies one bounded page through an in-memory `StorageProvider`. It retains Histodex's database, parser, owned snapshots, record provenance, scoped search, full-text pagination, exact search targets and reading-position storage. It does not write imported messages through the chat framework. Original attachments remain in the owned archive; only bounded image thumbnails enter the reused message list. Settings and original-record inspection are Catalyst adapters to HistodexCore, not replacements for the upstream chat renderer.

Only Histodex and its UI dependencies are built. Neither the FlowDown application target nor its example app is built or launched. No installed FlowDown preferences or data are accessed. Runtime visual verification is deliberately omitted at the user's request.
