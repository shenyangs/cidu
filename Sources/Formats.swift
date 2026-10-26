import Foundation
import CoreFoundation

enum InputFormat: String, CaseIterable, Identifiable {
    case auto, archive, tsv, baidu, rime, sogou, qq, google, apple, microsoft, wetype, doubao
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "自动识别"
        case .apple: return "macOS 系统 · 自定义短语"
        case .microsoft: return "微软拼音 · 迁入 Mac 的短语文件"
        case .wetype: return "微信 Mac · 词库副本（实验）"
        case .archive: return "词渡完整档案 · JSON"
        case .tsv: return "词渡交换表格 · TSV"
        case .baidu: return "百度 Mac · 导出文本"
        case .rime: return "Rime / 鼠须管 · 拼音词典"
        case .sogou: return "搜狗 · 拼音 TXT"
        case .qq: return "QQ 拼音 · TXT"
        case .google: return "谷歌拼音 · 文本词库"
        case .doubao: return "豆包 Mac · usr.dat"
        }
    }
    var help: String {
        switch self {
        case .apple: return "选择系统设置 → 键盘 → 文本替换导出的 .plist。仅包含自定义短语，不包含自动学习词库。"
        case .microsoft: return "读取 mschxudp 自定义短语文件，可转换为 Mac 系统短语。微软拼音是 Windows 来源，不是 Mac 目标。"
        case .wetype: return "选择已退出微信输入法后复制的完整 LevelDB 文件夹。实验性读取已知短语键；不保证覆盖所有学习记录，不写回输入法。"
        case .auto: return "按文件内容识别。新增系统短语 PLIST、微软短语文件与微信 Mac 数据库副本。支持百度、搜狗 / QQ 拼音 TXT、谷歌拼音文本、Rime 拼音词典、豆包主词库，以及词渡 JSON / TSV。"
        case .archive: return "重新打开词渡完整档案，保留每条记录、来源和原始字段。"
        case .tsv: return "接受词渡导出的带列名 TSV；不猜测其他表格的列含义。"
        case .baidu: return "百度设置 → 词库 → 用户词库 → 导出。原生 usr3user.bin 暂不支持。"
        case .rime: return "选择 .dict.yaml 文本词典。支持明确的 text / code / weight 列；不展开 import_tables，不读取 userdb 数据库。"
        case .sogou: return "支持每行「'pin'yin 词语」的拼音 TXT（UTF-8 / UTF-16 / GBK）。不支持 .bin / .scel 或自定义短语格式。"
        case .qq: return "支持 UTF-16 / UTF-8 的「pin'yin 词语 词频」文本。暂不支持逗号扩展字段、QPyd / Qcel 和自定义短语。"
        case .google: return "支持 GBK / UTF-8 的三列文本：词语、词频、空格分隔拼音。用于迁移旧词库。"
        case .doubao: return "读取已识别结构的 usr.dat，完整保留内部音节编号。未知音节边界不会自动猜测。"
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case archive, tsv, rime, baidu, sogou, qq, google, apple
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: return "macOS 系统自定义短语"
        case .archive: return "词渡完整档案"
        case .tsv: return "词渡交换表格"
        case .rime: return "Rime / 鼠须管"
        case .baidu: return "百度 Mac 文本"
        case .sogou: return "搜狗拼音 TXT"
        case .qq: return "QQ 拼音 TXT"
        case .google: return "谷歌拼音文本"
        }
    }
    var filename: String {
        switch self {
        case .apple: return "Text Substitutions.plist"
        case .archive: return "lexicon.json"
        case .tsv: return "lexicon.tsv"
        case .rime: return "cidu_personal.dict.yaml"
        case .baidu: return "baidu-personal.txt"
        case .sogou: return "sogou-personal.txt"
        case .qq: return "qq-personal.txt"
        case .google: return "google-personal.txt"
        }
    }
    var guidance: String {
        switch self {
        case .apple: return "把 .plist 拖入系统设置 → 键盘 → 文本替换列表。只接受保留了缩写的短语，不会把普通词库自动变为文本替换。导入前请从系统导出备份。"
        case .archive: return "完整保留词条和来源字段。可在另一台电脑用词渡重新打开。"
        case .tsv: return "可用表格软件查看，也可重新导入词渡。JSON 为完整保全档案。"
        case .rime: return "生成拼音词典，权重统一为 1。将词典加入自己的 Rime 配置并重新部署；不会自动修改现有方案。"
        case .baidu: return "生成与百度 Mac 导出文本对应的结构。原百度数值保留，其他来源使用 1；其他来源在百度中的实际导入尚待验证。"
        case .qq: return "生成 UTF-16 LE 拼音 TXT。同格式词频保留，其他来源使用 1；需在支持此文本格式的 QQ 拼音导入入口验证。未完成实机导入。"
        case .google: return "生成 GBK 三列文本。同格式词频保留，其他来源使用 1。用于谷歌拼音历史词库；未完成实机导入。"
        case .sogou: return "生成 GBK 拼音 TXT，不保留来源词频。仅适用于支持该文本格式的搜狗导入入口；未完成搜狗实机验证。"
        }
    }
}

