# Histodex

A native, offline macOS archive for Codex history. Select a Codex data folder to copy sessions into Histodex's sandbox, then browse and search the independent archive. Source files are read-only.

See [the architecture note](Docs/Architecture.md) for format research, dependencies, data boundaries and implementation decisions.

Development artifacts belong in `.tmp/` (ignored by git). The reusable engine lives in `Packages/HistodexCore`; the AppKit application lives in `Histodex`.
