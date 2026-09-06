import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Markdown

struct AssetStore {
    let root: URL
    let sourceRoot: URL
    var preserved: [String: ArchivedAsset] = [:]
    var archiveOnly = false

    func extract(from value: JSONValue, cwd: String) -> [ArchivedAsset] {
        var references: [String] = []
        func add(_ s: String) { if !s.isEmpty && !references.contains(s) { references.append(s) } }
        func walk(_ v: JSONValue) {
            switch v {
            case .object(let object):
                let type = object["type"]?.string ?? ""
                for (key, child) in object {
                    let s = child.string
                    if s.hasPrefix("data:image/") || s.hasPrefix("data:audio/") || s.hasPrefix("data:application/pdf;") { add(s) }
                    else if ["image_url", "audio_url", "saved_path", "image_path", "local_image_path", "local_audio"].contains(key) { add(s) }
                    else if ["images", "local_images"].contains(key) { child.array.forEach { add($0.string) } }
                    else if key == "result", type == "image_generation_call" || type == "image_generation_end" {
                        if s.hasPrefix("/") || s.hasPrefix("file:") { add(s) }
                        else if !s.isEmpty { add("data:image/png;base64," + s) }
                    } else if key == "data", type == "image", let mime = object["mimeType"]?.string, mime.hasPrefix("image/") {
                        add("data:\(mime);base64,\(s)")
                    } else if key == "path", type == "local_image" || type == "input_image" { add(s) }
                    if (key == "text" || key == "message"), !s.isEmpty {
                        let doc = Document(parsing: s)
                        func images(_ markup: any Markup) {
                            if let img = markup as? Markdown.Image, let src = img.source { add(src) }
                            markup.children.forEach { images($0) }
                        }
                        images(doc)
                    }
                    if key == "output" || key == "arguments" || key == "input", let data = s.data(using: .utf8),
                       let nested = try? JSONDecoder().decode(JSONValue.self, from: data) { walk(nested) }
                    if ["arguments", "input"].contains(key), object["name"]?.string.contains("view_image") == true,
                       let d = s.data(using: .utf8), let args = try? JSONDecoder().decode(JSONValue.self, from: d) { add(args["path"].string) }
                    if key == "referenced_image_paths" { child.array.forEach { add($0.string) } }
                    if case .object = child { walk(child) }
                    if case .array = child { walk(child) }
                }
            case .array(let list): list.forEach(walk)
            default: break
            }
        }
        walk(value)
        return references.map { archive($0, cwd: cwd) }
    }

    private func archive(_ reference: String, cwd: String) -> ArchivedAsset {
        let isInline = reference.hasPrefix("data:")
        let sourceLabel = isInline ? "Inline image" : reference
        func missing(_ reason: String) -> ArchivedAsset {
            ArchivedAsset(hash: nil, relativePath: nil, mimeType: "", byteSize: 0, width: nil, height: nil, sourceReference: sourceLabel, missingReason: reason)
        }
        if !isInline, let saved = preserved[reference], let path = saved.relativePath,
           FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) { return saved }
        if !isInline && archiveOnly { return missing("External asset was not available in the archive. Re-import the source to try copying it.") }
        let fm = FileManager.default
        let temp = root.appendingPathComponent("staging/asset-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        do {
            var hash = SHA256(); var count: Int64 = 0; var mime = "application/octet-stream"
            if isInline {
                guard let comma = reference.firstIndex(of: ","), reference[..<comma].hasSuffix(";base64"),
                      let data = Data(base64Encoded: String(reference[reference.index(after: comma)...]), options: .ignoreUnknownCharacters) else {
                    return missing("Invalid inline image encoding; original preserved in raw snapshot.")
                }
                mime = String(reference.dropFirst(5).prefix(while: { $0 != ";" }))
                hash.update(data: data); count = Int64(data.count); try data.write(to: temp, options: .atomic)
            } else {
                if let scheme = URL(string: reference)?.scheme, scheme != "file" { return missing("Remote asset was not downloaded. Histodex works offline.") }
                let path = reference.hasPrefix("file:") ? URL(string: reference)!.path : reference
                let base = cwd.isEmpty ? sourceRoot : URL(fileURLWithPath: cwd, isDirectory: true)
                let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { return missing("Not a regular file.") }
                guard (values.fileSize ?? 0) <= 256 * 1024 * 1024 else { return missing("Asset exceeds the 256 MiB import limit.") }
                let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
                fm.createFile(atPath: temp.path, contents: nil)
                let output = try FileHandle(forWritingTo: temp); defer { try? output.close() }
                // Size boundary also prevents following a continuously growing asset forever.
                var remaining = try input.seekToEnd(); guard remaining <= 256 * 1024 * 1024 else { return missing("Asset exceeds the 256 MiB import limit.") }; try input.seek(toOffset: 0)
                while remaining > 0 {
                    let data = try input.read(upToCount: Int(min(remaining, 128 * 1024))) ?? Data()
                    guard !data.isEmpty else { throw ArchiveError.truncatedSource }
                    remaining -= UInt64(data.count); count += Int64(data.count); hash.update(data: data)
                    try output.write(contentsOf: data)
                }
                try output.synchronize(); try output.close()
                mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? mime
            }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            let relative = "assets/sha256/\(digest.prefix(2))/\(digest)"
            let dest = root.appendingPathComponent(relative)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: dest.path) { try fm.moveItem(at: temp, to: dest) }
            var width: Int?; var height: Int?
            if let image = CGImageSourceCreateWithURL(dest as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
                let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any]
                width = props?[kCGImagePropertyPixelWidth] as? Int; height = props?[kCGImagePropertyPixelHeight] as? Int
                if let type = CGImageSourceGetType(image) { mime = UTType(type as String)?.preferredMIMEType ?? mime }
            }
            return ArchivedAsset(hash: digest, relativePath: relative, mimeType: mime, byteSize: count, width: width, height: height, sourceReference: sourceLabel, missingReason: nil)
        } catch { return missing("File unavailable or outside the selected folder's read permission: \(error.localizedDescription)") }
    }
}

extension JSONValue {
    /// The original bytes live once in raw storage. Never index embedded image bodies.
    var withoutImageBodies: JSONValue {
        switch self {
        case .string(let s): return s.hasPrefix("data:") && s.contains(";base64,") ? .string("[Archived asset]") : self
        case .array(let a): return .array(a.map(\.withoutImageBodies))
        case .object(let o):
            var result = o.mapValues(\.withoutImageBodies)
            if ["image_generation_call", "image_generation_end"].contains(o["type"]?.string ?? "") { result["result"] = .string("[Archived generated image]") }
            if o["type"]?.string == "image", o["data"] != nil { result["data"] = .string("[Archived image]") }
            return .object(result)
        default: return self
        }
    }
}
