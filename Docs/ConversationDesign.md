# Conversation interface

The main window runs reused [FlowDown](https://github.com/Lakr233/FlowDown) UIKit components on Mac Catalyst. The authors' extracted LanguageModelChatUI supplies the actual chat controller and message renderer. [FlowDown Reference](FlowDownReference.md) lists vendored source revisions, file mappings, licenses and local adaptations.

## Window and navigation

- FlowDown's persistent resizable sidebar, drag handle, conversation cells, date headers and settings/search controls are retained. Archive callbacks replace its application managers. Search opens through the sidebar button or ⌘F; normal browsing groups by creation date and search shows exact-item results.
- FlowDown's Catalyst layout composes the sidebar and inset reading surface. The actual ChatViewController renders the title/menu header, user messages, assistant Markdown, date separators, attachments and supporting-record disclosures. The message input is hidden and inactive; no model is configured.
- New conversations open at the latest page. Saved positions restore to their item. Earlier/Later/Latest footer actions load bounded pages of 100 archive items. Exact search hits scroll to and highlight their containing row.
- Each message has an ellipsis menu for displayed-text copying, full-text reading or details. Original text is paged in the inspector; grouped entries expose individual source records and owned attachments through Quick Look.
- Empty states explain archive selection/import. The sidebar + action and gear open the same settings controller. Window scene titles retain the conversation name for system window lists.

## Presentation boundary

`CodexAdapter` assigns an explicit `RecordCategory` before records enter SQLite. The primary reader, its search results, preview and item counts use conversation items: actual user/assistant messages and image output. Role alone is not evidence of user authorship. Complete injected context envelopes, system/developer instructions, coordination messages, execution activity and bookkeeping are preserved in their appropriate categories.

The conversation header menu → Browse All Records opens a separate, paginated, searchable archive window for supporting records as well as messages. Its navigation does not overwrite the main reader's saved position. Confirmed event/response mirrors remain paired; all original bytes remain in snapshots.

`TranscriptEntry` only formats the records supplied by the database scope; it does not decide which source records constitute a conversation.

- In the record browser, routine consecutive session events become one collapsed activity entry. Diagnostic notices remain individually visible. Search targets inside a group expand the correct entry.
- Commands show command text, results show readable output, and remaining structured fields use labels. The original normalized text remains available in the details window's Archived Text mode.
- Reasoning, tools, injected context and technical activity use disclosures in the record browser. Their classification is stored and shared by queries, rather than inferred by the renderer.
- Messages render as selectable text, with visible full-text access when previews are truncated. The details window pages through complete text and allows selection of individual grouped records.
- Attachments stay with their entry. Missing files use a short unavailable-attachment label; the full reason and provenance remain in details.

ListViewKit provides upstream row reuse and sizing, and MarkdownView caches parsed Markdown packages. The adapter holds only one bounded page; long previews remain bounded independently of complete archived text. Supporting records use the actual upstream reasoning disclosure, with archived record titles instead of live thinking labels. This presentation does not run inference or mutate archive messages.

## Titles and upgrades

Titles follow Agent Sessions' Codex source precedence: the last saved name in `session_index.jsonl`, then the state database's `threads.title` (or `first_user_message`), then the rollout-derived title. State rows match thread identity first, with a source-scoped rollout-path fallback. Histodex copies the state database and WAL before opening SQLite, checks that the source files stayed unchanged during copying, and preserves those owned copies. SQLite recovery only operates in Histodex's staging directory.

Without a saved title, the parser prefers a meaningful short user request in the first ten records, with full-history user/assistant/tool fallbacks. Multiline requests supply their collapsed text rather than only their first line. Parent history cannot name a child conversation.

Outdated projections rebuild from owned snapshots before loading the sidebar. Update Archive acquires source titles that older imports did not preserve. Unchanged rollout files reuse owned snapshots after checking identity, size, and nanosecond modification/change timestamps. Changed files retain immutable content-addressed snapshots.

Discovery and title copying show indeterminate progress; copying and normalization report progress when measurable. Startup repair disables conflicting archive maintenance until it finishes.

## Settings and progress

⌘,, the sidebar gear and the top + action open the same Settings sheet. Settings owns folder selection, read-only bookmarks, archive updates, cancellation, errors, archive location and index rebuilding. Closing Settings does not cancel an import.

Archive operations display their phase and progress in the sidebar and Settings. Startup repair disables search and conflicting archive maintenance until it finishes. The sidebar status shows the total local conversation count. Settings also exposes bundled acknowledgements.

## Validation

For the FlowDown migration, neither Histodex nor FlowDown is launched. FlowDown is read only as a temporary source checkout and is not compiled. Validation uses compile-only Histodex builds, headless HistodexCore tests and source review. No runtime screenshots or interaction inspection are performed, so visual fidelity is not claimed to be verified.

Headless tests cover the new archive projection's role identity, bounded previews, grouped exact-item lookup and retained provenance, plus existing scoped search, import and rebuild behavior. Legacy AppKit Markdown/layout tests remain useful core regressions but do not validate the new UIKit rendering. Runtime appearance, keyboard behavior, scene restoration and interaction remain unverified under the user's no-launch constraint.
