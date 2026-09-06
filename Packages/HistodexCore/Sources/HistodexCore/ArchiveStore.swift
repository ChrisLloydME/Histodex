import Foundation
import CryptoKit
import GRDB

public actor ArchiveStore {
    public nonisolated let root: URL
    private let database: DatabaseQueue
    public static let schemaVersion = 2

    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        _ = try SnapshotStore(root: self.root)
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA foreign_keys = ON") }
        database = try DatabaseQueue(path: self.root.appendingPathComponent("archive.sqlite").path, configuration: config)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("archive-v1") { db in
            try db.execute(sql: """
                CREATE TABLE snapshots (
                    id TEXT PRIMARY KEY, rawPath TEXT NOT NULL, parsePath TEXT NOT NULL,
                    sourcePath TEXT NOT NULL, byteSize INTEGER NOT NULL,
                    importedAt TEXT NOT NULL, parserVersion INTEGER NOT NULL,
                    status TEXT NOT NULL, error TEXT
                );
                CREATE TABLE conversations (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL, project TEXT NOT NULL,
                    startedAt TEXT NOT NULL, updatedAt TEXT NOT NULL,
                    itemCount INTEGER NOT NULL DEFAULT 0, warningCount INTEGER NOT NULL DEFAULT 0,
                    snapshotID TEXT NOT NULL REFERENCES snapshots(id)
                );
                CREATE TABLE items (
                    id INTEGER PRIMARY KEY, conversationID TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    ordinal INTEGER NOT NULL, kind TEXT NOT NULL, role TEXT NOT NULL,
                    text TEXT NOT NULL, timestamp TEXT NOT NULL, turnID TEXT NOT NULL,
                    toolName TEXT NOT NULL, callID TEXT NOT NULL, sourceType TEXT NOT NULL,
                    rawOffset INTEGER NOT NULL, rawLength INTEGER NOT NULL, rawPath TEXT NOT NULL,
                    isDiagnostic INTEGER NOT NULL, mirrorKey TEXT, mirrorFamily TEXT, hidden INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX item_order ON items(conversationID, ordinal);
                CREATE INDEX item_calls ON items(conversationID, callID);
                CREATE INDEX item_mirrors ON items(conversationID, mirrorKey, mirrorFamily, hidden);
                CREATE INDEX conversation_date ON conversations(updatedAt DESC);
                CREATE TABLE assets (
                    hash TEXT PRIMARY KEY, relativePath TEXT NOT NULL, mimeType TEXT NOT NULL,
                    byteSize INTEGER NOT NULL, width INTEGER, height INTEGER
                );
                CREATE TABLE item_assets (
                    itemID INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL, hash TEXT REFERENCES assets(hash),
                    sourceReference TEXT NOT NULL, missingReason TEXT,
                    PRIMARY KEY(itemID, position)
                );
                CREATE VIRTUAL TABLE item_search USING fts5(text, toolName, content='items', content_rowid='id', tokenize='unicode61');
                CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
                    INSERT INTO item_search(rowid,text,toolName) VALUES(new.id,new.text,new.toolName);
                END;
                CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
                    INSERT INTO item_search(item_search,rowid,text,toolName) VALUES('delete',old.id,old.text,old.toolName);
                END;
                CREATE TABLE reading_positions(conversationID TEXT PRIMARY KEY, ordinal INTEGER NOT NULL);
                """)
        }
        migrator.registerMigration("archive-v2") { db in
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS item_calls ON items(conversationID, callID);
                CREATE TABLE snapshot_sources(snapshotID TEXT NOT NULL REFERENCES snapshots(id), sourcePath TEXT NOT NULL, PRIMARY KEY(snapshotID,sourcePath));
                INSERT INTO snapshot_sources SELECT id,sourcePath FROM snapshots;
                """)
        }
        try migrator.migrate(database)
    }

    public func conversations(filter: String = "") throws -> [Conversation] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT conversations.*, coalesce((SELECT substr(text,1,180) FROM items WHERE conversationID=conversations.id AND hidden=0 AND kind='message' AND role IN ('user','assistant') ORDER BY ordinal DESC LIMIT 1),'') AS preview FROM conversations WHERE ? = '' OR instr(lower(title || ' ' || project || ' ' || startedAt), lower(?)) > 0
                ORDER BY updatedAt DESC, id LIMIT 10000
                """, arguments: [filter, filter])
            return rows.map(Self.conversation)
        }
    }

    public func items(conversationID: String, from ordinal: Int = 0, limit: Int = 100) throws -> [ArchiveItem] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id,conversationID,ordinal,kind,role,substr(text,1,12000) AS text,length(text) AS textLength,timestamp,turnID,toolName,callID,sourceType,rawOffset,rawLength,rawPath,isDiagnostic FROM items WHERE conversationID = ? AND hidden = 0 AND ordinal >= ? ORDER BY ordinal LIMIT ?",
                             arguments: [conversationID, max(0, ordinal), min(200, max(1, limit))]).map { try Self.item($0, db: db) }
        }
    }

    public func textPage(itemID: Int64, offset: Int = 0, limit: Int = 64000) throws -> String {
        try database.read { db in
            try String.fetchOne(db, sql: "SELECT substr(text,?,?) FROM items WHERE id=?", arguments: [max(0, offset) + 1, min(64000, max(1, limit)), itemID]) ?? ""
        }
    }

    public func precedingPageStart(conversationID: String, before ordinal: Int, limit: Int = 100) throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "SELECT min(ordinal) FROM (SELECT ordinal FROM items WHERE conversationID = ? AND hidden = 0 AND ordinal < ? ORDER BY ordinal DESC LIMIT ?)", arguments: [conversationID, ordinal, min(200, max(1, limit))]) ?? 0
        }
    }

    public func search(_ query: String, limit: Int = 100) throws -> [SearchHit] {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        // User input is literal FTS terms, never an executable FTS expression.
        let pattern = words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
        return try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT i.id,i.conversationID,i.ordinal,c.title,snippet(item_search,0,'','', ' … ',24) AS excerpt
                FROM item_search JOIN items i ON i.id=item_search.rowid JOIN conversations c ON c.id=i.conversationID
                WHERE item_search MATCH ? AND i.hidden=0 ORDER BY rank LIMIT ?
                """, arguments: [pattern, min(500, max(1, limit))]).map {
                    SearchHit(id: $0["id"], conversationID: $0["conversationID"], title: $0["title"], ordinal: $0["ordinal"], snippet: $0["excerpt"])
                }
        }
    }

    public func savePosition(conversationID: String, ordinal: Int) throws {
        try database.write { db in try db.execute(sql: "INSERT OR REPLACE INTO reading_positions VALUES (?,?)", arguments: [conversationID, ordinal]) }
    }
    public func savedPosition(conversationID: String) throws -> Int? {
        try database.read { db in try Int.fetchOne(db, sql: "SELECT ordinal FROM reading_positions WHERE conversationID=?", arguments: [conversationID]) }
    }
    public func position(conversationID: String) throws -> Int {
        try database.read { db in try Int.fetchOne(db, sql: "SELECT ordinal FROM reading_positions WHERE conversationID=?", arguments: [conversationID]) ?? 0 }
    }

    public func importDirectory(_ sourceURL: URL, progress: (@Sendable (ImportProgress) -> Void)? = nil) throws -> ImportReport {
        let source = try CodexSource(root: sourceURL)
        guard !root.path.hasPrefix(source.root.path + "/"), root != source.root,
              !source.root.path.hasPrefix(root.path + "/") else {
            throw ArchiveError.invalidSource("The archive and source folder must be separate, non-nested locations.")
        }
        let files = try source.discover()
        guard !files.isEmpty else { throw ArchiveError.invalidSource("No rollout files were found under sessions/ or archived_sessions/ in the selected folder.") }
        let snapshots = try SnapshotStore(root: root)
        var report = ImportReport()
        var captured: [Snapshot] = []
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            progress?(ImportProgress(completed: index, total: files.count * 2, filename: "Snapshot: " + file.url.lastPathComponent))
            do { captured.append(try snapshots.snapshot(source: source, file: file)) }
            catch is CancellationError { throw CancellationError() }
            catch { report.errors.append("\(file.relativePath): \(error.localizedDescription)") }
        }
        for snapshot in captured { try register(snapshot) }
        let known = try knownSnapshots() + captured
        for (index, snapshot) in captured.enumerated() {
            try Task.checkCancellation()
            progress?(ImportProgress(completed: files.count + index, total: files.count * 2, filename: "Import: " + snapshot.sourcePath))
            do {
                if try importSnapshot(snapshot, sourceRoot: source.root, known: known) { report.imported += 1 } else { report.unchanged += 1 }
            } catch is CancellationError { throw CancellationError() }
            catch { report.errors.append("\(snapshot.sourcePath): \(error.localizedDescription)") }
        }
        progress?(ImportProgress(completed: files.count * 2, total: files.count * 2, filename: ""))
        return report
    }

    /// Rebuild normalized data from owned raw snapshots, without requiring the original Codex folder.
    public func reparseArchive() throws -> ImportReport {
        let snapshots: [Snapshot] = try database.read { db in
            try Row.fetchAll(db, sql: "SELECT s.* FROM snapshots s JOIN conversations c ON c.snapshotID=s.id ORDER BY s.importedAt").map {
                Snapshot(id: $0["id"], rawPath: $0["rawPath"], parsePath: $0["parsePath"], byteSize: UInt64($0["byteSize"] as Int64), sourcePath: $0["sourcePath"])
            }
        }
        let known = try knownSnapshots()
        var report = ImportReport()
        for snapshot in snapshots {
            try Task.checkCancellation()
            do { _ = try importSnapshot(snapshot, sourceRoot: root, known: known, force: true); report.imported += 1 }
            catch { report.errors.append("\(snapshot.sourcePath): \(error.localizedDescription)") }
        }
        return report
    }

    private func knownSnapshots() throws -> [Snapshot] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT s.id,s.rawPath,s.parsePath,ss.sourcePath,s.byteSize FROM snapshots s JOIN snapshot_sources ss ON ss.snapshotID=s.id ORDER BY s.importedAt").map {
                Snapshot(id: $0["id"], rawPath: $0["rawPath"], parsePath: $0["parsePath"], byteSize: UInt64($0["byteSize"] as Int64), sourcePath: $0["sourcePath"])
            }
        }
    }

    private func register(_ snapshot: Snapshot) throws {
        try database.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO snapshots(id,rawPath,parsePath,sourcePath,byteSize,importedAt,parserVersion,status)
                VALUES(?,?,?,?,?,?,?,'pending')
                """, arguments: [snapshot.id, snapshot.rawPath, snapshot.parsePath, snapshot.sourcePath, Int64(snapshot.byteSize), ISO8601DateFormatter().string(from: Date()), CodexAdapter.version])
            try db.execute(sql: "INSERT OR IGNORE INTO snapshot_sources VALUES(?,?)", arguments: [snapshot.id, snapshot.sourcePath])
        }
    }

    private func importSnapshot(_ snapshot: Snapshot, sourceRoot: URL, known: [Snapshot], force: Bool = false) throws -> Bool {
        let resolver = HistoryResolver(root: root, snapshots: known)
        let metadata = try resolver.metadata(snapshot)
        if !force, metadata.parentRolloutID.isEmpty, try database.read({ db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM snapshots WHERE id=? AND parserVersion=? AND status IN ('complete','superseded'))", arguments: [snapshot.id, CodexAdapter.version]) ?? false
        }) { return false }
        let plan = try resolver.plan(for: snapshot)
        let identity = metadata.sourceID.isEmpty ? SHA256.hash(data: Data(snapshot.sourcePath.utf8)).map { String(format: "%02x", $0) }.joined() : metadata.sourceID
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO snapshots(id,rawPath,parsePath,sourcePath,byteSize,importedAt,parserVersion,status)
                VALUES(?,?,?,?,?,?,?,'pending') ON CONFLICT(id) DO UPDATE SET status='pending',error=NULL
                """, arguments: [snapshot.id, snapshot.rawPath, snapshot.parsePath, snapshot.sourcePath, Int64(snapshot.byteSize), ISO8601DateFormatter().string(from: Date()), CodexAdapter.version])
        }
        do {
            try database.write { db in
                let currentDate = try String.fetchOne(db, sql: "SELECT updatedAt FROM conversations WHERE id=?", arguments: [identity]) ?? ""
                // Retain known asset links before replacing normalized rows. Reparsing stays self-contained.
                let existingAssets = try Row.fetchAll(db, sql: """
                    SELECT ia.sourceReference,ia.missingReason,a.* FROM item_assets ia
                    JOIN items i ON i.id=ia.itemID LEFT JOIN assets a ON a.hash=ia.hash
                    WHERE i.conversationID=? AND a.hash IS NOT NULL
                    """, arguments: [identity])
                var preserved: [String: ArchivedAsset] = [:]
                for row in existingAssets { preserved[row["sourceReference"] as String] = Self.asset(row) }
                try db.execute(sql: """
                    INSERT INTO conversations(id,title,project,startedAt,updatedAt,snapshotID) VALUES(?,'Importing','','','',?)
                    ON CONFLICT(id) DO UPDATE SET snapshotID=excluded.snapshotID
                    """, arguments: [identity, snapshot.id])
                try db.execute(sql: "DELETE FROM items WHERE conversationID=?", arguments: [identity])
                var adapter = CodexAdapter(); adapter.metadata = metadata
                var count = 0; var warnings = 0
                let assetStore = AssetStore(root: root, sourceRoot: sourceRoot, preserved: preserved, archiveOnly: force)
                enum PrefixEnd: Error { case reached }
                for segment in plan.segments {
                    let segmentMetadata = try resolver.metadata(segment.snapshot)
                    if !segmentMetadata.project.isEmpty { adapter.metadata.project = segmentMetadata.project }
                    do {
                        try JSONLReader().read(root.appendingPathComponent(segment.snapshot.parsePath)) { line in
                            if let end = segment.endByte, line.offset + line.length > end { throw PrefixEnd.reached }
                            if let end = segment.endOrdinal, let data = line.data,
                               let raw = try? JSONDecoder().decode(JSONValue.self, from: data),
                               let ordinal = raw["ordinal"].integer, ordinal >= end { throw PrefixEnd.reached }
                            var item = adapter.normalize(line, rawPath: segment.snapshot.parsePath, assetStore: assetStore)
                            item.conversationID = identity; item.ordinal = count
                            item.assets = item.assets.map { asset in
                                if asset.hash == nil, let saved = preserved[asset.sourceReference], saved.sourceReference != "Inline image" { return saved }
                                return asset
                            }
                            if item.isDiagnostic || item.assets.contains(where: { $0.missingReason != nil }) { warnings += 1 }
                            try Self.insert(item, db: db)
                            count += 1
                        }
                    } catch PrefixEnd.reached {}
                }
                for text in plan.warnings {
                    var warning = ArchiveItem()
                    warning.conversationID = identity; warning.ordinal = count; warning.kind = .systemEvent
                    warning.isDiagnostic = true; warning.sourceType = "inherited_history"
                    warning.text = text; warning.rawPath = snapshot.parsePath
                    try Self.insert(warning, db: db); warnings += 1; count += 1
                }
                let visible = try Int.fetchOne(db, sql: "SELECT count(*) FROM items WHERE conversationID=? AND hidden=0", arguments: [identity]) ?? count
                let meta = adapter.metadata
                if !force && !currentDate.isEmpty && !meta.updatedAt.isEmpty && meta.updatedAt < currentDate { throw ProjectionOutcome.older }
                try db.execute(sql: """
                    UPDATE conversations SET title=?,project=?,startedAt=?,updatedAt=?,itemCount=?,warningCount=?,snapshotID=? WHERE id=?
                    """, arguments: [meta.title.isEmpty ? "Untitled conversation" : meta.title, meta.project, meta.startedAt, meta.updatedAt, visible, warnings, snapshot.id, identity])
                try db.execute(sql: "UPDATE snapshots SET status='complete',parserVersion=?,error=NULL WHERE id=?", arguments: [CodexAdapter.version, snapshot.id])
            }
            return true
        } catch ProjectionOutcome.older {
            try database.write { db in try db.execute(sql: "UPDATE snapshots SET status='superseded',parserVersion=?,error=NULL WHERE id=?", arguments: [CodexAdapter.version, snapshot.id]) }
            return false
        } catch {
            try? database.write { db in try db.execute(sql: "UPDATE snapshots SET status='failed',error=? WHERE id=?", arguments: [error.localizedDescription, snapshot.id]) }
            throw error
        }
    }

    private enum ProjectionOutcome: Error { case older }

    private static func insert(_ original: ArchiveItem, db: Database) throws {
        var item = original
        if item.kind == .toolResult, !item.callID.isEmpty,
           let call = try Row.fetchOne(db, sql: "SELECT kind,toolName FROM items WHERE conversationID=? AND callID=? AND kind IN ('command','toolCall','fileChange') ORDER BY ordinal DESC LIMIT 1", arguments: [item.conversationID, item.callID]) {
            item.toolName = call["toolName"]
            if call["kind"] as String == ItemKind.command.rawValue { item.kind = .commandOutput }
        }
        var mirrorKey: String?; var family: String?; var hidden = false
        if item.kind == .message || item.kind == .reasoning {
            family = item.sourceType.hasPrefix("response_item/") ? "response" : "event"
            let signature = item.kind.rawValue + "\u{0}" + item.role + "\u{0}" + item.text
            mirrorKey = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
            // Pair only the most recent opposite representation, once. Repeated messages in the same family remain.
            if let prior = try Row.fetchOne(db, sql: "SELECT id,mirrorFamily FROM items WHERE conversationID=? AND mirrorKey=? AND hidden=0 AND ordinal>=? AND (turnID=? OR turnID='' OR ?='') ORDER BY id DESC LIMIT 1", arguments: [item.conversationID, mirrorKey, max(0, item.ordinal - 32), item.turnID, item.turnID]),
               prior["mirrorFamily"] as String? != family {
                // Mark the pair as consumed by clearing its key; keep the richer response representation.
                let priorID: Int64 = prior["id"]
                if family == "response" {
                    let assets = try Row.fetchAll(db, sql: "SELECT ia.sourceReference,ia.missingReason,a.* FROM item_assets ia LEFT JOIN assets a ON a.hash=ia.hash WHERE ia.itemID=? ORDER BY ia.position", arguments: [priorID]).map(Self.asset)
                    for asset in assets where !item.assets.contains(where: { asset.hash != nil ? $0.hash == asset.hash : $0.sourceReference == asset.sourceReference }) { item.assets.append(asset) }
                } else {
                    var position = try Int.fetchOne(db, sql: "SELECT count(*) FROM item_assets WHERE itemID=?", arguments: [priorID]) ?? 0
                    for asset in item.assets {
                        if let hash = asset.hash { try db.execute(sql: "INSERT OR IGNORE INTO assets VALUES(?,?,?,?,?,?)", arguments: [hash,asset.relativePath,asset.mimeType,asset.byteSize,asset.width,asset.height]) }
                        let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM item_assets WHERE itemID=? AND (hash=? OR sourceReference=?))", arguments: [priorID,asset.hash,asset.sourceReference]) ?? false
                        if !exists { try db.execute(sql: "INSERT INTO item_assets VALUES(?,?,?,?,?)", arguments: [priorID,position,asset.hash,asset.sourceReference,asset.missingReason]); position += 1 }
                    }
                }
                if family == "response" { try db.execute(sql: "UPDATE items SET hidden=1,mirrorKey=NULL WHERE id=?", arguments: [prior["id"] as Int64]) }
                else { hidden = true; try db.execute(sql: "UPDATE items SET mirrorKey=NULL WHERE id=?", arguments: [prior["id"] as Int64]) }
                mirrorKey = nil
            }
        }
        try db.execute(sql: """
            INSERT INTO items(conversationID,ordinal,kind,role,text,timestamp,turnID,toolName,callID,sourceType,rawOffset,rawLength,rawPath,isDiagnostic,mirrorKey,mirrorFamily,hidden)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, arguments: [item.conversationID, item.ordinal, item.kind.rawValue, item.role, item.text, item.timestamp, item.turnID, item.toolName, item.callID, item.sourceType, item.rawOffset, item.rawLength, item.rawPath, item.isDiagnostic, mirrorKey, family, hidden])
        let itemID = db.lastInsertedRowID
        for (position, asset) in item.assets.enumerated() {
            if let hash = asset.hash {
                try db.execute(sql: "INSERT OR IGNORE INTO assets VALUES(?,?,?,?,?,?)", arguments: [hash, asset.relativePath, asset.mimeType, asset.byteSize, asset.width, asset.height])
            }
            try db.execute(sql: "INSERT INTO item_assets VALUES(?,?,?,?,?)", arguments: [itemID, position, asset.hash, asset.sourceReference, asset.missingReason])
        }
    }

    private static func conversation(_ r: Row) -> Conversation {
        Conversation(id: r["id"], title: r["title"], project: r["project"], startedAt: r["startedAt"], updatedAt: r["updatedAt"], itemCount: r["itemCount"], snapshotID: r["snapshotID"], warningCount: r["warningCount"], preview: r["preview"])
    }
    private static func asset(_ r: Row) -> ArchivedAsset {
        ArchivedAsset(hash: r["hash"], relativePath: r["relativePath"], mimeType: r["mimeType"] ?? "", byteSize: r["byteSize"] ?? 0, width: r["width"], height: r["height"], sourceReference: r["sourceReference"], missingReason: r["missingReason"])
    }
    private static func item(_ r: Row, db: Database) throws -> ArchiveItem {
        var item = ArchiveItem()
        item.id = r["id"]; item.conversationID = r["conversationID"]; item.ordinal = r["ordinal"]
        item.kind = ItemKind(rawValue: r["kind"]) ?? .unknown; item.role = r["role"]; item.text = r["text"]
        item.textLength = r["textLength"]; item.timestamp = r["timestamp"]; item.turnID = r["turnID"]; item.toolName = r["toolName"]; item.callID = r["callID"]
        item.sourceType = r["sourceType"]; item.rawOffset = r["rawOffset"]; item.rawLength = r["rawLength"]; item.rawPath = r["rawPath"]; item.isDiagnostic = r["isDiagnostic"]
        item.assets = try Row.fetchAll(db, sql: "SELECT ia.sourceReference,ia.missingReason,a.* FROM item_assets ia LEFT JOIN assets a ON a.hash=ia.hash WHERE ia.itemID=? ORDER BY ia.position", arguments: [item.id]).map(Self.asset)
        return item
    }
}
