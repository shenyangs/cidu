import SwiftUI
import AppKit

struct PreviewRow: Identifiable {
    let id: Int
    let entry: Entry
    var sourceTitle: String {
        switch entry.source {
        case "macos-text-replacement": return "系统自定义短语"
        case "microsoft-udp": return "微软短语 · 迁入 Mac"
        case "wetype-macos-experimental": return "微信 Mac · 实验"
        case "baidu-macos-export": return "百度 Mac"
        case "qq-pinyin-txt": return "QQ 拼音"
        case "google-pinyin-txt": return "谷歌拼音"
        case "sogou-pinyin-txt": return "搜狗 TXT"
        case "rime-dict": return "Rime 词典"
        case "doubao-macos": return "豆包 Mac"
        default: return entry.source
        }
    }
}
enum Page: String, CaseIterable, Identifiable {
    case convert = "转换词库", compatibility = "豆包兼容性", guide = "使用与支持"
    var id: String { rawValue }
    var symbol: String { switch self { case .convert: return "arrow.triangle.2.circlepath"; case .compatibility: return "checkmark.shield"; case .guide: return "book" } }
}

@MainActor final class Model: ObservableObject {
    @Published var page = Page.convert
    @Published var inputFormat = InputFormat.auto
    @Published var outputFormat = OutputFormat.archive { didSet { assess() } }
    @Published var imported: ImportResult?
    @Published var sourceName = ""
    @Published var sourceData = Data()
    @Published var busy = false
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var assessment = ExportAssessment(supported: 0, blocked: 0, reasons: [])
    @Published var search = "" { didSet { filter() } }
    @Published var preview = [PreviewRow]()
    @Published var matchCount = 0
    @Published var uniqueWords = 0
    @Published var distinctCodes = 0
    @Published var compatibility: CompatibilityReport?
    @Published var lastOutput: URL?
    @Published var showWords = false
    private var rows = [PreviewRow]()
    private var searchGeneration = 0
    var entries: [Entry] { imported?.entries ?? [] }
    func assess() { assessment = Formats.assess(entries, for: outputFormat) }
    func filter() {
        searchGeneration += 1; let generation = searchGeneration
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); let all = rows
        DispatchQueue.global(qos: .userInitiated).async {
            let matches = query.isEmpty ? all : all.filter { $0.entry.word.localizedCaseInsensitiveContains(query) || $0.entry.syllables.joined().lowercased().contains(query) }
            let page = Array(matches.prefix(200))
            DispatchQueue.main.async { guard self.searchGeneration == generation else { return }; self.preview = page; self.matchCount = matches.count }
        }
    }
    func chooseSource() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "选择词库文件、词渡迁移包，或已停止使用的微信 Mac 数据库副本文件夹。"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
    func load(_ url: URL) {
        guard !busy else { return }
        busy = true; errorMessage = nil; status = "正在读取并检查完整性…"
        let selected = inputFormat
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> (ImportResult, Data) in
                let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if directory {
                    if FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) { let r = try Packages.verify(url); return (r, try Lexicon.boundedRead(url.appendingPathComponent("source.original"))) }
                    guard selected == .auto || selected == .wetype else { throw MigrationError("此格式需要文件；微信词库需选择微信 Mac 或自动识别。") }
                    let snapshot = try WeType.capture(url); return (try WeType.read(snapshot), snapshot)
                }
                let data = try Lexicon.boundedRead(url); return (try Formats.read(data, as: selected), data)
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let (r, data)):
                    self.imported = r; self.sourceData = data; self.sourceName = url.lastPathComponent
                    self.rows = r.entries.enumerated().map { PreviewRow(id: $0.offset, entry: $0.element) }
                    self.uniqueWords = Set(r.entries.map(\.word)).count; self.distinctCodes = Set(r.entries.map(\.exactKey)).count
                    self.lastOutput = nil; self.showWords = false; self.search = ""; self.assess(); self.filter()
                    self.status = r.entries.contains(where: { $0.source == "wetype-macos-experimental" }) ? "实验性读取：识别 \(r.entries.count.formatted()) 条微信短语；不代表完整学习词库。" : "完整读取 \(r.entries.count.formatted()) 条记录。原文件保持不变。"
                case .failure(let e): self.errorMessage = e.localizedDescription; self.status = self.imported == nil ? "读取未完成" : "新文件读取失败，仍显示上一次成功读取的词库。"
                }
            }
        }
    }
    func sample() {
        inputFormat = .auto
        let data = Data("示例(shi|li) 100\n重庆(chong|qing) 200\n重庆(zhong|qing) 2\n词渡(ci|du) 1\n示例(shi|li) 3\n".utf8)
        do {
            let r = try Formats.read(data)
            imported = r; sourceData = data; sourceName = "人工示例词库"
            rows = r.entries.enumerated().map { PreviewRow(id: $0.offset, entry: $0.element) }
            uniqueWords = Set(r.entries.map(\.word)).count; distinctCodes = Set(r.entries.map(\.exactKey)).count
            showWords = true; search = ""; lastOutput = nil; errorMessage = nil; assess(); filter(); status = "正在查看 5 条人工示例，可以体验转换和迁移包。"
        } catch { errorMessage = error.localizedDescription }
    }
    func scan() {
        guard !busy else { return }; busy = true; errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let report = Compatibility.inspect()
            DispatchQueue.main.async { self.compatibility = report; self.busy = false }
        }
    }
    func saveReport() {
        guard let report = compatibility else { return }
        let p = NSSavePanel(); p.nameFieldStringValue = "cidu-compatibility-\(Int(Date().timeIntervalSince1970)).json"
        p.message = "仅包含版本、系统、引擎指纹和计数，不包含账号路径或词语。"
        if p.runModal() == .OK, let u = p.url {
            do { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; try Lexicon.saveNew(e.encode(report), at: u); lastOutput = u; status = "兼容性报告已保存。" } catch { errorMessage = error.localizedDescription }
        }
    }
    func export(package: Bool) {
        guard let r = imported, assessment.canExport, !busy else { return }
        let destination: URL
        if package {
            let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
            p.prompt = "保存到这里"; p.message = "选择迁移包的存放位置。包内包含个人词语、原件和完整档案。"
            guard p.runModal() == .OK, let u = p.url else { return }; destination = u
        } else {
            let p = NSSavePanel(); p.nameFieldStringValue = outputFormat.filename
            p.message = "只导出目标文件；建议用迁移包同时保存原件和完整档案。"
            guard p.runModal() == .OK, let u = p.url else { return }; destination = u
        }
        busy = true; errorMessage = nil; status = package ? "正在生成并校验迁移包…" : "正在导出…"
        let source = sourceData; let format = outputFormat
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> URL in
                if package { return try Packages.create(in: destination, source: source, imported: r, format: format) }
                try Lexicon.saveNew(Formats.write(r.entries, as: format), at: destination); return destination
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let url): self.lastOutput = url; self.status = "转换完成 · \(r.entries.count.formatted()) 条记录。下一步按使用说明在目标输入法中导入。"
                case .failure(let e): self.errorMessage = e.localizedDescription; self.status = "导出未完成，原词库未修改。"
                }
            }
        }
    }
}

