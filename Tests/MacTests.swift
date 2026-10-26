import Foundation

extension CoreTests {
    static func macTests(in dir: URL) throws {
        let rows = [["phrase": "示例短语𠮷", "shortcut": "sl"], ["phrase": "无缩写", "shortcut": ""], ["phrase": "a & b < c", "shortcut": "a b"], ["phrase": "示例短语𠮷", "shortcut": "sl"]]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let data = try PropertyListSerialization.data(fromPropertyList: rows, format: format, options: 0)
            let imported = try Formats.read(data)
            try check(imported.format == .apple && imported.entries.count == 4, "Apple XML/binary detection retains duplicates")
            let output = try Formats.write(imported.entries, as: .apple)
            try check(try PropertyListSerialization.propertyList(from: output, format: nil) as? [[String:String]] == rows, "Apple keys empty shortcuts and escaping preserved")
            try check(try Formats.read(Formats.write(imported.entries, as: .tsv)).entries == imported.entries, "shortcut TSV retains spaces and empty fields")
            try check(try Formats.read(Formats.write(imported.entries, as: .archive)).entries == imported.entries, "shortcut archive roundtrip")
            try fails("shortcuts never treated as pinyin") { _ = try Formats.write(imported.entries, as: .rime) }
            let pkg = try Packages.create(in: dir, source: data, imported: imported, format: .apple)
            try check(try Packages.verify(pkg).entries == imported.entries, "Apple migration package")
        }
        try fails("Apple unknown fields not discarded") { _ = try Formats.read(PropertyListSerialization.data(fromPropertyList: [["phrase":"词", "shortcut":"c", "future":"metadata"]], format: .xml, options: 0)) }
        try fails("normal lexicon not auto mapped to replacements") { _ = try Formats.write([Entry(word: "示例", syllables: ["shi","li"], sourceValue: 1, source: "test")], as: .apple) }
        // Independently constructed little-endian UDP fixture: one candidate sl -> 示例.
        var ms = Data([0x6d,0x73,0x63,0x68,0x78,0x75,0x64,0x70, 2,0,0x60,0, 1,0,0,0, 64,0,0,0, 68,0,0,0, 96,0,0,0, 1,0,0,0])
        ms.append(Data(repeating: 0, count: 36))
        ms.append(contentsOf: [0x10,0,0x10,0, 22,0,3,6, 0,0,0,0, 0,0,0,0, 0x73,0,0x6c,0,0,0, 0x3a,0x79,0x8b,0x4f,0,0])
        let microsoft = try Formats.read(ms)
        try check(microsoft.format == .microsoft && microsoft.entries[0].word == "示例" && microsoft.entries[0].sourceValue == 3, "Microsoft binary fixture with rank")
        try check(try Formats.read(Formats.write(microsoft.entries, as: .apple)).entries[0].syllables == ["sl"], "Microsoft to Mac keeps shortcut")
        var broken = ms; broken[64] = 1
        try fails("Microsoft bad offsets") { _ = try Formats.read(broken) }
        broken = ms; broken[12] = 2
        try fails("Microsoft unknown version") { _ = try Formats.read(broken) }
        broken = ms; broken.removeLast()
        try fails("Microsoft truncation") { _ = try Formats.read(broken) }
        broken = ms; broken[84] = 1
        try fails("Microsoft missing null") { _ = try Formats.read(broken) }

        let dbFolder = dir.appendingPathComponent("synthetic-wetype")
        let options = leveldb_options_create()!; defer { leveldb_options_destroy(options) }
        leveldb_options_set_create_if_missing(options, 1); leveldb_options_set_compression(options, 1)
        var error: UnsafeMutablePointer<CChar>?
        let db = leveldb_open(options, dbFolder.path, &error)!
        let writes = leveldb_writeoptions_create()!; defer { leveldb_writeoptions_destroy(writes) }
        func checked() throws { if let e = error { leveldb_free(e); error = nil; throw MigrationError("synthetic fixture DB failed") } }
        func put(_ key: String, _ value: String) throws {
            key.withCString { k in value.withCString { v in leveldb_put(db, writes, k, key.utf8.count, v, value.utf8.count, &error) } }; try checked()
        }
        let deleted = "!u_d_v_p!shan,chu\u{1}删除\u{1}1"
        try put(deleted, "old")
        try put("!u_d_v_p!shi,li\u{1}示例\u{1}1", "old-value")
        for i in 0..<400 { try put("metadata-\(i)", String(repeating: "compressible", count: 100)) }
        // Force SST with Snappy blocks, then leave update/delete/new entry in WAL.
        leveldb_compact_range(db, nil, 0, nil, 0)
        deleted.withCString { leveldb_delete(db, writes, $0, deleted.utf8.count, &error) }; try checked()
        try put("!u_d_v_p!shi,li\u{1}示例\u{1}1", "new-value")
        try put("!u_d_v_p!chong,qing\u{1}重庆\u{1}2", String(repeating: "fragment", count: 9000))
        leveldb_close(db)
        let snapshot = try WeType.capture(dbFolder), result = try WeType.read(snapshot)
        try check(result.entries.count == 2 && !result.entries.contains(where: { $0.word == "删除" }), "LevelDB SST plus WAL deletes respected")
        try check(result.entries.contains(where: { $0.syllables == ["chong", "qing"] }), "WeType syllable boundaries retained")
        let decoded = try JSONDecoder().decode(WeType.Snapshot.self, from: snapshot)
        try check(decoded.files.keys.contains(where: { $0.hasSuffix(".ldb") }), "fixture includes compressed SST")
        try check(try WeType.capture(dbFolder) == snapshot, "source files byte unchanged after reading")
        try check(result.entries.first(where: { $0.word == "示例" })!.sourceRawValue!.contains(Data("new-value".utf8).base64EncodedString()), "newest value supersedes SST value")
        try check(try Formats.read(snapshot).entries == result.entries, "snapshot directly reopenable")
        try check(try Formats.read(Formats.write(result.entries, as: .tsv)).entries == result.entries, "WeType raw metadata TSV roundtrip")
        let pkg = try Packages.create(in: dir, source: snapshot, imported: result, format: .rime)
        let verified = try Packages.verify(pkg)
        try check(verified.entries == result.entries && verified.format == .wetype && !verified.warnings.isEmpty, "WeType package retains origin and partial-read warning")
        try check(try Lexicon.boundedRead(pkg.appendingPathComponent("source.original")) == snapshot, "full unparsed source preserved")
        var files = decoded.files
        let log = files.keys.first(where: { $0.hasSuffix(".log") && files[$0]!.count > 10 })!
        files[log]![0] ^= 1
        let encoder = JSONEncoder()
        try fails("WAL checksum corruption rejected") { _ = try WeType.read(encoder.encode(WeType.Snapshot(schema: decoded.schema, files: files))) }
        files = decoded.files; files[log]!.removeLast()
        try fails("WAL truncation rejected") { _ = try WeType.read(encoder.encode(WeType.Snapshot(schema: decoded.schema, files: files))) }
        files = decoded.files; files["../escape"] = Data()
        try fails("snapshot traversal rejected") { _ = try WeType.read(encoder.encode(WeType.Snapshot(schema: decoded.schema, files: files))) }
        let link = dbFolder.appendingPathComponent("009999.ldb")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dbFolder.appendingPathComponent("CURRENT"))
        try fails("snapshot symlink rejected") { _ = try WeType.capture(dbFolder) }
    }
}
