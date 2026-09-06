# Conversation interface redesign

The macOS Messages conversation experience is the primary reference: a leading conversation list, a single reading surface, clear incoming/outgoing identity, and secondary commands outside the transcript. Apple describes that sidebar/transcript arrangement in the [Messages guide](https://support.apple.com/en-gb/guide/messages/ichte16154fb/mac). Native split-view navigation and a unified toolbar follow Apple's [sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars) and [AppKit design guidance](https://developer.apple.com/videos/play/wwdc2025/310/).

This is an archive reader. It uses those navigation, hierarchy and spacing conventions without adding a message composer, delivery states or fictional contacts.

## Window and navigation

- `NSSplitViewController` with a native sidebar item, system sidebar material and source-list selection. A tracking toolbar separator follows the divider. The system sidebar toggle supports collapsing navigation.
- Conversation rows show title, a compact date, project, and a bounded message preview. One search field finds both conversation metadata and archived text; content results retain exact-item targets.
- The unified toolbar contains the conversation title, project and Info command. Record counts, source paths and import notices belong in Info/details rather than a permanent transcript header.
- New conversations open at their latest page. Existing reading positions restore to the saved item. Earlier/later controls appear at the edges of the transcript, with database requests still bounded to 100 source records.
- Time separators appear at meaningful gaps. User messages align right in blue; assistant messages align left with readable native Markdown. Width limits keep text lines comfortable in wide windows.

## Presentation boundary

`TranscriptEntry` projects normalized archive items into display entries. It does not change imported text, search indexing, source provenance or assets.

- Routine consecutive session events become one collapsed activity entry. Diagnostic notices remain individually visible. Search targets inside a group expand the correct entry.
- Commands show command text, results show readable output, and remaining structured fields use labels. The original normalized text remains available in the details window's Archived Text mode.
- Reasoning, tools, system/developer instructions and technical activity use disclosures instead of appearing as ordinary assistant replies.
- Messages render as selectable text, with visible full-text access when previews are truncated. The details window pages through complete text and allows selection of individual grouped records.
- Attachments stay with their entry. Missing files use a short unavailable-attachment label; the full reason and provenance remain in details.

`TranscriptLayout` prepares attributed text and geometry once per entry/width/expansion state. Both table row sizing and cell rendering use that same result. Width changes invalidate cached layouts only when the width changes, preventing repeated Markdown parsing on every layout pass. Large expanded text uses a bounded scrollable viewport, and image decoding remains lazy.

## Settings

Histodex → Settings (⌘,) owns folder selection, read-only bookmarks, update imports, progress, cancellation, errors, archive location and index rebuilding. Closing Settings does not cancel an in-progress import. The reading window has no import controls or progress footer.

## Validation for this revision

The application was not launched. No Computer Use, screenshots, accessibility automation or visual inspection was performed, as requested. Validation consists of source review against native conventions, compile-only Xcode builds, and headless package tests. Eight focused presentation tests cover grouping/provenance, message roles, structured output, collapsed payloads, sizing bounds, search highlighting, Markdown paragraph structure and outgoing links. Runtime appearance and interaction fidelity are not claimed to be visually verified.
