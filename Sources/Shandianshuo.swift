import Foundation

/// FlashSay 0.8.1 stores spelling hints, not pinyin or input-method frequencies.
enum Shandianshuo {
    static let source = "shandianshuo-dictionary"
    static let warning = "闪电说词典没有拼音或词频。读音需逐条核对；纠错规则保留在档案中，迁入豆包的是正确写法的拼音候选，不代表语音识别或替换规则已生效。"

    struct Origin: Codable {
        let line: Int
        let raw: String
        let correctionFrom: String?
    }

    static func read(_ data: Data) throws -> ImportResult {
        guard data.count <= Lexicon.sizeLimit else { throw MigrationError("文件超过 64 MB。") }
        let text = try Formats.text(data)
        var entries = [Entry]()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for (offset, raw) in lines.enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Headings are retained verbatim in source.original, never treated as words.
            if line.range(of: "^#{1,6} +[^#]", options: .regularExpression) != nil { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            guard !line.isEmpty, !line.contains(where: { "`#<>|[]".contains($0) }), !line.hasPrefix("---"), !line.hasPrefix("!") else {
                throw MigrationError("闪电说词典第 \(offset + 1) 行包含尚未支持的 Markdown。请保留原件，将词条整理为一行一个，纠错写为「错写 → 正确写法」。")
            }
            let parts = line.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }), !line.contains("->"), !line.contains("=>") else {
                throw MigrationError("闪电说词典第 \(offset + 1) 行的纠错规则不明确；支持一个「→」连接错写与正确写法。")
            }
            let origin = Origin(line: offset + 1, raw: raw, correctionFrom: parts.count == 2 ? parts[0] : nil)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            entries.append(Entry(word: parts.last!, syllables: [], sourceValue: 1, source: source,
                                 codeKind: "unpronounced", sourceRawValue: String(decoding: try encoder.encode(origin), as: UTF8.self)))
        }
        try Formats.validate(entries)
        return ImportResult(entries: entries, format: .shandianshuo, warnings: [warning])
    }

    static func origin(_ entry: Entry) -> Origin? {
        guard entry.source == source, let raw = entry.sourceRawValue else { return nil }
        return try? JSONDecoder().decode(Origin.self, from: Data(raw.utf8))
    }

    /// A local suggestion only. Never used by the migration worker without review.
    static func suggestion(_ word: String) -> String {
        guard !word.isEmpty, word.unicodeScalars.allSatisfy({
            (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0x20000...0x3134F).contains($0.value)
        }), let latin = word.applyingTransform(.mandarinToLatin, reverse: false) else { return "" }
        // Preserve ü as v before removing tone marks.
        var scalars = [Unicode.Scalar]()
        for scalar in latin.decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.value == 0x0308, scalars.last == "u" {
                scalars[scalars.count - 1] = "v"
            } else {
                scalars.append(scalar)
            }
        }
        let decomposed = String(String.UnicodeScalarView(scalars))
        let plain = decomposed.applyingTransform(.stripCombiningMarks, reverse: false)?.lowercased() ?? ""
        return (try? syllables(plain)) != nil ? plain : ""
    }

    static func syllables(_ text: String) throws -> [String] {
        let parts = text.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        guard !parts.isEmpty, parts.allSatisfy({ $0.range(of: "^[a-zv]{1,6}$", options: .regularExpression) != nil }) else {
            throw MigrationError("请用空格分隔小写拼音，不带声调；ü 写作 v，例如「chong qing」。")
        }
        return parts
    }

    static func reviewed(_ entries: [Entry], pronunciations: [Int: String]) throws -> ImportResult {
        guard pronunciations.keys.allSatisfy({ entries.indices.contains($0) }) else { throw MigrationError("核对行号无效。") }
        let reviewed = try entries.enumerated().map { index, entry -> Entry in
            guard entry.source == source, origin(entry) != nil else { throw MigrationError("缺少闪电说来源记录，请重新读取原件。") }
            guard let text = pronunciations[index] else { return Entry(word: entry.word, syllables: [], sourceValue: entry.sourceValue, source: entry.source, codeKind: "unpronounced", sourceRawValue: entry.sourceRawValue) }
            return Entry(word: entry.word, syllables: try syllables(text), sourceValue: entry.sourceValue, source: entry.source, codeKind: "syllables", sourceRawValue: entry.sourceRawValue)
        }
        try Formats.validate(reviewed)
        return ImportResult(entries: reviewed, format: .shandianshuo, warnings: [warning])
    }
}

/// Both migration and preflight use the same verified package reader.
enum MigrationInput {
    static func read(_ url: URL, as format: InputFormat = .auto) throws -> (imported: ImportResult, original: Data) {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return (try Packages.verify(url), try Lexicon.boundedRead(url.appendingPathComponent("source.original")))
        }
        let data = try Lexicon.boundedRead(url)
        return (try Formats.read(data, as: format), data)
    }
}
