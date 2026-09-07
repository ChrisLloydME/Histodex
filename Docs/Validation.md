# Validation and limits

## Verified on 2026-09-06

- Xcode 26.6 / Swift 6.3.3, macOS arm64: native app builds successfully.
- Ad-hoc development signature includes App Sandbox, user-selected read-only access, app-scoped bookmarks, and debug task access. No network entitlement.
- 19 core regression tests pass, including an opt-in test against three privately copied real sessions (706,571 source bytes). Without that local fixture path, 18 tests run and the real-fixture test is skipped.
- Real sessions import and reparse successfully. A prior schema-shape survey sampled 16 of 894 local rollouts without retaining private content in git.
- Runtime smoke test of the development app imported a synthetic archive with 137 visible records and one explicit missing-asset notice, without runtime log errors. This exposed and fixed a missing delegate initialization in the storyboard-free entry point.
- Tests cover source deletion followed by offline search/reparse, plain/compressed files, corrupted compressed updates, malformed/unknown/truncated JSONL, oversized-line byte provenance, duplicated images, generated images, missing paths, native Markdown link handling, source symlink replacement, inherited prefixes/cycles, large output text paging, 2,200-item transcript paging, cancellation rollback, changed source versions, and event/response mirror preservation.
- Visual interaction QA remains outstanding: Computer Use access to Histodex was not approved. No visual or accessibility pass is claimed. The native UI smoke test used synthetic data and an unsigned development launch before the final sandboxed signing check.

## Deliberate bounds

- JSON decoding: at most 32 MiB per record. Larger lines are streamed past and represented by a diagnostic with their complete raw byte range. No raw bytes are discarded.
- SQLite transcript pages: up to 200 items per API request (UI uses 100), at most 12,000 text characters per item preview. Inspect reads text in 64,000-character pages. The full normalized text remains indexed.
- External assets: 256 MiB per file. Image thumbnails decode to bounded pixel sizes for visible rows only. Remote URLs are retained as unavailable assets, never fetched automatically.
- Zstandard decoder window: 128 MiB. Incomplete/corrupt frames preserve the compressed raw copy and report a failed import; the last complete conversation remains available.
- Inherited history: maximum 32 levels, with cycle/missing-parent notices. Explicit byte bounds must end on a JSONL record boundary. Physical rollout identities come from source filenames; source aliases survive reparsing.
- Search returns the first 100 ranked hits (API supports up to 500). Sidebar metadata queries support up to 10,000 conversations. These are explicit UI/API bounds, not archive retention limits.

## Remaining compatibility and release considerations

- Codex's private format evolves. Unknown records stay archived; a dedicated presentation is not promised for every future event. Encrypted reasoning cannot be rendered as plaintext.
- Snapshotting captures a fixed size from an opened read-only file. It does not lock Codex and cannot guarantee atomicity against arbitrary in-place rewrites during copying. Normal append growth is bounded by the initial size.
- Assets outside the selected folder may be inaccessible under App Sandbox. Histodex shows missing-asset reasons instead of broadening permissions silently. Reparse uses previously archived assets, even if external files later change.
- Mirrors are paired conservatively across nearby opposite source representations, with turn checks; raw records and asset links remain preserved. Unusual older producer layouts may still show duplicate transcript entries.
- Compaction replacement context is retained in raw snapshots and distinguished from the chronological transcript; it is not replayed as a second conversation. Subagent visibility/projection semantics beyond inherited prefixes are not exhaustively modeled.
- Full raw snapshots remain uncompressed when imported plain; compressed inputs also retain a decoded copy for seekable byte provenance. Plan disk capacity for independent copies and historical revisions.
- Reading restoration returns to an item, not a pixel within a long item. Native Markdown supports text, code, headings, lists, quotes, links and basic tab-separated table presentation. There is no syntax-highlighting dependency or browser renderer.
- File-asset thumbnails are generated on demand; the reserved thumbnail directory is not yet a persistent cache. Generic binary/audio assets are preserved where recognized, but the initial inspector only previews images.
- The development signature is not a distribution signature. Complete visual testing, Developer ID signing and notarization before public distribution.


## Conversation redesign validation (2026-09-06)

The follow-up redesign was validated without launching Histodex or using Computer Use, per the user's instruction. Compile-only Xcode validation succeeds. The package suite discovers 27 tests: 26 pass and the optional private real-fixture test is skipped when its environment variable is absent. Eight new presentation tests cover grouping, role hierarchy, readable structured data, collapsed payloads, shared geometry bounds, truncation/highlighting, Markdown table/list structure and outgoing link contrast. The earlier runtime smoke check above applies to the original interface only.

The redesigned browser uses a Messages-style sidebar, native split-view/toolbar integration, aligned message bubbles and collapsed technical records. Import and maintenance controls are now in Settings. See ConversationDesign.md for implementation and validation details. No visual or runtime-interaction verification is claimed for this redesign.


## Record semantics and title validation (2026-09-07)

The 34-test headless package suite passes, including the three project-local real-session fixtures. Seven new regressions verify context classification, mixed context/request splitting, legacy environment records, typed agent coordination, conversation counts/previews, scoped search and paging, exact search targets, name-index updates without changed rollouts, offline name persistence, rename timestamp precedence, inherited/foreign title isolation, and an actual v2-to-v3 schema migration followed by idempotent offline repair. Quoted/incomplete envelope examples remain unchanged. The real-fixture test now also checks title and conversation-message context boundaries.

The compile-only, signed Xcode app build passes. No application launch, Computer Use, screenshot, visual inspection or app-hosted UI test was performed for this revision. Existing installed archives were not accessed or modified during development; automatic repair runs when the user next opens the updated app. Sources remain read-only, and fixture/build writes stay under the project's ignored `.tmp/` directory.
