import Foundation

/// Experimental decoder for known WeType keys. LevelDB only opens a disposable copy.
enum WeType {
    struct Snapshot: Codable {
        let schema: String
        let files: [String: Data]
    }
    static func filenames(_ folder: URL) throws -> [String] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard urls.count <= 4096 else { throw MigrationError("数据库文件过多。") }
        var names = [String]()
        for url in urls {
            let n = url.lastPathComponent
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard v.isSymbolicLink != true, v.isRegularFile == true else { throw MigrationError("数据库副本不能包含子目录或符号链接。") }
            // LOG/LOCK are diagnostic/locking artifacts, not database contents.
            if n == "LOCK" || n == "LOG" || n == "LOG.old" || n == ".DS_Store" { continue }
            guard n == "CURRENT" || n.range(of: "^(MANIFEST-[0-9]+|[0-9]+\\.(ldb|sst|log))$", options: .regularExpression) != nil else { throw MigrationError("文件夹包含未知数据库文件；请选择完整、已停止使用的微信词库副本。") }
            names.append(n)
        }
        guard names.contains("CURRENT") else { throw MigrationError("缺少 CURRENT；需要完整 LevelDB 数据库副本。") }
        return names.sorted()
    }
    static func capture(_ folder: URL) throws -> Data {
        let v = try folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard v.isDirectory == true, v.isSymbolicLink != true else { throw MigrationError("请选择数据库副本文件夹。") }
        let names = try filenames(folder)
        var files = [String: Data](), total = 0
        for name in names {
            let d = try Lexicon.boundedRead(folder.appendingPathComponent(name)); total += d.count
            guard total <= 40 * 1024 * 1024 else { throw MigrationError("微信数据库副本超过 40 MB，本版暂不支持。") }
            files[name] = d
        }
        guard try filenames(folder) == names else { throw MigrationError("数据库仍在变化，请退出输入法并重新复制。") }
        for name in names {
            guard try Lexicon.boundedRead(folder.appendingPathComponent(name)) == files[name] else { throw MigrationError("数据库仍在变化，请退出输入法并重新复制。") }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Snapshot(schema: "cidu.wetype-snapshot.v1", files: files))
    }
    // LevelDB can ignore torn WAL tails during recovery. A migration must report those,
    // rather than returning a misleading successful partial export.
    static func validateLog(_ data: Data) throws {
        let b = Array(data); var p = 0, fragment = false
        func crc(_ range: Range<Int>) -> UInt32 {
            var c = UInt32.max
            for x in b[range] { c ^= UInt32(x); for _ in 0..<8 { c = (c >> 1) ^ (c & 1 == 1 ? 0x82f63b78 : 0) } }
            return ~c
        }
        while p < b.count {
            let rem = 32768 - p % 32768
            if rem < 7 {
                let end = min(p+rem, b.count)
                guard b[p..<end].allSatisfy({ $0 == 0 }) else { throw MigrationError("数据库日志块尾损坏。") }; p = end; continue
            }
            guard p+7 <= b.count else { throw MigrationError("数据库日志尾部截断。") }
            let length = Int(b[p+4]) | Int(b[p+5]) << 8, type = b[p+6]
            if type == 0 && length == 0 {
                let end = min(p+rem, b.count)
                guard b[p..<end].allSatisfy({ $0 == 0 }) else { throw MigrationError("数据库日志填充无效。") }; p = end; continue
            }
            guard length+7 <= rem, p+7+length <= b.count, (1...4).contains(type) else { throw MigrationError("数据库日志记录已截断或不受支持。") }
            let c = crc((p+6)..<(p+7+length)); let masked = ((c >> 15) | (c << 17)) &+ 0xa282ead8
            guard try Lexicon.u32(b, p) == masked else { throw MigrationError("数据库日志校验和不一致。") }
            switch type {
            case 1: guard !fragment else { throw MigrationError("数据库日志分片不完整。") }
            case 2: guard !fragment else { throw MigrationError("数据库日志分片重复开始。") }; fragment = true
            case 3: guard fragment else { throw MigrationError("数据库日志分片缺少开头。") }
            case 4: guard fragment else { throw MigrationError("数据库日志分片缺少开头。") }; fragment = false
            default: break
            }
            p += 7+length
        }
        guard !fragment else { throw MigrationError("数据库日志分片已截断。") }
    }
    static func read(_ source: Data) throws -> ImportResult {
        guard source.count <= Lexicon.sizeLimit else { throw MigrationError("数据库快照超过大小限制。") }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: source)
        guard snapshot.schema == "cidu.wetype-snapshot.v1", snapshot.files.count <= 4096,
              let current = snapshot.files["CURRENT"], let name = String(data: current, encoding: .utf8), name.hasSuffix("\n"),
              String(name.dropLast()).range(of: "^MANIFEST-[0-9]+$", options: .regularExpression) != nil,
              snapshot.files[String(name.dropLast())] != nil else { throw MigrationError("数据库快照清单无效。") }
        let fm = FileManager.default, temp = fm.temporaryDirectory.appendingPathComponent("cidu-wetype-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temp) }
        for (name, data) in snapshot.files {
            guard name == "CURRENT" || name.range(of: "^(MANIFEST-[0-9]+|[0-9]+\\.(ldb|sst|log))$", options: .regularExpression) != nil else { throw MigrationError("快照文件名无效。") }
            if name.hasSuffix(".log") || name.hasPrefix("MANIFEST-") { try validateLog(data) }
            try Lexicon.saveNew(data, at: temp.appendingPathComponent(name))
        }
        let options = leveldb_options_create()!; defer { leveldb_options_destroy(options) }
        leveldb_options_set_create_if_missing(options, 0); leveldb_options_set_paranoid_checks(options, 1)
        var error: UnsafeMutablePointer<CChar>?
        let db = leveldb_open(options, temp.path, &error)
        if let error { leveldb_free(error); if let db { leveldb_close(db) }; throw MigrationError("数据库结构、比较器或校验不受支持；未返回部分词条。") }
        guard let db else { throw MigrationError("无法打开数据库副本。") }; defer { leveldb_close(db) }
        let readOptions = leveldb_readoptions_create()!; defer { leveldb_readoptions_destroy(readOptions) }
        leveldb_readoptions_set_verify_checksums(readOptions, 1)
        let iterator = leveldb_create_iterator(db, readOptions)!; defer { leveldb_iter_destroy(iterator) }
        var entries = [Entry](), unknown = 0, total = 0, rawBytes = 0
        leveldb_iter_seek_to_first(iterator)
        while leveldb_iter_valid(iterator) != 0 {
            total += 1
            guard total <= 1_000_000 else { throw MigrationError("数据库记录超过本版限制。") }
            var keySize = 0, valueSize = 0
            guard let keyPointer = leveldb_iter_key(iterator, &keySize), let valuePointer = leveldb_iter_value(iterator, &valueSize), keySize <= 1_048_576, valueSize <= 1_048_576 else { throw MigrationError("数据库记录无效或过大。") }
            rawBytes += keySize + valueSize
            guard rawBytes <= 40 * 1024 * 1024 else { throw MigrationError("解压后的数据库超过 40 MB 限制。") }
            let key = Data(bytes: keyPointer, count: keySize), value = Data(bytes: valuePointer, count: valueSize)
            if key.starts(with: Data("!u_d_v_p!".utf8)) {
                let parts = key.dropFirst(Data("!u_d_v_p!".utf8).count).split(separator: 1, maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3, !parts[2].isEmpty, let code = String(data: parts[0], encoding: .ascii), let word = String(data: parts[1], encoding: .utf8), !word.isEmpty,
                      code.range(of: "^[a-zv]+(,[a-zv]+)*$", options: .regularExpression) != nil else { throw MigrationError("微信短语键版本不受支持；已停止读取。") }
                let raw = try JSONSerialization.data(withJSONObject: ["key": key.base64EncodedString(), "value": value.base64EncodedString()], options: [.sortedKeys])
                entries.append(Entry(word: word, syllables: code.components(separatedBy: ","), sourceValue: 1, source: "wetype-macos-experimental", codeKind: !code.contains(",") && word.count > 1 ? "continuous" : "syllables", sourceRawValue: String(decoding: raw, as: UTF8.self)))
            } else { unknown += 1 }
            leveldb_iter_next(iterator)
        }
        leveldb_iter_get_error(iterator, &error)
        if let error { leveldb_free(error); throw MigrationError("数据库读取校验失败；未返回部分词条。") }
        try Formats.validate(entries)
        return ImportResult(entries: entries, format: .wetype, warnings: ["实验性读取：仅识别 !u_d_v_p! 短语键；另有 \(unknown) 条其他类型记录未解释。完整数据库副本保存在迁移包 source.original 中。", "原始键和值已保留；词频使用占位值 1，不代表真实使用次数。未验证微信实机候选，不提供写回。"])
    }
}
