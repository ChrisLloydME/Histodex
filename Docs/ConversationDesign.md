# Conversation interface

The main window follows [FlowDown's macOS interface](https://github.com/Lakr233/FlowDown), implemented independently in AppKit. [FlowDown Reference](FlowDownReference.md) records the inspected commit and source components. Histodex retains its offline archive model, import pipeline, search and native Markdown rendering.

## Window and navigation

- A persistent, resizable sidebar has Histodex branding and an import-settings action at the top. Settings, archive count and search shortcuts sit at the bottom. Search remains visible above the list and supports ⌘F.
- Conversation rows use document symbols and subtle rounded accent selection. Creation-date headings group normal browsing; each row keeps a project/date subtitle. Search switches to one result section with snippets and exact-item targets. Date headings cannot be selected, and list refreshes preserve selection by conversation/item identity.
- The reading surface is inset by 10 points, with 10-point corners and a thin system separator. Its 64-point header has a document symbol, a centered truncating title, project context and Conversation Info. Title and project fields stay inside the detail pane. Native window titles retain the selected conversation for system window lists.
- New conversations open at their latest page. Existing reading positions restore to the saved item. Earlier/later controls appear at transcript edges, with database requests bounded to 100 items. The read-only footer also offers Latest Messages (Latest Records in the record browser).
- Time separators appear at meaningful gaps. Both roles share one centered column, capped at 800 points. User messages align to its trailing edge with a light accent background, native text colors and 12-point corners. Assistant Markdown flows directly on the reading surface. Message details, attachments and full-text actions stay accessible.
- The empty reader explains how to select or import history and includes an Archive Settings button. An empty selected conversation points to Conversation Info for supporting records.

## Presentation boundary

`CodexAdapter` assigns an explicit `RecordCategory` before records enter SQLite. The primary reader, its search results, preview and item counts use conversation items: actual user/assistant messages and image output. Role alone is not evidence of user authorship. Complete injected context envelopes, system/developer instructions, coordination messages, execution activity and bookkeeping are preserved in their appropriate categories.

Conversation Info → Browse All Records opens a separate, paginated, searchable archive window for supporting records as well as messages. Its navigation does not overwrite the main reader's saved position. Confirmed event/response mirrors remain paired; all original bytes remain in snapshots.

`TranscriptEntry` only formats the records supplied by the database scope; it does not decide which source records constitute a conversation.

- In the record browser, routine consecutive session events become one collapsed activity entry. Diagnostic notices remain individually visible. Search targets inside a group expand the correct entry.
- Commands show command text, results show readable output, and remaining structured fields use labels. The original normalized text remains available in the details window's Archived Text mode.
- Reasoning, tools, injected context and technical activity use disclosures in the record browser. Their classification is stored and shared by queries, rather than inferred by the renderer.
- Messages render as selectable text, with visible full-text access when previews are truncated. The details window pages through complete text and allows selection of individual grouped records.
- Attachments stay with their entry. Missing files use a short unavailable-attachment label; the full reason and provenance remain in details.

`TranscriptLayout` prepares attributed text and geometry once per entry/width/expansion state. Both table row sizing and cell rendering use that same result. Width changes invalidate cached layouts only when the width changes, preventing repeated Markdown parsing on every layout pass. Large expanded text uses a bounded scrollable viewport, and image decoding remains lazy.

## Titles and upgrades

Titles follow Agent Sessions' Codex source precedence: the last saved name in `session_index.jsonl`, then the state database's `threads.title` (or `first_user_message`), then the rollout-derived title. State rows match thread identity first, with a source-scoped rollout-path fallback. Histodex copies the state database and WAL before opening SQLite, checks that the source files stayed unchanged during copying, and preserves those owned copies. SQLite recovery only operates in Histodex's staging directory.

Without a saved title, the parser prefers a meaningful short user request in the first ten records, with full-history user/assistant/tool fallbacks. Multiline requests supply their collapsed text rather than only their first line. Parent history cannot name a child conversation.

Outdated projections rebuild from owned snapshots before loading the sidebar. Update Archive acquires source titles that older imports did not preserve. Unchanged rollout files reuse owned snapshots after checking identity, size, and nanosecond modification/change timestamps. Changed files retain immutable content-addressed snapshots.

Discovery and title copying show indeterminate progress; copying and normalization report progress when measurable. Startup repair disables conflicting archive maintenance until it finishes.

## Settings and progress

Histodex → Settings (⌘,), the sidebar gear, the top import action and the initial empty-state action all open the same settings window. Settings owns folder selection, read-only bookmarks, archive updates, cancellation, errors, archive location and index rebuilding. Closing Settings does not cancel an import.

Archive operations display their phase and progress in the sidebar and Settings. Startup repair disables search and conflicting archive maintenance until it finishes. The footer shows the total local conversation count.

## Validation

For the FlowDown migration, neither Histodex nor FlowDown is launched. FlowDown is read only as a temporary source checkout and is not compiled. Validation uses compile-only Histodex builds, headless HistodexCore tests and source review. No runtime screenshots or interaction inspection are performed, so visual fidelity is not claimed to be verified.

Presentation tests cover role identity, grouped supporting records, bounded previews, cached geometry, Markdown line breaks/tables, native outgoing link colors, retained inline-code styles, and a shared centered reading column at narrow and wide widths. Existing archive tests cover scoped search, exact-item targets, provenance, import and rebuild behavior.