struct AdvancedView: View {
    @StateObject private var model = Model()
    private let accent = Color(red: 0.30, green: 0.39, blue: 0.32)
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("词渡").font(.system(size: 28, weight: .semibold, design: .serif))
                    Text("把你的词，带到下一站。").font(.callout).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.top, 20)
                List(selection: $model.page) {
                    ForEach(Page.allCases) { p in Label(p.rawValue, systemImage: p.symbol).tag(p) }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 7) {
                    Label("全程在本机处理", systemImage: "lock").font(.callout)
                    Text("无账号 · 无自动上传").font(.caption).foregroundStyle(.secondary)
                    Text("0.5 · 文件工具").font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 205, ideal: 215, max: 245)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch model.page { case .convert: conversion; case .compatibility: compatibility; case .guide: guide }
                    }.padding(28).frame(maxWidth: 1080, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
                }
                if !model.status.isEmpty || model.busy {
                    Divider()
                    HStack(spacing: 10) {
                        if model.busy { ProgressView().controlSize(.small) }
                        Text(model.status).font(.callout).textSelection(.enabled)
                        Spacer()
                        if let url = model.lastOutput { Button("在访达中查看") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                    }.padding(14)
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent).frame(minWidth: 940, minHeight: 700)
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onAppear {
            if let i = CommandLine.arguments.firstIndex(of: "--source"), CommandLine.arguments.count > i+1 { model.load(URL(fileURLWithPath: CommandLine.arguments[i+1])) }
        }
        .onOpenURL { model.load($0) }
    }
    func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 26, weight: .semibold)); Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
    var conversion: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("转换词库", "选择来源，检查词条，再生成可以带走的迁移包。")
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        Picker("来源格式", selection: $model.inputFormat) { ForEach(InputFormat.allCases) { f in Text(f.title).tag(f) } }.frame(maxWidth: 370)
                        Spacer()
                        Button(model.imported == nil ? "选择词库或迁移包…" : "更换文件…", action: model.chooseSource).keyboardShortcut("o").disabled(model.busy)
                    }
                    Text(model.inputFormat.help).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let imported = model.imported {
                        Divider()
                        HStack { Label(model.sourceName, systemImage: "doc.text").lineLimit(1).truncationMode(.middle).help(model.sourceName); Spacer(); Text(imported.format.title).font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing: 25) {
                            summary("记录", model.entries.count)
                            summary("不同词语", model.uniqueWords)
                            summary("词语与编码组合", model.distinctCodes)
                        }
                        Text("重复记录保留，多音字分开计算。记录数不等于你亲自输入过的词语数。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Divider()
                        HStack { Text("先体验流程，再导入自己的词库。").foregroundStyle(.secondary); Spacer(); Button("使用人工示例", action: model.sample).disabled(model.busy) }
                    }
                }.padding(10)
            }
            if let imported = model.imported {
                ForEach(imported.warnings, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("词条预览").font(.headline)
                        Spacer()
                        Toggle("显示词语", isOn: $model.showWords).toggleStyle(.checkbox).help("个人词语默认隐藏；开启后请留意截图内容。")
                    }
                    if model.showWords {
                        TextField("搜索词语或连续拼音", text: $model.search).textFieldStyle(.roundedBorder).accessibilityLabel("搜索词条")
                        Table(model.preview) {
                            TableColumn("词语") { Text($0.entry.word) }
                            TableColumn("编码") { Text($0.entry.syllables.joined(separator: " ")).foregroundStyle(.secondary) }
                            TableColumn("来源") { Text($0.sourceTitle).font(.caption).foregroundStyle(.secondary) }.width(min: 100, ideal: 160, max: 200)
                        }.frame(height: 210)
                        Text("匹配 \(model.matchCount.formatted()) 条 · 预览前 200 条；导出包含全部记录。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("词语已隐藏。开启“显示词语”后可以搜索核对，隐藏不会影响导出。").font(.callout).foregroundStyle(.secondary).padding(.vertical, 10)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text("带到哪里").font(.headline)
                    Picker("输出格式", selection: $model.outputFormat) { ForEach(OutputFormat.allCases) { f in Text(f.title).tag(f) } }.frame(maxWidth: 400).disabled(model.busy)
                    Text(model.outputFormat.guidance).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.assessment.blocked > 0 {
                        Label("\(model.assessment.blocked.formatted()) 条不能完整转换", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        ForEach(model.assessment.reasons, id: \.self) { Text($0).font(.callout) }
                        Button("改用完整档案，保留全部词条") { model.outputFormat = .archive }
                    } else { Label("全部 \(model.entries.count.formatted()) 条可写入目标文件", systemImage: "checkmark.circle").foregroundStyle(accent) }
                    HStack {
                        Button("生成迁移包…") { model.export(package: true) }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                        Button("只导出目标文件…") { model.export(package: false) }
                    }.disabled(model.busy || !model.assessment.canExport)
                    Text("迁移包包含原件、完整档案、目标文件和使用说明。转换完成后仍需在目标输入法中导入。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    func summary(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 6) { Text(value.formatted()).fontWeight(.semibold).monospacedDigit(); Text(label).foregroundStyle(.secondary) }.font(.callout)
    }
    var compatibility: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("豆包兼容性", "一次成功，记录为一个已验证环境。每台电脑都需要自己的检查。")
            HStack { Button("检查这台 Mac", action: model.scan).buttonStyle(.borderedProminent).disabled(model.busy); if model.compatibility != nil { Button("导出不含词语的报告…", action: model.saveReport).disabled(model.busy) } }
            if let r = model.compatibility {
                Text(r.status).font(.title3).fontWeight(.semibold)
                Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                    GridRow { Text("豆包版本").foregroundStyle(.secondary); Text("\(r.version) · build \(r.build)") }
                    GridRow { Text("运行环境").foregroundStyle(.secondary); Text("macOS \(r.system) · \(r.architecture)") }
                    GridRow { Text("引擎指纹").foregroundStyle(.secondary); Text(r.sameEngine ? "与已验证引擎一致" : "未匹配 / 无法读取") }
                    GridRow { Text("词库结构").foregroundStyle(.secondary); Text(r.structuralCheck) }
                }.font(.callout).textSelection(.enabled)
                Divider()
                Text(r.nextStep).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else { Text("检查会读取应用版本、引擎指纹和本地词库结构。不会退出输入法或改写词库。").foregroundStyle(.secondary) }
            GroupBox("已验证范围") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("豆包 1.0.2 · Apple Silicon · macOS 27.0.1")
                    Text("已在一台 Mac 完成真实合并、扩容、原生引擎候选检查和重启后保留。用户已反馈能正常使用。")
                    Text("不同账号、Intel、新版引擎及跨设备云同步仍待验证。即使版本号相同，也不能跳过本机副本测试。")
                }.font(.callout).foregroundStyle(.secondary).padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    var guide: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("使用与支持", "先保留原件，再转换；实际输入验证后，才算迁移完成。")
            guideItem("换一台电脑", "生成迁移包，用你选择的方式传到另一台电脑，再在词渡中选择整个文件夹。词渡会校验文件并读取完整档案。无需登录，也没有自动云同步。")
            guideItem("验证迁移是否有效", "在目标输入法导入后，用完整拼音抽查个人特色词语、原有词语和多音字。查看候选并翻页，再重启输入法复查。候选顺序不保证与原输入法相同。")
            guideItem("保留与恢复", "迁移包中的 source.original 是源文件原件，archive.json 是完整中立档案。文件工具只生成文件；主界面的自动安装另有独立备份与恢复记录。")
            guideItem("目前支持的格式", "百度 Mac 导出文本、搜狗 / QQ 拼音 TXT、谷歌拼音文本、Rime 拼音 .dict.yaml、词渡 JSON / TSV 可以读写。豆包 usr.dat 可以读取并转存 JSON / TSV。系统自定义短语 PLIST 可读写，微软短语可迁入 Mac；微信 Mac 完整数据库副本提供实验性读取。支持的格式不代表所有输入法版本都经过实机验证。")
            guideItem("尚未支持", "搜狗 .scel / .bin、QQ .qpyd / .qcel、微软 DCTX 学习词库、微信写回与未知数据库记录、macOS 自动学习词库；Rime userdb 和形码；跨平台自动安装。这些格式不会被伪装成通用文本后继续转换。")
            guideItem("为什么有些词不能转换", "输入法的编码方式、字符集和词频含义不同。遇到不兼容条目，词渡会停止该目标的导出，并允许改用完整档案保留所有词条。")
            Text("词库在本机处理，源代码采用 MIT 协议。发行包的签名、公证与实机验证范围见项目验证记录。").font(.caption).foregroundStyle(.secondary)
        }
    }
    func guideItem(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
}

