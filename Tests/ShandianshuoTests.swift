import Foundation

extension CoreTests {
    static func shandianshuoTests(in dir: URL) throws {
        // Saved through FlashSay 0.8.1's actual macOS UI, then checked after restart.
        let saved = try Data(contentsOf: URL(fileURLWithPath: "fixtures/shandianshuo-0.8.1-synthetic.md"))
        let actual = try Formats.read(saved, as: .shandianshuo)
        try check(actual.entries.map(\.word) == ["词渡星舟", "OpenAI", "重庆", "词渡星舟"], "FlashSay real UI date heading and row order")
        try check(Shandianshuo.origin(actual.entries[0])?.correctionFrom == "词度星舟", "FlashSay real UI correction syntax")
        try check(actual.entries.allSatisfy { $0.codeKind == "unpronounced" }, "FlashSay real UI contains no reviewed pronunciation")
        try fails("date-headed Markdown is not automatically classified as a dictionary") { _ = try Formats.read(saved) }
        let raw = Data("# 用户词典\r\n\r\n## 专有名词 / 固定写法\r\n词渡星舟\r\n重庆\r\n词渡星舟\r\nOpenAI\r\n𠮷野\r\n## 替换规则\r\n- 词度星舟 → 词渡星舟\r\n".utf8)
        let imported = try Formats.read(raw)
        let entries = imported.entries
        try check(imported.format == .shandianshuo && entries.count == 6, "FlashSay headings skipped, duplicate rows retained")
        try check(entries.allSatisfy { $0.codeKind == "unpronounced" && $0.syllables.isEmpty && !$0.hasBoundaries }, "FlashSay never infers confirmed pinyin")
        try check(entries.map(\.word) == ["词渡星舟","重庆","词渡星舟","OpenAI","𠮷野","词渡星舟"], "FlashSay Unicode and correction target retained")
        let origin = Shandianshuo.origin(entries[5])
        try check(origin?.line == 10 && origin?.raw == "- 词度星舟 → 词渡星舟" && origin?.correctionFrom == "词度星舟", "FlashSay CRLF source line and correction evidence retained")
        try check(try Formats.read(Data("词渡星舟\n".utf8), as: .shandianshuo).entries.count == 1, "FlashSay explicit plain dictionary")
        try fails("generic text must not be guessed as FlashSay") { _ = try Formats.read(Data("词渡星舟\n".utf8)) }
        for bad in ["", "# 用户词典\n", "好词\n坏 →\n", "好词\nA → B → C\n", "A -> B", "A => B", "[链接](https://example.com)", "```\n词语\n```", "词\u{0}语"] {
            try fails("FlashSay malformed input fails whole file") { _ = try Shandianshuo.read(Data(bad.utf8)) }
        }
        try check(Shandianshuo.suggestion("绿") == "lv", "FlashSay local pinyin preserves umlaut")
        try check(Shandianshuo.suggestion("OpenAI") == "" && Shandianshuo.suggestion("AI助手") == "", "FlashSay mixed Latin words require manual pinyin")
        let reviewed = try Shandianshuo.reviewed(entries, pronunciations: [0:"ci du xing zhou",1:"chong qing",5:"ci du xing zhou"])
        try check(reviewed.entries.count == entries.count && reviewed.entries[1].syllables == ["chong","qing"], "FlashSay explicit polyphone override")
        try check(reviewed.entries[2] == entries[2], "FlashSay unselected duplicate stays unreviewed")
        try check(reviewed.entries[5].sourceRawValue == entries[5].sourceRawValue, "FlashSay review retains correction provenance")
        for bad in ["", "chóng qìng", "chong  qing", "chong\tqing", "Chong qing", "chong1 qing4"] {
            try fails("FlashSay invalid reviewed pinyin") { _ = try Shandianshuo.reviewed(entries, pronunciations: [1:bad]) }
        }
        try fails("FlashSay invalid review row") { _ = try Shandianshuo.reviewed(entries, pronunciations: [99:"ci"] ) }
        try fails("FlashSay cannot relabel an unrelated source") { _ = try Shandianshuo.reviewed([Entry(word:"词",syllables:["ci"],sourceValue:1,source:"test")], pronunciations:[0:"ci"]) }
        for format in [OutputFormat.archive,.tsv] {
            let back = try Formats.read(Formats.write(reviewed.entries, as: format))
            try check(back.entries == reviewed.entries && !back.warnings.isEmpty, "FlashSay reviewed/unreviewed metadata roundtrip \(format)")
        }
        try check(Formats.assess(entries, for: .rime).blocked == entries.count, "FlashSay unreviewed export blocked")
        try fails("FlashSay partial conventional export never drops rows") { _ = try Formats.write(reviewed.entries, as: .rime) }
        let mapping = ["ci":1,"du":2,"xing":3,"zhou":4,"chong":5,"qing":6]
        let selection = DoubaoMerge.select(reviewed.entries, mapping: mapping)
        try check(selection.accepted.count == 3 && selection.rejected.count == 3, "FlashSay only reviewed entries reach merge")
        try check(DoubaoMerge.select(entries,mapping:mapping).accepted.isEmpty, "FlashSay raw input cannot reach merge")
        try check(DoubaoMerge.select(reviewed.entries,mapping:[:]).accepted.isEmpty, "FlashSay review cannot bypass engine mapping")
        let package = try Packages.create(in: dir, source: raw, imported: reviewed, format: .archive)
        let input = try MigrationInput.read(package)
        try check(input.original == raw && input.imported.entries == reviewed.entries && input.imported.format == .shandianshuo, "FlashSay package reads reviewed entries with exact original Markdown")
        var malformed = entries[0]; malformed.codeKind = "syllables"
        try fails("FlashSay no empty confirmed pinyin") { try Formats.validate([malformed]) }
        let forged = Entry(word:"词",syllables:["ci"],sourceValue:1,source:Shandianshuo.source,codeKind:"unpronounced")
        try fails("FlashSay unpronounced archive cannot hide pinyin") { try Formats.validate([forged]) }
    }
}