struct ImportResult {
    let entries: [Entry]
    let format: InputFormat
    let warnings: [String]
}
struct ExportAssessment {
    let supported: Int
    let blocked: Int
    let reasons: [String]
    var canExport: Bool { supported > 0 && blocked == 0 }
}

enum Formats {
    static let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding("GBK" as CFString)))
    static func text(_ data: Data, allowGBK: Bool = false) throws -> String {
        let encoding: String.Encoding = data.starts(with: [255,254]) ? .utf16LittleEndian : data.starts(with: [254,255]) ? .utf16BigEndian : .utf8
        let value = String(data: data, encoding: encoding) ?? (allowGBK ? String(data: data, encoding: gbk) : nil)
        guard let value = value, !value.contains("\0") else { throw MigrationError("无法识别文本编码。请选择官方导出的文本或词渡档案。") }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
    }
    static func validate(_ entries: [Entry]) throws {
        guard !entries.isEmpty, entries.count <= 1_000_000 else { throw MigrationError("词库为空或超过 100 万条。") }
        func valid(_ s: String) -> Bool { !s.isEmpty && !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029 } }
        for (i, e) in entries.enumerated() {
            guard valid(e.word), valid(e.source), (e.codeKind == "shortcut" ? e.syllables.count == 1 : !e.syllables.isEmpty),
                  e.syllables.allSatisfy({ e.codeKind == "shortcut" ? ($0.isEmpty || valid($0)) : (valid($0) && !$0.contains(" ")) }),
                  e.codeKind == nil || ["syllables", "continuous", "native", "shortcut"].contains(e.codeKind!),
                  e.nativeSyllables == nil || (!e.nativeSyllables!.isEmpty && e.nativeSyllables!.allSatisfy { (0...65535).contains($0) }),
                  e.nativeAttributes == nil || (e.nativeAttributes!.count == 4 && e.nativeAttributes!.allSatisfy { (0...Int(UInt32.max)).contains($0) }),
                  e.sourceRawValue == nil || valid(e.sourceRawValue!) else {
                throw MigrationError("第 \(i + 1) 条记录包含空字段、控制字符或无效元数据；已停止整个读取。")
            }
        }
    }
    static func read(_ data: Data, as selected: InputFormat = .auto) throws -> ImportResult {
        guard data.count <= Lexicon.sizeLimit else { throw MigrationError("文件超过 64 MB。") }
        var format = selected
        if format == .auto {
            if data.starts(with: Data("mschxudp".utf8)) { format = .microsoft }
            else if data.starts(with: Data("bplist".utf8)) || (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [Any] { format = .apple }
            else if data.count >= 8, (try? Lexicon.u32(Array(data.prefix(8)), 0)) == 12001 { format = .doubao }
            else {
                let s = try text(data, allowGBK: true).trimmingCharacters(in: .whitespacesAndNewlines)
                if s.hasPrefix("{") {
                    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    format = object?["schema"] as? String == "cidu.wetype-snapshot.v1" ? .wetype : .archive
                }
                else if s.hasPrefix("word\tpinyin\tsource_value\tsource") { format = .tsv }
                else if s.contains("\n---") || s.hasPrefix("---") { format = .rime }
                else if s.components(separatedBy: .newlines).first.map({ $0.components(separatedBy: "\t").count == 3 }) == true { format = .google }
                else if let first = s.components(separatedBy: .newlines).first, first.split(whereSeparator: { $0 == " " || $0 == "\t" }).count == 3, first.contains("(") == false { format = .qq }
                else if s.hasPrefix("'") { format = .sogou }
                else { format = .baidu }
            }
        }
        let entries: [Entry]; var warnings = [String]()
        switch format {
        case .archive:
            let a: Archive
            do { a = try JSONDecoder().decode(Archive.self, from: data) }
            catch { throw MigrationError("档案字段不完整或不是词渡 JSON；请检查所选文件。") }
            guard a.schema == "cidu.archive.v1" else { throw MigrationError("此档案版本尚不支持，请升级词渡。") }
            entries = a.entries
        case .apple:
            entries = try MacFormats.apple(data)
            warnings.append("仅为自定义短语 / 文本替换，缩写不是拼音；不包含系统自动学习词库。")
        case .microsoft:
            entries = try MacFormats.microsoft(data)
            warnings.append("来自 Windows 微软拼音的自定义短语；候选位置保存在档案中，Mac 文本替换没有相同排序机制。")
        case .wetype: return try WeType.read(data)
        case .baidu: entries = try Lexicon.parseBaidu(data)
        case .tsv: entries = try parseTSV(data)
        case .rime:
            entries = try parseRime(data)
            warnings.append("只读取当前词典的显式词条，不包含 Rime 的动态学习记录或其他词典。")
        case .sogou:
            entries = try parseSogou(data)
            warnings.append("拼音 TXT 不含使用频率；使用占位值 1，不能推断原有排序。")
        case .qq, .google:
            entries = try parseRankedText(data, format: format)
            warnings.append("已读取文本词条；不包含动态学习历史。目标输入法实机导入尚未验证。")
        case .doubao:
            let report = try Lexicon.decodeDoubao(data)
            guard report.consistent else { throw MigrationError("豆包词库有损坏或重复偏移；请保留原件，不能部分读取。") }
            entries = report.entries
            warnings.append("已保留豆包内部音节编号；连续拼音无法保证音节边界，仅可完整转存 JSON / TSV。")
        case .auto: throw MigrationError("无法识别格式。")
        }
        try validate(entries)
        if entries.contains(where: { $0.source == "wetype-macos-experimental" }) { warnings.append("微信实验性档案仅含已识别短语，不代表完整学习词库。完整源快照请保留原迁移包。") }
        return ImportResult(entries: entries, format: format, warnings: warnings)
    }
    static func parseTSV(_ data: Data) throws -> [Entry] {
        let lines = try text(data).components(separatedBy: .newlines).filter { !$0.isEmpty }
        let old = "word\tpinyin\tsource_value\tsource"
        let new = old + "\tcode_kind\tnative_ids\tnative_attributes\tsource_raw_value"
        guard let first = lines.first, first == old || first == new else { throw MigrationError("TSV 列名不匹配。请使用词渡导出的交换表格。") }
        return try lines.dropFirst().enumerated().map { i, line in
            let c = line.components(separatedBy: "\t")
            guard c.count == (first == old ? 4 : 8), let n = Int64(c[2]) else { throw MigrationError("TSV 第 \(i+2) 行列数或数值无效。") }
            var e = Entry(word: c[0], syllables: c[1].components(separatedBy: " "), sourceValue: n, source: c[3])
            if c.count == 8 {
                e.codeKind = c[4].isEmpty ? nil : c[4]
                if e.codeKind == "shortcut" { e = Entry(word: c[0], syllables: [c[1]], sourceValue: n, source: c[3], codeKind: "shortcut") }
                func numbers(_ s: String) throws -> [Int]? {
                    if s.isEmpty { return nil }
                    let parts = s.components(separatedBy: ","); let values = parts.compactMap(Int.init)
                    guard parts.count == values.count else { throw MigrationError("TSV 第 \(i+2) 行内部编码无效。") }
                    return values
                }
                e.nativeSyllables = try numbers(c[5]); e.nativeAttributes = try numbers(c[6]); e.sourceRawValue = c[7].isEmpty ? nil : c[7]
            }
            return e
        }
    }
    static func parseSogou(_ data: Data) throws -> [Entry] {
        try text(data, allowGBK: true).components(separatedBy: .newlines).enumerated().compactMap { i, raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2, parts[0].first == "'" else { throw MigrationError("搜狗 TXT 第 \(i+1) 行不符合「'pin'yin 词语」。不支持二进制词库或自定义短语文件。") }
            let code = String(parts[0].dropFirst()).components(separatedBy: "'")
            guard code.allSatisfy({ $0.range(of: "^[a-zv]+$", options: .regularExpression) != nil }) else { throw MigrationError("搜狗 TXT 第 \(i+1) 行包含不支持的拼音。") }
            return Entry(word: String(parts[1]), syllables: code, sourceValue: 1, source: "sogou-pinyin-txt")
        }
    }
    static func parseRankedText(_ data: Data, format: InputFormat) throws -> [Entry] {
        try text(data, allowGBK: format == .google).components(separatedBy: .newlines).enumerated().compactMap { i, raw in
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            let fields = format == .google ? raw.components(separatedBy: "\t") : raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count == 3 else { throw MigrationError("第 \(i+1) 行必须恰好三列，不能忽略扩展字段。") }
            let word = fields[format == .google ? 0 : 1]
            let rank = fields[format == .google ? 1 : 2]
            var code = fields[format == .google ? 2 : 0]
            if format == .qq && code.hasPrefix("'") { code.removeFirst() }
            guard rank.range(of: "^[0-9]+$", options: .regularExpression) != nil, let value = Int64(rank), value <= Int64(Int32.max), !word.contains("," ) || format == .google else { throw MigrationError("第 \(i+1) 行词频或扩展字段不受支持。") }
            let entry = Entry(word: word, syllables: code.components(separatedBy: format == .google ? " " : "'"), sourceValue: value, source: format == .google ? "google-pinyin-txt" : "qq-pinyin-txt")
            guard Lexicon.rimeEligible(entry) else { throw MigrationError("第 \(i+1) 行需要明确分隔的小写拼音。") }
            return entry
        }
    }
    static func parseRime(_ data: Data) throws -> [Entry] {
        let lines = try text(data).components(separatedBy: .newlines)
        var inHeader = false, ended = false, columns = [String](), readingColumns = false, out = [Entry]()
        var name = false
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if !inHeader && !ended {
                guard line == "---" else { throw MigrationError("Rime 词典缺少 YAML 头部起始符。") }; inHeader = true; continue
            }
            if inHeader {
                if line == "..." { ended = true; inHeader = false; continue }
                if line.hasPrefix("import_tables:") && line != "import_tables: []" { throw MigrationError("这个 Rime 词典引用其他词典。请分别选择各个 .dict.yaml；本次不会漏掉引用后继续。") }
                if line.hasPrefix("name:") { name = true }
                if line.hasPrefix("columns:") {
                    guard columns.isEmpty else { throw MigrationError("Rime columns 重复定义。") }
                    let tail = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    if tail.isEmpty { readingColumns = true }
                    else {
                        guard tail.hasPrefix("["), tail.hasSuffix("]") else { throw MigrationError("暂不支持此 Rime columns 写法。") }
                        columns = tail.dropFirst().dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                    }
                    continue
                }
                if readingColumns {
                    if line.hasPrefix("- ") { columns.append(String(line.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))); continue }
                    readingColumns = false
                }
                continue
            }
            if columns.isEmpty { columns = ["text", "code", "weight"] }
            guard name, columns.count == Set(columns).count, columns.contains("text"), columns.contains("code"), Set(columns).isSubset(of: ["text", "code", "weight"]) else { throw MigrationError("Rime 需要唯一的 text / code 列，只支持可选 weight 列；不支持其他字段。") }
            let fields = raw.components(separatedBy: "\t")
            guard fields.count == columns.count || (fields.count == 2 && columns == ["text", "code", "weight"]) else { throw MigrationError("Rime 第 \(i+1) 行列数不匹配。") }
            var values = [String:String](); for (key,value) in zip(columns, fields) { values[key] = value }
            guard let w = values["text"], let code = values["code"], !code.isEmpty else { throw MigrationError("Rime 第 \(i+1) 行缺少词语或编码。") }
            let weight = values["weight"] ?? "1"
            guard weight.range(of: #"^\d+(\.\d+)?%?$"#, options: .regularExpression) != nil else { throw MigrationError("Rime 第 \(i+1) 行权重格式无效。") }
            let e = Entry(word: w, syllables: code.components(separatedBy: " "), sourceValue: Int64(weight) ?? 0, source: "rime-dict", sourceRawValue: weight)
            guard Lexicon.rimeEligible(e) else { throw MigrationError("Rime 第 \(i+1) 行不是支持的小写拼音编码；形码和双拼不能按拼音直接互转。") }
            out.append(e)
        }
        guard ended else { throw MigrationError("Rime 头部缺少结束符 ...。") }
        return out
    }
    static func reason(_ e: Entry, for format: OutputFormat) -> String? {
        if format == .archive || format == .tsv { return nil }
        if format == .apple { return e.codeKind == "shortcut" && e.syllables.count == 1 ? nil : "需要明确的短语缩写，不能把拼音学习词条当作文本替换" }
        if e.codeKind == "shortcut" { return "自定义短语缩写不是拼音" }
        if !e.hasBoundaries { return "缺少可靠的音节边界" }
        if format == .baidu {
            if e.word.contains("(") || e.word.contains(")") || e.syllables.contains(where: { $0.contains("|") || $0.contains("(") || $0.contains(")") }) { return "包含百度文本分隔符" }
        } else if !Lexicon.rimeEligible(e) { return "编码不是小写拼音" }
        if format == .qq {
            if e.word.contains(where: { $0.isWhitespace }) || e.word.contains(",") { return "QQ TXT 不支持词语中的空白或逗号" }
        }
        if (format == .qq && e.source == "qq-pinyin-txt") || (format == .google && e.source == "google-pinyin-txt") {
            if e.sourceValue < 0 || e.sourceValue > Int64(Int32.max) { return "来源词频超出目标范围" }
        }
        if format == .google && e.word.data(using: gbk, allowLossyConversion: false) == nil { return "词语无法无损编码为 GBK" }
        if format == .sogou {
            if e.word.contains(where: { $0.isWhitespace }) { return "搜狗 TXT 不支持词语中的空白" }
            if e.word.data(using: gbk, allowLossyConversion: false) == nil { return "词语无法无损编码为 GBK" }
        }
        return nil
    }
    static func assess(_ es: [Entry], for format: OutputFormat) -> ExportAssessment {
        var reasons = [String:Int](), blocked = 0
        for e in es { if let reason = reason(e, for: format) { blocked += 1; reasons[reason, default: 0] += 1 } }
        return ExportAssessment(supported: es.count - blocked, blocked: blocked, reasons: reasons.keys.sorted().map { "\($0)：\(reasons[$0]!) 条" })
    }
    static func write(_ es: [Entry], as format: OutputFormat) throws -> Data {
        try validate(es)
        let a = assess(es, for: format)
        guard a.canExport else { throw MigrationError("有 \(a.blocked) 条无法完整转换。请选择 JSON / TSV 保留全部记录。" + a.reasons.joined(separator: "；")) }
        switch format {
        case .apple: return try PropertyListSerialization.data(fromPropertyList: es.map { ["phrase": $0.word, "shortcut": $0.syllables[0]] }, format: .xml, options: 0)
        case .archive: return try Lexicon.archive(es)
        case .tsv:
            let header = "word\tpinyin\tsource_value\tsource\tcode_kind\tnative_ids\tnative_attributes\tsource_raw_value\n"
            return Data((header + es.map { e in [e.word, e.syllables.joined(separator: " "), String(e.sourceValue), e.source, e.codeKind ?? "", e.nativeSyllables?.map(String.init).joined(separator: ",") ?? "", e.nativeAttributes?.map(String.init).joined(separator: ",") ?? "", e.sourceRawValue ?? ""].joined(separator: "\t") }.joined(separator: "\n") + "\n").utf8)
        case .rime: return Data(try Lexicon.rime(es).utf8)
        case .baidu:
            let text = es.map { "\($0.word)(\($0.syllables.joined(separator: "|"))) \($0.source == "baidu-macos-export" ? $0.sourceValue : 1)" }.joined(separator: "\r\n") + "\r\n"
            var d = Data([255,254]); d.append(text.data(using: .utf16LittleEndian)!); return d
        case .qq, .google:
            let source = format == .qq ? "qq-pinyin-txt" : "google-pinyin-txt"
            let rows = es.map { e -> String in
                let rank = String(e.source == source ? e.sourceValue : 1)
                return format == .qq ? "\(e.syllables.joined(separator: "'")) \(e.word) \(rank)" : [e.word, rank, e.syllables.joined(separator: " ")].joined(separator: "\t")
            }.joined(separator: "\r\n") + "\r\n"
            if format == .qq { var d = Data([255,254]); d.append(rows.data(using: .utf16LittleEndian)!); return d }
            guard let d = rows.data(using: gbk, allowLossyConversion: false) else { throw MigrationError("无法无损转换为 GBK。") }; return d
        case .sogou:
            let s = es.map { "'\($0.syllables.joined(separator: "'")) \($0.word)" }.joined(separator: "\r\n") + "\r\n"
            guard let d = s.data(using: gbk, allowLossyConversion: false) else { throw MigrationError("无法无损转换为 GBK。") }; return d
        }
    }
}
