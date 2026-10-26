import Foundation
import Darwin

@main struct CoreTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw MigrationError("FAIL: " + name) }; checks += 1
    }
    static func fails(_ name: String, _ f: () throws -> Void) throws {
        do { try f() } catch { checks += 1; return }
        throw MigrationError("FAIL: expected rejection: " + name)
    }
    static func fixture() -> Data {
        // One manually constructed record: 示例 / shili; not real user data.
        let py = Array("shili".utf8).map { b -> UInt8 in let x = Int(b ^ 0xa5); return UInt8((x << 5 | x >> 3) & 255) }
        var val = [UInt8](repeating: 0, count: 16)
        func put16(_ n: Int) { val.append(UInt8(n & 255)); val.append(UInt8(n >> 8)) }
        put16(4); put16(100); put16(101); put16(13); put16(5); val += py; put16(2)
        for cp in "示例".utf16 { let x = Int(cp) ^ 0x65c9; put16((x >> 7 | x << 9) & 65535) }
        let h = [12001,20230630,64,256,64,140,204,8,2,1,212,44,40,2,2,16]
        var bytes = h.flatMap { n in (0..<4).map { UInt8((n >> ($0 * 8)) & 255) } }
        bytes += [UInt8](repeating: 0, count: 140)
        bytes += [1,0,0,0,0,0,0,0,0]; bytes += val
        bytes += [UInt8](repeating: 0, count: 256 - bytes.count)
        return Data(bytes)
    }
    static func main() throws {
        let source = "示例(shi|li) 55000\r\n重庆(chong|qing) 60001\r\n重庆(zhong|qing) 42\r\n𠮷野(ji|ye) 7\r\n示例(shi|li) 9\r\n"
        var bytes = Data([255,254]); bytes.append(source.data(using: .utf16LittleEndian)!)
        let entries = try Lexicon.parseBaidu(bytes)
        try check(entries.count == 5, "all rows retained")
        try check(Set(entries.map(\.exactKey)).count == 4, "polyphonic words remain distinct")
        try check(entries[3].word == "𠮷野", "non-BMP characters preserved")
        let archive = try JSONDecoder().decode(Archive.self, from: Lexicon.archive(entries))
        try check(archive.entries == entries, "lossless archive roundtrip incl duplicates")
        let otherCodes = try Lexicon.parseBaidu(Data("示例(Shi|li1) 7".utf8))
        try check(otherCodes[0].syllables == ["Shi", "li1"], "preserve original code case and unsupported codes")
        try fails("unsupported Rime codes never silently dropped") { _ = try Lexicon.rime(otherCodes) }
        try check(try Lexicon.rime(entries).contains("重庆\tchong qing\t1"), "Rime spelling boundaries")
        try fails("malformed rows fail whole import") { _ = try Lexicon.parseBaidu(Data((source + "bad row").utf8)) }
        try fails("invalid UTF8") { _ = try Lexicon.parseBaidu(Data([0xff])) }
        try fails("empty file") { _ = try Lexicon.parseBaidu(Data()) }
        try fails("binary instead of text") { _ = try Lexicon.parseBaidu(Data(repeating: 0, count: 128)) }
        try fails("ambiguous empty syllable") { _ = try Lexicon.parseBaidu(Data("示例(shi||li) 2".utf8)) }
        let report = try Lexicon.decodeDoubao(fixture())
        try check(report.decoded == 1 && report.consistent, "valid binary fixture")
        try check(report.candidateKeys.contains(entries[0].candidateKey), "cross-format candidate overlap")
        var zeroOffset = fixture(); zeroOffset[204] = 0
        for i in 212..<255 { zeroOffset[i] = zeroOffset[i+1] }; zeroOffset[255] = 0
        try check(try Lexicon.decodeDoubao(zeroOffset).consistent, "zero offset inside used index is valid")
        var unused = fixture(); unused[208] = 1
        try fails("nonzero unused index rejected") { _ = try Lexicon.decodeDoubao(unused) }
        var truncated = fixture(); truncated.removeLast()
        try fails("truncated binary") { _ = try Lexicon.decodeDoubao(truncated) }
        var corrupt = fixture(); corrupt[204] = 255
        try check(try Lexicon.decodeDoubao(corrupt).malformed == 1, "invalid offset counted")
        var stale = fixture(); stale[36] = 2
        try check(try !Lexicon.decodeDoubao(stale).consistent, "stale count blocks validation")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("archive.json")
        try Lexicon.saveNew(Data("original".utf8), at: dest)
        try fails("never overwrite") { try Lexicon.saveNew(Data("changed".utf8), at: dest) }
        try check(try String(contentsOf: dest, encoding: .utf8) == "original", "original survives")
        let mode = try FileManager.default.attributesOfItem(atPath: dest.path)[.posixPermissions] as? Int
        try check(mode == 0o600, "private export permissions")
        try check(try Lexicon.boundedRead(dest) == Data("original".utf8),"bounded ordinary file read")
        try fails("bounded read honors caller limit") { _ = try Lexicon.boundedRead(dest,limit:4) }
        let linkedRead = dir.appendingPathComponent("read-link")
        try FileManager.default.createSymbolicLink(at:linkedRead,withDestinationURL:dest)
        try fails("bounded read refuses symlink") { _ = try Lexicon.boundedRead(linkedRead) }
        try fails("bounded read refuses directory") { _ = try Lexicon.boundedRead(dir) }
        let fifo = dir.appendingPathComponent("pipe")
        guard mkfifo(fifo.path,0o600) == 0 else { throw MigrationError("test FIFO creation failed") }
        try fails("bounded read refuses FIFO without blocking") { _ = try Lexicon.boundedRead(fifo) }
        let huge = dir.appendingPathComponent("oversize")
        try Lexicon.saveNew(Data(),at:huge)
        let hugeFile = try FileHandle(forWritingTo:huge); try hugeFile.truncate(atOffset:UInt64(Lexicon.sizeLimit+1)); try hugeFile.close()
        try fails("bounded read refuses oversize file") { _ = try Lexicon.boundedRead(huge) }
        try check(try Formats.read(Formats.write(entries, as: .baidu)).entries == entries, "Baidu text lossless including duplicates and Unicode")
        for format in [OutputFormat.archive, .tsv] {
            try check(try Formats.read(Formats.write(entries, as: format)).entries == entries, "exchange roundtrip \(format)")
            try check(try Formats.read(Formats.write(report.entries, as: format)).entries == report.entries, "native metadata roundtrip \(format)")
        }
        try check(Formats.assess(report.entries, for: .rime).blocked == 1, "unknown native boundaries block conversion")
        let simple = Array(entries.prefix(3))
        let sogou = try Formats.read(Formats.write(simple, as: .sogou))
        try check(sogou.format == .sogou && sogou.entries.map(\.candidateKey) == simple.map(\.candidateKey), "GBK Sogou text roundtrip")
        try fails("non-GBK word cannot be silently replaced") { _ = try Formats.write(entries, as: .sogou) }
        let rime = try Formats.read(Formats.write(entries, as: .rime))
        try check(rime.entries.map(\.candidateKey) == entries.map(\.candidateKey), "Rime roundtrip preserves codes and duplicate rows")
        let weighted = Data("---\nname: sample\ncolumns: [code, weight, text]\n...\nshi li\t12.5%\t示例\n".utf8)
        let weights = try Formats.read(weighted)
        try check(weights.entries[0].sourceRawValue == "12.5%", "Rime fractional weight kept raw")
        try check(try Formats.read(Formats.write(weights.entries, as: .tsv)).entries == weights.entries, "TSV preserves raw weight")
        try fails("Rime dependencies cannot be silently lost") { _ = try Formats.read(Data("---\nname: sample\nimport_tables:\n - external\n...\n示例\tshi li\n".utf8)) }
        try fails("Rime implicit codes unsupported") { _ = try Formats.read(Data("---\nname: sample\n...\n示例\n".utf8)) }
        try fails("unknown archive schema") {
            let d = try Lexicon.archive(entries)
            let s = String(data: d, encoding: .utf8)!.replacingOccurrences(of: "cidu.archive.v1", with: "cidu.archive.v999")
            _ = try Formats.read(Data(s.utf8))
        }
        try fails("malformed TSV rejected") { _ = try Formats.read(Data("word\tpinyin\tsource_value\tsource\n示例\tshi li\tnan\tx\n".utf8)) }
        let imported = try Formats.read(bytes)
        let package = try Packages.create(in: dir, source: bytes, imported: imported, format: .archive)
        try check(try Packages.verify(package).entries == entries, "portable package verifies and reopens")
        try check(try Data(contentsOf: package.appendingPathComponent("source.original")) == bytes, "package keeps exact source bytes")
        let packageMode = try FileManager.default.attributesOfItem(atPath: package.path)[.posixPermissions] as? Int
        try check(packageMode == 0o700, "private package permissions")
        let archiveFile = package.appendingPathComponent("archive.json")
        let originalArchive = try Data(contentsOf: archiveFile)
        try Data("corrupted".utf8).write(to: archiveFile)
        try fails("tampered package rejected") { _ = try Packages.verify(package) }
        try FileManager.default.removeItem(at: archiveFile)
        let linked = dir.appendingPathComponent("linked-archive.json")
        try originalArchive.write(to: linked)
        try FileManager.default.createSymbolicLink(at: archiveFile, withDestinationURL: linked)
        try fails("package symlink rejected") { _ = try Packages.verify(package) }
        let missingApp = Compatibility.inspect(app: dir, targets: [])
        try check(!missingApp.sameEngine && !missingApp.liveWriteAvailable, "missing app never enables write")
        let qq = try Formats.read(Data("shi'li 示例 42\r\nchong'qing 重庆 9\r\nshi'li 示例 2\r\n".utf8))
        try check(qq.format == .qq && qq.entries.count == 3, "QQ auto detect retains duplicates")
        try check(try Formats.read(Formats.write(qq.entries, as: .qq)).entries == qq.entries, "QQ UTF16 rank roundtrip")
        let google = try Formats.read(Data("示例\t42\tshi li\n重庆\t9\tchong qing\n示例\t2\tshi li\n".utf8))
        try check(google.format == .google && google.entries.count == 3, "Google auto detect")
        try check(try Formats.read(Formats.write(google.entries, as: .google)).entries == google.entries, "Google GBK rank roundtrip")
        for target in [OutputFormat.qq, .google] {
            let converted = try Formats.read(Formats.write(qq.entries, as: target))
            try check(converted.entries.map(\.word) == qq.entries.map(\.word), "new format cross-conversion rows")
            try check(try Formats.read(Formats.write(converted.entries, as: .tsv)).entries == converted.entries, "new format TSV metadata")
            let pkg = try Packages.create(in: dir, source: Data("shi'li 示例 42".utf8), imported: Formats.read(Data("shi'li 示例 42".utf8)), format: target)
            try check(try Packages.verify(pkg).entries.count == 1, "new target package verification")
        }
        try fails("QQ comma extension rejected") { _ = try Formats.read(Data("shi'li 示例 42,other".utf8), as: .qq) }
        try fails("QQ overflow rejected") { _ = try Formats.read(Data("shi'li 示例 2147483648".utf8), as: .qq) }
        try fails("Google extra column rejected") { _ = try Formats.read(Data("示例\t42\tshi li\textra".utf8), as: .google) }
        try fails("Google malformed pitch rejected") { _ = try Formats.read(Data("示例\t42\tshi1 li4".utf8), as: .google) }
        try fails("Google unrepresentable Unicode blocked") { _ = try Formats.write(entries, as: .google) }
        try check(try Formats.read(Formats.write(entries, as: .qq)).entries[3].word == "𠮷野", "QQ nonBMP retained")
        let spaced = Entry(word: "示 例", syllables: ["shi", "li"], sourceValue: 1, source: "test")
        try fails("QQ whitespace blocked") { _ = try Formats.write([spaced], as: .qq) }
        try check(try Formats.read(Formats.write([spaced], as: .google)).entries[0].word == spaced.word, "Google word spaces retained")
        try macTests(in: dir)
        try migrationTests(in: dir)
        print("PASS \(checks) checks")
        if let i = CommandLine.arguments.firstIndex(of: "--source"), CommandLine.arguments.count > i + 1 {
            let es = try Lexicon.parseBaidu(Lexicon.boundedRead(URL(fileURLWithPath: CommandLine.arguments[i+1])))
            let rt = try JSONDecoder().decode(Archive.self, from: Lexicon.archive(es))
            try check(rt.entries == es, "real source in-memory roundtrip")
            try check(try Formats.read(Formats.write(es, as: .tsv)).entries == es, "real source TSV roundtrip")
            print("real_source records=\(es.count) unique=\(Set(es.map(\.exactKey)).count) rime_eligible=\(es.filter(Lexicon.rimeEligible).count)")
            for p in Lexicon.discoverDoubao() {
                let t = try Lexicon.decodeDoubao(Lexicon.boundedRead(p))
                try check(try Formats.read(Formats.write(t.entries, as: .tsv)).entries == t.entries, "real target TSV metadata roundtrip")
                let keys = Set(es.map(\.candidateKey))
                print("target slots=\(t.slots) header=\(t.headerUsed) decoded=\(t.decoded) malformed=\(t.malformed) overlaps=\(keys.intersection(t.candidateKeys).count) union_lower_bound=\(keys.union(t.candidateKeys).count)")
            }
            if CommandLine.arguments.contains("--archive") {
                let p = URL(fileURLWithPath: CommandLine.arguments[i+1]).deletingLastPathComponent()
                try Lexicon.saveNew(Lexicon.archive(es), at: p.appendingPathComponent("词渡-完整档案.json"))
                try Lexicon.saveNew(Data(Lexicon.tsv(es).utf8), at: p.appendingPathComponent("词渡-通用词库.tsv"))
                print("Private JSON and TSV archives saved beside source.")
            }
        }
    }
}
