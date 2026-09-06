import Foundation

struct HistorySegment {
    let snapshot: Snapshot
    let endByte: Int64?
    let endOrdinal: Int64?
}
struct HistoryPlan {
    var segments: [HistorySegment] = []
    var warnings: [String] = []
}

struct HistoryResolver {
    let root: URL
    let snapshots: [Snapshot]
    private enum Stop: Error { case found }

    func metadata(_ snapshot: Snapshot) throws -> SessionMetadata {
        var result = SessionMetadata()
        do {
            try JSONLReader().read(root.appendingPathComponent(snapshot.parsePath)) { line in
                guard let d = line.data, let raw = try? JSONDecoder().decode(JSONValue.self, from: d), raw["type"].string == "session_meta" else { return }
                let p = raw["payload"]
                result.sourceID = p["id"].string; result.project = p["cwd"].string; result.startedAt = p["timestamp"].string
                result.parentRolloutID = p["history_base"]["thread_id"].string
                result.parentEndByte = p["history_base"]["end_byte_offset"].integer
                result.parentEndOrdinal = p["history_base"]["end_ordinal_exclusive"].integer
                throw Stop.found
            }
        } catch Stop.found {}
        return result
    }

    func plan(for snapshot: Snapshot) throws -> HistoryPlan {
        var result = HistoryPlan()
        func visit(_ current: Snapshot, endByte: Int64?, endOrdinal: Int64?, seen: Set<String>) throws {
            guard !seen.contains(current.id), seen.count < 32 else {
                result.warnings.append("Inherited history contains a cycle or exceeds 32 levels. Original references remain archived."); return
            }
            let meta = try metadata(current)
            if !meta.parentRolloutID.isEmpty {
                let reference = meta.parentRolloutID
                // Physical rollout IDs come from filenames, not stable thread IDs after revert.
                let matches = snapshots.filter {
                    let name = URL(fileURLWithPath: $0.sourcePath).lastPathComponent.replacingOccurrences(of: ".zst", with: "")
                    return name.hasSuffix("-\(reference).jsonl")
                }
                if let parent = matches.last, let boundary = meta.parentEndByte, let ordinal = meta.parentEndOrdinal {
                    let size = (try root.appendingPathComponent(parent.parsePath).resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                    if boundary <= size {
                        try visit(parent, endByte: boundary, endOrdinal: ordinal, seen: seen.union([current.id]))
                    } else { result.warnings.append("Inherited rollout \(reference) is shorter than its declared prefix. Available child history is shown.") }
                } else { result.warnings.append("Inherited rollout \(reference) is unavailable or its prefix bounds are invalid. Import its source history to complete this conversation.") }
            }
            result.segments.append(HistorySegment(snapshot: current, endByte: endByte, endOrdinal: endOrdinal))
        }
        try visit(snapshot, endByte: nil, endOrdinal: nil, seen: [])
        return result
    }
}
