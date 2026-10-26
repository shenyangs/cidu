import Foundation
import Darwin

struct MigrationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct Entry: Codable, Equatable {
    let word: String
    let syllables: [String]
    let sourceValue: Int64
    let source: String
    var codeKind: String? = nil
    var nativeSyllables: [Int]? = nil
    var nativeAttributes: [Int]? = nil
    var sourceRawValue: String? = nil
    var hasBoundaries: Bool { codeKind == nil || codeKind == "syllables" }
    var candidateKey: String { word + "\u{1f}" + syllables.joined().lowercased().replacingOccurrences(of: "'", with: "") }
    var exactKey: String { word + "\u{1f}" + (nativeSyllables.map { "native:" + $0.map(String.init).joined(separator: ",") } ?? ((codeKind ?? "syllables") + ":" + syllables.joined(separator: " "))) }
}

struct Archive: Codable {
    let schema: String
    let createdAt: String
    let sourceValueMeaning: String
    let entries: [Entry]
}

struct DoubaoReport: Codable {
    let slots: Int
    let headerUsed: Int
    let decoded: Int
    let malformed: Int
    let duplicateOffsets: Int
    let candidateKeys: Set<String>
    let entries: [Entry]
    var consistent: Bool { headerUsed == decoded && malformed == 0 && duplicateOffsets == 0 }
}

enum Lexicon {
    static let sizeLimit = 64 * 1024 * 1024
    static func boundedRead(_ url: URL, limit: Int = sizeLimit) throws -> Data {
        guard limit > 0, limit <= sizeLimit else { throw MigrationError("读取上限无效。") }
        // Open once: a path swap cannot redirect the read after the size check.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw MigrationError("无法读取文件，请确认文件存在、不是符号链接且具有读取权限。") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw MigrationError("只能读取普通词库文件。") }
        guard info.st_size <= limit else { throw MigrationError("文件超过读取大小限制，请拆分来源或重新生成记录。") }
        var data = Data()
        while let chunk = try file.read(upToCount: min(65536, limit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw MigrationError("文件大小超出限制。") }
        }
        return data
    }

