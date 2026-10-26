import Foundation

/// Interchange formats; never accesses system preference stores.
enum MacFormats {
    static func apple(_ data: Data) throws -> [Entry] {
        guard let rows = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw MigrationError("需要系统导出的自定义短语 PLIST 数组。")
        }
        return try rows.map { row in
            guard Set(row.keys) == ["phrase", "shortcut"], let phrase = row["phrase"] as? String, let shortcut = row["shortcut"] as? String else {
                throw MigrationError("系统短语字段不受支持；未忽略额外字段或继续部分读取。")
            }
            return Entry(word: phrase, syllables: [shortcut], sourceValue: 1, source: "macos-text-replacement", codeKind: "shortcut")
        }
    }

    static func microsoft(_ data: Data) throws -> [Entry] {
        let b = Array(data)
        func u32(_ i: Int) throws -> Int { Int(try Lexicon.u32(b, i)) }
        func u16(_ i: Int) throws -> Int {
            guard i >= 0, i + 2 <= b.count else { throw MigrationError("微软短语文件已截断。") }
            return Int(b[i]) | Int(b[i+1]) << 8
        }
        guard b.count >= 64, data.prefix(8) == Data("mschxudp".utf8),
              try u32(8) == 0x00600002, try u32(12) == 1, try u32(16) == 64,
              try u32(24) == b.count, b[36..<64].allSatisfy({ $0 == 0 }) else {
            throw MigrationError("只支持已识别版本的 mschxudp 自定义短语文件，不支持 DCTX 学习词库。")
        }
        let count = try u32(28), start = try u32(20)
        guard count > 0, count <= 20_000, start == 64 + 4 * count, start < b.count else { throw MigrationError("微软短语目录或条数无效。") }
        let offsets = try (0..<count).map { try u32(64 + 4 * $0) }
        guard offsets[0] == 0, zip(offsets, offsets.dropFirst()).allSatisfy({ $0 < $1 }), offsets.last! < b.count-start else { throw MigrationError("微软短语偏移表无效。") }
        func string(_ lo: Int, _ hi: Int) throws -> String {
            guard lo >= 0, hi <= b.count, hi - lo >= 2, (hi-lo) % 2 == 0, b[hi-2] == 0, b[hi-1] == 0,
                  let s = String(data: Data(b[lo..<hi-2]), encoding: .utf16LittleEndian), !s.contains("\0"), s.data(using: .utf16LittleEndian) == Data(b[lo..<hi-2]) else { throw MigrationError("微软短语包含无效 UTF-16 或终止符。") }
            return s
        }
        return try offsets.enumerated().map { i, offset in
            let lo = start + offset, hi = i+1 < count ? start + offsets[i+1] : b.count
            guard hi-lo >= 20, try u32(lo) == 0x00100010, b[lo+6] > 0, b[lo+7] == 6, try u32(lo+8) == 0 else { throw MigrationError("微软短语记录头不受支持。") }
            let wordStart = lo + (try u16(lo+4))
            guard wordStart >= lo+18, wordStart <= hi-2 else { throw MigrationError("微软短语记录长度无效。") }
            let shortcut = try string(lo+16, wordStart), phrase = try string(wordStart, hi)
            guard shortcut.utf16.count <= 32, shortcut.range(of: "^[a-z']+$", options: .regularExpression) != nil, !phrase.isEmpty, phrase.utf16.count <= 64 else { throw MigrationError("微软短语长度或缩写不受支持。") }
            return Entry(word: phrase, syllables: [shortcut], sourceValue: Int64(b[lo+6]), source: "microsoft-udp", codeKind: "shortcut", sourceRawValue: Data(b[lo..<hi]).base64EncodedString())
        }
    }
}
