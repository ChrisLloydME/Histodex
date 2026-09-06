import Foundation
import CryptoKit
import libzstd
import Darwin

public struct SourceFile: Sendable {
    public let url: URL
    public let relativePath: String
}

/// Deliberately offers no write operations. The only source handle is read-only.
public struct CodexSource: Sendable {
    public let root: URL
    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &dir), dir.boolValue else {
            throw ArchiveError.invalidSource("Select an existing Codex data folder.")
        }
    }
    public func discover() throws -> [SourceFile] {
        let fm = FileManager.default
        var files: [SourceFile] = []
        for directory in ["sessions", "archived_sessions"] {
            let base = root.appendingPathComponent(directory)
            if (try? base.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            guard let e = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if v.isSymbolicLink == true { e.skipDescendants(); continue }
                guard v.isRegularFile == true, url.lastPathComponent.hasPrefix("rollout-"),
                      url.path.hasSuffix(".jsonl") || url.path.hasSuffix(".jsonl.zst") else { continue }
                if url.path.hasSuffix(".zst"), fm.fileExists(atPath: url.deletingPathExtension().path) { continue }
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(root.path + "/") else { continue }
                files.append(SourceFile(url: resolved, relativePath: String(resolved.path.dropFirst(root.path.count + 1))))
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }
    func open(_ file: SourceFile) throws -> FileHandle {
        guard file.url.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else {
            throw ArchiveError.invalidSource("Source path escaped the selected folder.")
        }
        let descriptor = Darwin.open(file.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(descriptor)
            throw ArchiveError.invalidSource("Rollout source is not a regular file.")
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}

struct Snapshot: Sendable {
    let id: String
    let rawPath: String
    let parsePath: String
    let byteSize: UInt64
    let sourcePath: String
}

struct SnapshotStore {
    let root: URL
    init(root: URL) throws {
        self.root = root
        for p in ["raw", "assets/sha256", "staging", "thumbnails"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(p), withIntermediateDirectories: true)
        }
    }
    func snapshot(source: CodexSource, file: SourceFile) throws -> Snapshot {
        let input = try source.open(file); defer { try? input.close() }
        let size = try input.seekToEnd(); try input.seek(toOffset: 0)
        let staging = root.appendingPathComponent("staging/\(UUID().uuidString)")
        FileManager.default.createFile(atPath: staging.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: staging) }
        let output = try FileHandle(forWritingTo: staging); defer { try? output.close() }
        var remaining = size; var hash = SHA256()
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try input.read(upToCount: Int(min(remaining, 256 * 1024))) ?? Data()
            guard !data.isEmpty else { throw ArchiveError.truncatedSource }
            remaining -= UInt64(data.count); hash.update(data: data); try output.write(contentsOf: data)
        }
        try output.synchronize(); try output.close()
        let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let compressed = file.url.path.hasSuffix(".zst")
        let raw = "raw/\(id).jsonl" + (compressed ? ".zst" : "")
        let rawURL = root.appendingPathComponent(raw)
        if !FileManager.default.fileExists(atPath: rawURL.path) { try FileManager.default.moveItem(at: staging, to: rawURL) }
        let parse = "raw/\(id).jsonl"
        if compressed, !FileManager.default.fileExists(atPath: root.appendingPathComponent(parse).path) {
            try decompress(rawURL, to: root.appendingPathComponent(parse))
        }
        return Snapshot(id: id, rawPath: raw, parsePath: parse, byteSize: size, sourcePath: file.relativePath)
    }
    private func decompress(_ source: URL, to destination: URL) throws {
        let temp = root.appendingPathComponent("staging/\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temp) }
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let output = try FileHandle(forWritingTo: temp); defer { try? output.close() }
        guard let context = ZSTD_createDStream() else { throw ArchiveError.corruptCompression("Cannot allocate Zstandard decoder.") }
        defer { ZSTD_freeDStream(context) }
        // Bound decoder window memory even for untrusted archives.
        let parameter = ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, 27)
        guard ZSTD_isError(parameter) == 0 else { throw ArchiveError.corruptCompression("Cannot limit Zstandard decoder memory.") }
        var lastResult = 1
        var buffer = [UInt8](repeating: 0, count: 128 * 1024)
        while let data = try input.read(upToCount: 128 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            try data.withUnsafeBytes { bytes in
                var src = ZSTD_inBuffer(src: bytes.baseAddress, size: bytes.count, pos: 0)
                while src.pos < src.size {
                    let before = src.pos
                    try buffer.withUnsafeMutableBytes { bytes in
                        var dst = ZSTD_outBuffer(dst: bytes.baseAddress, size: bytes.count, pos: 0)
                        lastResult = ZSTD_decompressStream(context, &dst, &src)
                        guard ZSTD_isError(lastResult) == 0 else {
                            throw ArchiveError.corruptCompression(String(cString: ZSTD_getErrorName(lastResult)))
                        }
                        try output.write(contentsOf: Data(bytes: bytes.baseAddress!, count: dst.pos))
                        if src.pos == before && dst.pos == 0 { throw ArchiveError.corruptCompression("Zstandard decoder made no progress.") }
                    }
                }
            }
        }
        guard lastResult == 0 else { throw ArchiveError.corruptCompression("Incomplete Zstandard frame; the raw compressed snapshot was preserved.") }
        try output.synchronize(); try output.close()
        try FileManager.default.moveItem(at: temp, to: destination)
    }
}

struct RawLine {
    let data: Data?
    let offset: Int64
    let length: Int64
    let terminated: Bool
}

/// Keeps at most one bounded record plus a 64 KiB read buffer in memory.
struct JSONLReader {
    let maximumRecordBytes: Int
    init(maximumRecordBytes: Int = 32 * 1024 * 1024) { self.maximumRecordBytes = maximumRecordBytes }
    func read(_ url: URL, consume: (RawLine) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var pending = Data(); var offset: Int64 = 0; var length: Int64 = 0; var oversized = false
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            var start = chunk.startIndex
            for i in chunk.indices where chunk[i] == 10 {
                let part = chunk[start...i]; length += Int64(part.count)
                if !oversized && pending.count + part.count <= maximumRecordBytes { pending.append(contentsOf: part) }
                else { oversized = true; pending.removeAll(keepingCapacity: false) }
                try consume(RawLine(data: oversized ? nil : pending, offset: offset, length: length, terminated: true))
                offset += length; length = 0; pending.removeAll(keepingCapacity: true); oversized = false
                start = chunk.index(after: i)
            }
            if start < chunk.endIndex {
                let part = chunk[start...]; length += Int64(part.count)
                if !oversized && pending.count + part.count <= maximumRecordBytes { pending.append(contentsOf: part) }
                else { oversized = true; pending.removeAll(keepingCapacity: false) }
            }
        }
        if length > 0 { try consume(RawLine(data: oversized ? nil : pending, offset: offset, length: length, terminated: false)) }
    }
}
