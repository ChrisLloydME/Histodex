# FlowDown interface reference

Histodex's main window now follows the macOS layout of [FlowDown](https://github.com/Lakr233/FlowDown), inspected at commit [`1762159fee5821298fdbc1e47d9a07da64d7ab33`](https://github.com/Lakr233/FlowDown/tree/1762159fee5821298fdbc1e47d9a07da64d7ab33). The reference checkout was used only to read source. FlowDown was neither built nor launched, and its installed app, preferences and data were not accessed.

Source references under `FlowDown/Interface/`:

- `MainController/MainController+Layout.swift`: inset reading panel, rounded corners and persistent resizable navigation on macOS.
- `Sidebar/Sidebar.swift`: brand and primary action at the top; settings, status and search at the bottom.
- `ConversationSelectionView/ConversationSelectionView.swift`, `ConversationSelectionView+Cell.swift` and `SectionDateHeaderView.swift`: creation-date sections, compact document-icon rows and a subtle rounded accent selection.
- `ChatView/ChatView.swift`: centered conversation title, document icon, trailing conversation action and separated reading surface.
- `MessageListView/Components/UserMessageView.swift` and `AiMessageView.swift`: trailing lightly tinted user content and unboxed assistant Markdown.

Histodex implements these conventions independently in AppKit, using its existing archive models and native Markdown renderer. FlowDown uses UIKit/Catalyst, so its app UI types cannot be linked directly into this AppKit app. No FlowDown source, dependencies, brand assets, icon or artwork are bundled. Its source repository is AGPL-3.0; its brand assets are proprietary, as described in its README. This document records the design reference, rather than claiming FlowDown as a bundled dependency.

The archive-specific primary action opens import settings. The reader has no composer; its footer identifies the read-only archive and offers navigation to the latest messages. Search results preserve exact archived-item targets. Supporting records remain available through Conversation Info.
