# Histodex

A native, offline macOS archive for Codex conversation history. **Codex is an import format. Histodex is the archive.**

## Use

Open `Histodex.xcodeproj` in Xcode 16 or newer with Swift 6 support, select the Histodex scheme, and run on macOS 14 or newer. Dependencies are pinned; the first build needs internet access. The application does not.

1. Click **Import Folder…** and select your `.codex` data directory. The picker shows hidden folders.
2. Histodex snapshots rollouts from `sessions/` and `archived_sessions/`, then parses its own copies. Source files are never modified.
3. Browse by title, project or date under **Sessions**. Switch to **Contents** for full-text search; selecting a result opens its exact record.
4. Read 100 records at a time with Previous/Next navigation. Text is selectable. Expand cards for longer previews, or use **Inspect…** for complete text pages, images and raw provenance.
5. Use **Import Updates** to revisit the saved read-only folder grant. **File → Reparse Archived Snapshots** rebuilds the current projections from owned raw data without needing Codex.

Imported data lives in the application's sandbox Application Support directory, under `Histodex/`: SQLite, `raw/`, content-addressed `assets/sha256/`, and working directories. Keep that entire directory when backing up the archive; the database alone does not contain raw data or image bytes.

## Implemented

- Independent, deterministic prefix snapshots; safely repeatable transactional imports and cancellation.
- Plain JSONL and streamed Zstandard decoding, with raw compressed and decoded representations retained.
- Tolerant Codex adapter for messages, readable reasoning, commands, tools/results, patches, image generation and system events. Unknown/malformed records retain source provenance and raw bytes.
- Inherited rollout prefixes with byte/ordinal bounds, cycle detection and visible incomplete-history notices.
- SQLite/GRDB migrations, FTS5 search, bounded database pages and exact-item navigation.
- SHA-256 asset deduplication; inline images, structured local images, Markdown images, generated images, and recognized audio references. Unavailable assets remain explicit.
- Native AppKit transcript, swift-markdown attributed text, on-demand ImageIO thumbnails, disclosure controls and reading-position restoration.
- App Sandbox, read-only user-selected file access and read-only security-scoped bookmarks. No telemetry or network requirement.

## Build and validate

```sh
zsh Scripts/core.sh test
zsh Scripts/build-app.sh
```

Scripts put caches, temporary files, test fixtures and build products in the ignored `.tmp/` directory. The application script makes an ad-hoc signed development build at `.tmp/build/app/Build/Products/Debug/Histodex.app`. For distribution, use an appropriate Developer ID signing configuration and notarization in Xcode; the development build is not notarized.

An optional real-fixture regression test reads an already copied, project-local Codex source folder:

```sh
HISTODEX_REAL_FIXTURES="$PWD/.tmp/real-source" zsh Scripts/core.sh test
```

Never commit private rollout fixtures. The test suite generates synthetic fixtures under `.tmp/tests/` and removes its own per-test artifacts.

See [Architecture](Docs/Architecture.md) for source research and dependency decisions, and [Validation](Docs/Validation.md) for verified behavior and current limits. Full dependency licenses are bundled under `Histodex/Notices/`.
