# Conversation interface redesign

The macOS Messages conversation experience is the primary reference: a leading conversation list, a single reading surface, clear incoming/outgoing identity, and secondary commands outside the transcript. Apple describes that sidebar/transcript arrangement in the [Messages guide](https://support.apple.com/en-gb/guide/messages/ichte16154fb/mac). Native split-view navigation and a unified toolbar follow Apple's [sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars) and [AppKit design guidance](https://developer.apple.com/videos/play/wwdc2025/310/).

This is an archive reader. It uses those navigation, hierarchy and spacing conventions without adding a message composer, delivery states or fictional contacts.

## Window and navigation

- `NSSplitViewController` with a native sidebar item, system sidebar material and source-list selection. A tracking toolbar separator follows the divider. The system sidebar toggle supports collapsing navigation.
- Conversation rows show title, a compact date, project, and a bounded message preview. One search field finds both conversation metadata and archived text; content results retain exact-item targets.
- The standard window title and subtitle show the conversation and project. The unified toolbar contains the sidebar toggle, tracking separator and Info command; no custom title view imposes a width on the split view. Record counts, source paths and import notices belong in Info/details rather than a permanent transcript header.
- New conversations open at their latest page. Existing reading positions restore to the saved item. Earlier/later controls appear at the edges of the transcript, with database requests bounded to 100 items in the selected archive scope.
- Time separators appear at meaningful gaps. User messages align right in blue; assistant messages align left with readable native Markdown. Width limits keep text lines comfortable in wide windows.

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

Both archive updates and index rebuilds show progress in Settings and the sidebar. The native window subtitle also reports the current phase/percentage, including when the sidebar is collapsed. Discovery and title copying show indeterminate progress; copying and normalization report work counts and bytes. Startup repair disables conflicting archive maintenance until it finishes.

## Settings

Histodex → Settings (⌘,) owns folder selection, read-only bookmarks, update imports, progress, cancellation, errors, archive location and index rebuilding. Closing Settings does not cancel an in-progress import. The reading window has no import controls or progress footer.

## Validation for this revision

The application was not launched. No Computer Use, screenshots, accessibility automation or visual inspection was performed, as requested. Validation consists of source review against native conventions, compile-only Xcode builds, and headless package tests. Eight focused presentation tests cover grouping/provenance, message roles, structured output, collapsed payloads, sizing bounds, search highlighting, Markdown paragraph structure and outgoing links. Runtime appearance and interaction fidelity are not claimed to be visually verified.
