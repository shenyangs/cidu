import Foundation
import CryptoKit

struct CompatibilityReport: Codable {
    let version: String
    let build: String
    let architecture: String
    let system: String
    let engineHash: String?
    let sameEngine: Bool
    let targetFiles: Int
    let structuralCheck: String
    let status: String
    let nextStep: String
    let liveWriteAvailable: Bool
}

enum Compatibility {
    static let validatedEngine = "d1cebd7c9a9d888acc2a6d2f4aad372cb3b31570ff68a7e631cba930517f5db8"
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func inspect(app: URL = URL(fileURLWithPath: "/Library/Input Methods/DoubaoIme.app"), targets: [URL]? = nil) -> CompatibilityReport {
        let info = (try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String:Any] }
        let version = info?["CFBundleShortVersionString"] as? String ?? "未安装 / 未识别"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let system = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let engine = app.appendingPathComponent("Contents/Frameworks/OimeEngine.framework/Versions/A/OimeEngine")
        let digest = (try? Data(contentsOf: engine, options: .mappedIfSafe)).map(hash)
        let paths = targets ?? Lexicon.discoverDoubao()
        var structurallyValid = false
        let structure: String
        if paths.count == 1 {
            do {
                let report = try Lexicon.decodeDoubao(Lexicon.boundedRead(paths[0]))
                structurallyValid = report.consistent
                structure = report.consistent ? "通过 · \(report.decoded.formatted()) 条记录" : "未通过 · 记录损坏或计数不一致"
            } catch { structure = "未通过 · 文件结构尚不支持" }
        } else { structure = paths.isEmpty ? "未找到主词库" : "有 \(paths.count) 个文件，需要确认正在使用的账号" }
        let same = version == "1.0.2" && digest == validatedEngine
        let knownEnvironment = same && arch == "arm64" && system == "27.0.1"
        let status: String
        if !structurallyValid { status = "需要先解决词库检查" }
        else if knownEnvironment { status = "与已验证环境条件匹配" }
        else if same { status = "引擎相同，电脑环境待验证" }
        else { status = "尚未验证的豆包版本或引擎" }
        return CompatibilityReport(version: version, build: build, architecture: arch, system: system, engineHash: digest, sameEngine: same, targetFiles: paths.count, structuralCheck: structure, status: status,
            nextStep: "条件匹配不等于迁移成功。仍需在副本中检查加载、保存、候选、目标账号及恢复；跨设备与长期云同步尚未验证。自动安装入口受版本与账号检查限制，本报告本身不执行写入。", liveWriteAvailable: false)
    }
}

struct PackageManifest: Codable {
    let schema: String
    let createdAt: String
    let sourceFormat: String
    let outputFormat: String
    let recordCount: Int
    let uniqueWordCount: Int
    let distinctCodeCount: Int
    let sourceHash: String
    let files: [String:String]
    let state: String
}

/// A self-contained, private conversion package. No source or IME files are modified.
enum Packages {
    static func create(in parent: URL, source: Data, imported: ImportResult, format: OutputFormat) throws -> URL {
        let fm = FileManager.default
        let folder = parent.appendingPathComponent("词渡迁移包-" + UUID().uuidString.prefix(8))
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let output = try Formats.write(imported.entries, as: format)
            let archive = try Lexicon.archive(imported.entries)
            let files = ["source.original": source, "archive.json": archive, format.filename: output]
            var hashes = [String:String]()
            for (name, data) in files {
                try Lexicon.saveNew(data, at: folder.appendingPathComponent(name)); hashes[name] = Compatibility.hash(data)
            }
            let es = imported.entries
            let manifest = PackageManifest(schema: "cidu.package.v1", createdAt: ISO8601DateFormatter().string(from: Date()), sourceFormat: imported.format.rawValue, outputFormat: format.rawValue, recordCount: es.count, uniqueWordCount: Set(es.map(\.word)).count, distinctCodeCount: Set(es.map(\.exactKey)).count, sourceHash: Compatibility.hash(source), files: hashes, state: "converted-not-installed")
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try Lexicon.saveNew(enc.encode(manifest), at: folder.appendingPathComponent("manifest.json"))
            let instructions = """
            词渡迁移包

            状态：转换完成，尚未安装到目标输入法。
            微信实验性读取只转换已识别短语键，其余记录保留在源快照中。
            读取 \(es.count) 条记录，\(manifest.uniqueWordCount) 个不同词语。重复记录全部保留。
            来源：\(imported.format.title)
            目标：\(format.title)

            使用：\(format.guidance)

            archive.json 是完整中立档案。source.original 是逐字节保留的源文件；微信数据库来源则是保留各文件原始字节的 JSON 快照（Data 为 Base64）。
            在另一台电脑安装词渡后，选择整个迁移包可验证文件完整性并重新读取档案。
            需要恢复源文件时，可复制 source.original 并改回源文件名；目标输入法的恢复需通过其自己的导入/恢复流程。
            迁移包没有修改输入法，不能用于一键撤销另一次对输入法的写入。

            文件含个人词语，请自行选择传输方式。词渡不会自动上传或同步。
            原始数值不等于跨输入法通用词频。\(imported.warnings.joined(separator: "\n"))
            """
            try Lexicon.saveNew(Data(instructions.utf8), at: folder.appendingPathComponent("使用说明.txt"))
            _ = try verify(folder)
            return folder
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }
    static func verify(_ folder: URL) throws -> ImportResult {
        let manifest: PackageManifest
        do { manifest = try JSONDecoder().decode(PackageManifest.self, from: Lexicon.boundedRead(folder.appendingPathComponent("manifest.json"))) }
        catch { throw MigrationError("这个文件夹不是有效迁移包，或清单已损坏。") }
        let allowed = Set(["source.original", "archive.json"] + OutputFormat.allCases.map(\.filename))
        guard manifest.schema == "cidu.package.v1", manifest.state == "converted-not-installed",
              manifest.files["archive.json"] != nil, manifest.files["source.original"] == manifest.sourceHash,
              let sourceFormat = InputFormat(rawValue: manifest.sourceFormat), sourceFormat != .auto,
              let output = OutputFormat(rawValue: manifest.outputFormat), manifest.files[output.filename] != nil,
              manifest.files.count <= 3, Set(manifest.files.keys).isSubset(of: allowed) else { throw MigrationError("迁移包版本或文件清单不受支持。") }
        for (name, digest) in manifest.files {
            let url = folder.appendingPathComponent(name)
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true,
                  Compatibility.hash(try Lexicon.boundedRead(url)) == digest else { throw MigrationError("迁移包完整性检查失败：\(name)。请重新复制原迁移包。") }
        }
        let result = try Formats.read(Lexicon.boundedRead(folder.appendingPathComponent("archive.json")), as: .archive)
        guard result.entries.count == manifest.recordCount, Set(result.entries.map(\.word)).count == manifest.uniqueWordCount, Set(result.entries.map(\.exactKey)).count == manifest.distinctCodeCount else { throw MigrationError("迁移包记录数与清单不一致。") }
        return ImportResult(entries: result.entries, format: sourceFormat, warnings: result.warnings)
    }
}