    static func parseBaidu(_ data: Data) throws -> [Entry] {
        let encoding: String.Encoding = data.starts(with: [0xff, 0xfe]) ? .utf16LittleEndian : data.starts(with: [0xfe, 0xff]) ? .utf16BigEndian : .utf8
        guard let text = String(data: data, encoding: encoding) else { throw MigrationError("无法解码。请使用百度 Mac 设置 → 词库 → 用户词库 → 导出。") }
        let regex = try NSRegularExpression(pattern: #"^(.+)\(([^()]*)\)\s+(-?\d+)\s*$"#)
        var out = [Entry]()
        var invalid = [Int]()
        for (i, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
            if line.isEmpty { continue }
            let ns = line as NSString
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let value = Int64(ns.substring(with: m.range(at: 3))) else { invalid.append(i + 1); continue }
            let word = ns.substring(with: m.range(at: 1))
            let code = ns.substring(with: m.range(at: 2))
            let syllables = code.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard !word.contains("\t"), !word.contains("\u{1f}"), !syllables.contains(where: { $0.isEmpty || $0.contains("\t") || $0.contains("\u{1f}") }) else { invalid.append(i + 1); continue }
            out.append(Entry(word: word, syllables: syllables, sourceValue: value, source: "baidu-macos-export"))
        }
        guard invalid.isEmpty else { throw MigrationError("有 \(invalid.count) 行无法识别（起始行号：\(invalid.prefix(5).map(String.init).joined(separator: "、"))）。已停止，不会静默跳过。") }
        guard !out.isEmpty else { throw MigrationError("没有找到词条。当前支持百度 Mac 官方导出文本，不支持直接打开 usr3user.bin。") }
        return out
    }

    static func u16(_ b: [UInt8], _ i: Int) throws -> Int {
        guard i >= 0 && i + 2 <= b.count else { throw MigrationError("词库字段越界。") }
        return Int(b[i]) | Int(b[i+1]) << 8
    }
    static func u32(_ b: [UInt8], _ i: Int) throws -> Int {
        guard i >= 0 && i + 4 <= b.count else { throw MigrationError("词库字段越界。") }
        return Int(b[i]) | Int(b[i+1]) << 8 | Int(b[i+2]) << 16 | Int(b[i+3]) << 24
    }
    static func decodeDoubao(_ data: Data) throws -> DoubaoReport {
        let b = Array(data)
        guard b.count >= 64 else { throw MigrationError("豆包文件头不完整。") }
        let h = try (0..<16).map { try u32(b, $0 * 4) }
        guard h[0] == 12001, h[1] == 20230630, h[2] == 64,
              h[3] == b.count, h[4] == 64, h[4] + h[5] == h[6],
              h[7] == h[8] * 4, h[8] > 0, h[8] <= 1_000_000,
              h[9] <= h[8], h[6] + h[7] == h[10],
              h[10] + h[11] == b.count, h[12] < h[11],
              Array(h[13...15]) == [2, 2, 16] else { throw MigrationError("豆包文件结构不在已验证范围内。请保留原文件，等待适配。") }
        var keys = Set<String>(), offsets = Set<Int>()
        var decoded = 0, malformed = 0, duplicateOffsets = 0
        var entries = [Entry]()
        for slot in h[9]..<h[8] {
            guard try u32(b, h[6] + slot * 4) == 0 else {
                throw MigrationError("已用索引数量与词库尾部不一致。")
            }
        }
        // Used entries form a contiguous prefix. Offset zero is a valid record.
        for slot in 0..<h[9] {
            let off = try u32(b, h[6] + slot * 4)
            guard offsets.insert(off).inserted else { duplicateOffsets += 1; continue }
            do {
                guard off < h[12] else { throw MigrationError("非法偏移") }
                let pos = h[10] + off
                let sl = try u16(b, pos + 16)
                guard sl > 0, sl % 2 == 0 else { throw MigrationError("音节损坏") }
                let plen = try u16(b, pos + 18 + sl)
                let payload = pos + 20 + sl
                guard plen >= 4, payload + plen <= h[10] + h[12] else { throw MigrationError("记录越界") }
                let pyl = try u16(b, payload)
                guard pyl > 0, 4 + pyl <= plen else { throw MigrationError("拼音越界") }
                let pyBytes = b[(payload+2)..<(payload+2+pyl)].map { UInt8((Int($0) >> 5 | Int($0) << 3) & 255) ^ 0xa5 }
                guard let py = String(bytes: pyBytes, encoding: .utf8) else { throw MigrationError("拼音编码损坏") }
                let wn = try u16(b, payload + 2 + pyl)
                guard wn > 0, 4 + pyl + wn * 2 == plen else { throw MigrationError("词语越界") }
                var bytes = [UInt8]()
                for j in 0..<wn {
                    let c = try u16(b, payload + 4 + pyl + j * 2)
                    let cp = ((c >> 9 | c << 7) & 65535) ^ 0x65c9
                    bytes.append(UInt8(cp & 255)); bytes.append(UInt8(cp >> 8))
                }
                guard let word = String(data: Data(bytes), encoding: .utf16LittleEndian), !word.isEmpty else { throw MigrationError("词语编码损坏") }
                let ids = try stride(from: pos + 18, to: pos + 18 + sl, by: 2).map { try u16(b, $0) }
                let attrs = try (0..<4).map { try u32(b, pos + $0 * 4) }
                let entry = Entry(word: word, syllables: [py], sourceValue: Int64(attrs[0]), source: "doubao-macos", codeKind: "native", nativeSyllables: ids, nativeAttributes: attrs)
                entries.append(entry)
                keys.insert(entry.candidateKey)
                decoded += 1
            } catch { malformed += 1 }
        }
        return DoubaoReport(slots: h[8], headerUsed: h[9], decoded: decoded, malformed: malformed, duplicateOffsets: duplicateOffsets, candidateKeys: keys, entries: entries)
    }

    static func discoverDoubao() -> [URL] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DoubaoIme")
        var result = [URL]()
        let accounts = root.appendingPathComponent("EngineUserDictAccounts")
        for folder in (try? FileManager.default.contentsOfDirectory(at: accounts, includingPropertiesForKeys: nil)) ?? [] {
            let p = folder.appendingPathComponent("usr.dat")
            if FileManager.default.fileExists(atPath: p.path) { result.append(p) }
        }
        for rel in ["EngineUserDict/usr.dat", "usr.dat"] {
            let p = root.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: p.path) { result.append(p) }
        }
        return result.sorted { $0.path < $1.path }
    }

    static func archive(_ entries: [Entry]) throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(Archive(schema: "cidu.archive.v1", createdAt: ISO8601DateFormatter().string(from: Date()), sourceValueMeaning: "保留各来源原始数值，语义由 source 标识；不同引擎的数值不可直接比较。sourceRawValue 保留非整数权重。", entries: entries))
    }
    static func tsv(_ entries: [Entry]) -> String {
        "word\tpinyin\tsource_value\tsource\n" + entries.map { "\($0.word)\t\($0.syllables.joined(separator: " "))\t\($0.sourceValue)\t\($0.source)" }.joined(separator: "\n") + "\n"
    }
    static func rimeEligible(_ e: Entry) -> Bool {
        e.hasBoundaries && !e.syllables.isEmpty && e.syllables.allSatisfy { $0.range(of: #"^[a-zv]+$"#, options: .regularExpression) != nil }
    }
    static func rime(_ entries: [Entry]) throws -> String {
        let rejected = entries.filter { !rimeEligible($0) }.count
        guard rejected == 0 else { throw MigrationError("有 \(rejected) 条编码无法保真写入 Rime。请先导出完整 JSON / TSV；本次不生成部分文件。") }
        return "# Rime dictionary\n# Source values are retained in the JSON archive; weights use 1.\n---\nname: cidu_personal\nversion: \"1\"\nsort: by_weight\nuse_preset_vocabulary: false\n...\n" + entries.map { "\($0.word)\t\($0.syllables.joined(separator: " "))\t1" }.joined(separator: "\n") + "\n"
    }
    static func saveNew(_ data: Data, at url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw MigrationError(errno == EEXIST ? "该文件已存在，请换一个名称以保留原件。" : "无法创建导出文件，请检查目录权限。") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try file.write(contentsOf: data)
            try file.synchronize()
            try file.close()
        } catch {
            try? file.close()
            try? FileManager.default.removeItem(at: url)
            throw MigrationError("导出未完成，已移除本次不完整文件。请检查剩余磁盘空间。")
        }
    }
}
