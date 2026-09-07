# Histodex architecture

Codex is an import format. Histodex is the archive.

## Evidence reviewed (2026-09-06)

Upstream reference: OpenAI Codex main, revision `ac192cd7937b0d73edc6dffe009940ae53782dd4`. Reviewed [protocol metadata](https://github.com/openai/codex/blob/ac192cd7937b0d73edc6dffe009940ae53782dd4/codex-rs/protocol/src/protocol.rs), [response/content models](https://github.com/openai/codex/blob/ac192cd7937b0d73edc6dffe009940ae53782dd4/codex-rs/protocol/src/models.rs), and [rollout compression](https://github.com/openai/codex/blob/ac192cd7937b0d73edc6dffe009940ae53782dd4/codex-rs/rollout/src/compression.rs). No upstream implementation is copied into the adapter.

A read-only survey found 894 local plain rollout files. A distributed sample of 16 files (up to 3,001 records each) included user/assistant response messages, event mirrors, reasoning, function/custom tool calls and outputs, execution results, patches, turn context, repeated session metadata, world_state, compaction/replacement history, and unknown newer events. Largest sampled line: 1,128,058 bytes. No local compressed files were found; generated compressed fixtures must cover that path. Only shape statistics are retained in development scratch; private transcript contents must not enter git.

Current source uses timestamped JSONL envelopes with `type` and `payload`, plus optional evolving metadata. Sessions live in `sessions/` and `archived_sessions/`. Upstream supports `.jsonl.zst`, prefers plain siblings, and supports `history_base` references with exclusive ordinal and byte bounds. Metadata `id` is the stable thread identity; a filename's rollout identity can differ after revert. Multiple metadata records are possible. Event and response messages can mirror one another; retain provenance and suppress only confirmed mirrors, never all repeated text.

## Dependencies and rejected alternatives

- [GRDB.swift](https://github.com/groue/GRDB.swift), MIT, pinned 7.10.0: established since 2015, native SQLite, migrations/transactions/FTS, no network/runtime service. Prefer its database queue and explicit SQL over a custom C binding.
- [swift-markdown](https://github.com/swiftlang/swift-markdown), Apache-2.0 with Swift exception, pinned 0.8.0: Swift project's cmark-gfm-backed AST; native attributed-text rendering belongs in Histodex. Small dependency graph (cmark, build-time doc tooling as declared upstream).
- [Zstandard](https://github.com/facebook/zstd), BSD-3-Clause or GPLv2 (choose BSD), pinned `d9c0c7e2cf8a8bf9fb98d3bee546dcf8dc9ac59a`: use official `libzstd` product and stable streaming C API through a narrow Swift reader. The v1.5.7 release lacks its current SPM manifest; a fixed upstream revision gives reproducibility without relying on a moving branch. Review updates deliberately.
- [SwiftZSTD](https://github.com/aperedera/SwiftZSTD) provides streaming wrappers, but its current manifest depends on a zstd semantic release whose SPM manifest is absent. The official library plus a narrow streaming bridge avoids that integration issue.
- [ainame/swift-codex](https://github.com/ainame/swift-codex) is an app-server SDK requiring an installed Codex process; it is not an offline rollout parser. [chrischabot/codex-swift](https://github.com/chrischabot/codex-swift) implements an agent harness with networking/execution/persistence; importing that surface is unsuitable. Search did not identify an established, focused, offline Swift rollout reader. Implement a small tolerant adapter, without embedding the Rust runtime.
- [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine), Apache-2.0, is an interactive editing framework. Its editor and rendering dependencies exceed a read-only paginated transcript's needs. Start with swift-markdown AST and NSTextView, not a web renderer or custom Markdown parser.
- Foundation file access, CryptoKit SHA-256 and ImageIO thumbnailing cover filesystem/hashing/images without additional packages.

All dependencies build locally and need no network at runtime. Resolved revisions and required license notices are retained.

## Owned domain and schema

`HistodexCore` owns Conversation, ArchiveItem (message, reasoning, command, commandOutput, toolCall, toolResult, fileChange, image/generatedImage, systemEvent, unknown), Asset, ImportSnapshot and source provenance. Useful stable fields are typed. Raw unknown fields survive in immutable snapshots; items refer to raw byte ranges instead of duplicating Base64 in SQLite. Archive schema and Codex adapter versions are independent.

SQLite tables: conversations (stable archive identity, title, project, dates, current snapshot, item count), snapshots (content hash, raw relative path, source identity/size/time, parser version, status), items (conversation/order/turn/role/kind/text/tool/call/source range), assets (SHA-256, MIME, size, dimensions, archive path), item_assets (ordered links and missing original references), plus FTS5 over normalized text/tool metadata. Index conversation/order and search-to-exact-item linkage. A transaction replaces a conversation's normalized projection only when successful; old raw snapshots remain available for future reparsing. Failed imports never replace the last usable projection.

## Import and compatibility

A read-only source abstraction exposes discovery and reading, never mutation. Folder selection grants security-scoped read access. Discover regular rollout files without following directory symlinks. Copy exactly the size captured from an opened source descriptor; reject unexpected truncation. Hash while copying, synchronize, and publish to a content-addressed raw path. Parse only that owned copy. An unchanged snapshot/parser pair is a no-op. Re-import changed sessions transactionally; interrupted work is safely repeatable. Preserve partial last lines and malformed lines as diagnostic unknown records; continue after bad records. Keep complete raw data even when a line exceeds a documented parser safety bound.

Stream fixed-size reads and decompression buffers; bound individual JSON record memory (initially 32 MiB) and preserve oversized records by byte provenance. Normalize one record at a time with bounded batches. No multi-file or whole-rollout JSON decode. Preserve unfamiliar envelopes as unknown items. Mirror handling must preserve raw provenance and avoid erasing legitimate repeated utterances. Inherited history needs cycle detection and exclusive prefix bounds; unavailable parents must show an explicit incomplete-history state, not silently fabricate content. Compaction replacement context must remain distinguishable from the historical transcript.

## Assets

Extract inline image data, generated-image results, known local references and structured tool-result images. SHA-256 content-addressed filesystem storage with MIME, byte size, dimensions and original reference metadata. Copy external images only through available read grants, never request network resources. Missing/unreadable paths remain visible with reasons. Deduplicate bytes across sessions. Images decode only for visible rows; ImageIO creates bounded thumbnails. Raw snapshots preserve original encoded payloads, so normalized storage does not need duplicate Base64 bodies.

## Native interface

AppKit NSWindowController/NSSplitViewController, sidebar NSTableView and reusable transcript rows. Use a bounded database page/window with ordinal navigation and exact search jumps, avoiding thousands of views and eager text/image decoding. Selectable NSTextView uses native Markdown attributed strings; code and tool output use monospace text and disclosure. Store per-conversation item/scroll position. Sidebar supports title/project/date and archive-wide search. Show import progress, failure diagnostics and empty/missing-asset states. No SwiftUI bridge is needed initially.

## Risks to validate

Huge individual JSON records, concurrent source rewrites (prefix snapshots guarantee a size boundary, not atomicity against arbitrary in-place edits), inherited/reverted history, event mirrors, inaccessible image paths outside a security grant, encrypted reasoning, evolving tool payloads, unsupported inline media, FTS size, native variable-height text layout, sandbox signing/test environment. Reparse support must use owned snapshots, including assets already imported. Do not claim full compatibility with unseen future schemas.

## Implemented refinements

Archive schema v2 adds persistent source aliases for content-deduplicated snapshots and an indexed call/result lookup. Adapter v2 links command outputs, retains assets from event/response mirrors, and keeps reparsing on owned assets. Prefix resolution uses owned snapshots with cycle and byte-boundary validation; unavailable ancestry produces visible notices. Newer conversation projections are protected from older changed rollouts. Database query previews are capped independently from stored/indexed text, and the native inspector pages through complete output. See Validation.md for tested boundaries and release limitations.


## Conversation presentation revision

The Messages-inspired AppKit interface adds an owned `TranscriptEntry` display projection and a shared `TranscriptLayout` geometry cache. Routine events are grouped for disclosure without deleting archive items; exact search targets remain resolvable inside groups. Native `NSSplitViewController` and unified-toolbar navigation replace the original header/control stacks. Source permissions and maintenance move into an independent Settings controller. The database adds only a bounded conversation-preview query and optional reading-position lookup; the archive schema and import adapter are unchanged by this presentation revision. See ConversationDesign.md.


## Record semantics and title repair (2026-09-07)

The root cause was normalization: response messages with a user role were assumed to be user requests, including injected AGENTS and environment text. The first such text also supplied the fallback title. A shape-only survey of 24 local sessions found AGENTS/environment envelopes in 20 first user-role records. The importer also omitted Codex's name index and allowed inherited history to select child titles.

Schema v3 and adapter v3 persist `RecordCategory` independently of the source item kind. Conversation, activity, context, metadata and unknown records retain provenance. A complete leading context envelope followed by actual request text produces two normalized items sharing the original raw range. Ordinary mentions, quoted examples and incomplete envelopes are not stripped. Role-specific instructions and typed inter-agent messages are supporting context. New unsupported forms remain preserved; heuristic recognition of future user-role envelopes is not guaranteed.

Scoped SQL queries provide consistent transcript/search/pagination semantics. Main conversation counts and previews exclude supporting records. The all-records API remains available for archival inspection, including unknown data. Renderer grouping is only formatting within the selected scope.

Codex's [session index implementation](https://github.com/openai/codex/blob/main/codex-rs/rollout/src/session_index.rs) defines append-only `id`, `thread_name`, `updated_at` records with last-entry precedence. Histodex snapshots this optional source using the same read-only, fixed-prefix mechanism as rollouts. Selected names retain owned raw paths and byte offsets. The normalized name table survives offline reparsing. Index updates apply even when session snapshots are unchanged; newer own-thread rename events outrank older index timestamps. Explicit names remain intact; only extractive fallback titles are shortened. Context scaffolding, foreign-thread renames and inherited segments cannot name the child. The native browser requests an idempotent outdated-parser repair before its initial queries, without opening the original source folder.

## Desktop provenance and display names (schema/adapter v6)

Current desktop response messages include `internal_chat_message_metadata_passthrough.content_item_kinds`, parallel to their content blocks. The adapter uses the `user.*` provenance namespace for authored content and retains other blocks as context. Mixed records are split before text and asset extraction. Explicitly authored text bypasses legacy envelope heuristics, so a user can discuss literal configuration markup. Older records without provenance retain the compatibility parser. This addresses injected records structurally rather than maintaining a list of plugin/configuration strings.

Session metadata `thread_source` distinguishes `user` from `subagent` and `guardian_review`; older `source.subagent` variants supply equivalent provenance, matching Agent Sessions' surface classification. The conversation projection stores visibility, and list/search queries exclude internal threads. Raw snapshots and normalized records remain available for future reparsing. An `exec` source alone does not establish that a conversation is internal.

Direct comparison with three screenshot sessions established that modern state databases store sidebar names in `threads.name`, while `threads.title` can contain the original full prompt. Snapshot import now preserves the name separately and prefers it over legacy index/title fallbacks. This extends the older state-title/index logic in the Agent Sessions reference. Run Update Archive once to capture these names from the source; thereafter they survive offline rebuilding. Startup automatically repairs outdated rollout projections.
