import Foundation
import GRDB

/// Reads only owned copies of Codex's SQLite database and WAL. SQLite never opens
/// the source database, so recovery cannot create or alter source sidecars.
struct CodexStateTitles {
    struct Name { let id: String; let path: String; let title: String; let rawPath: String }
    static func read(source: CodexSource, archiveRoot: URL) throws -> [Name] {
        let files = try FileManager.default.contentsOfDirectory(at: source.root, includingPropertiesForKeys: nil)
        let candidates = files.filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
        func version(_ url: URL) -> Int { Int(url.deletingPathExtension().lastPathComponent.dropFirst(6)) ?? 0 }
        guard let file = candidates.max(by: { version($0) < version($1) }) else { return [] }
        let store = try SnapshotStore(root: archiveRoot)
        for _ in 0..<3 {
            try Task.checkCancellation()
            let base = SourceFile(url: file, relativePath: file.lastPathComponent)
            let walURL = URL(fileURLWithPath: file.path + "-wal")
            let wal = SourceFile(url: walURL, relativePath: walURL.lastPathComponent)
            let before = try source.fingerprint(base)
            let walBefore = FileManager.default.fileExists(atPath: walURL.path) ? try source.fingerprint(wal) : nil
            let baseCopy = try store.snapshot(source: source, file: base)
            let walCopy = walBefore != nil ? try store.snapshot(source: source, file: wal) : nil
            let after = try source.fingerprint(base)
            let walAfter = FileManager.default.fileExists(atPath: walURL.path) ? try source.fingerprint(wal) : nil
            guard before == after, walBefore == walAfter else { continue }
            let staging = archiveRoot.appendingPathComponent("staging/state-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            let owned = staging.appendingPathComponent("state.sqlite")
            try FileManager.default.copyItem(at: archiveRoot.appendingPathComponent(baseCopy.rawPath), to: owned)
            if let walCopy {
                try FileManager.default.copyItem(at: archiveRoot.appendingPathComponent(walCopy.rawPath), to: URL(fileURLWithPath: owned.path + "-wal"))
            }
            let database = try DatabaseQueue(path: owned.path)
            defer { try? database.close() }
            return try database.read { db in
                let columns = Set(try db.columns(in: "threads").map(\.name))
                guard columns.contains("id") else { return [] }
                let title = columns.contains("title") ? "title" : "NULL"
                let first = columns.contains("first_user_message") ? "substr(first_user_message,1,512)" : "NULL"
                let path = columns.contains("rollout_path") ? "rollout_path" : "''"
                return try Row.fetchAll(db, sql: "SELECT id,\(path) AS path,\(title) AS title,\(first) AS firstMessage FROM threads").compactMap { row in
                    let name = [row["title"] as String?, row["firstMessage"] as String?].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
                    guard let name else { return nil }
                    let sourcePath: String = row["path"] ?? ""
                    let relative = sourcePath.hasPrefix(source.root.path + "/") ? String(sourcePath.dropFirst(source.root.path.count + 1)) : sourcePath
                    return Name(id: row["id"], path: relative, title: name, rawPath: baseCopy.rawPath + (walCopy.map { "\n" + $0.rawPath } ?? ""))
                }
            }
        }
        throw ArchiveError.invalidSource("Codex's title database changed during copying. Retry Update Archive to refresh its titles.")
    }
}
