import AppKit
import SwiftUI

struct MigrationTick { let phase: Int; let fraction: Double; let count: Int; let total: Int; let word: String; var message: String }

final class MigrationCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func set(_ value: Bool) { lock.lock(); defer { lock.unlock() }; self.value = value }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

enum MigrationWorker {
    static func helper(_ args: [String]) throws {
        let sibling = URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("EngineProbe")
        guard let url = Bundle.main.url(forAuxiliaryExecutable:"EngineProbe") ?? (FileManager.default.isExecutableFile(atPath:sibling.path) ? sibling : nil) else { throw MigrationError("缺少引擎验证组件，请重新下载完整应用。") }
        let process = Process(); process.executableURL = url; process.arguments = args
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(45)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval:0.05) }
        if process.isRunning { process.terminate(); Thread.sleep(forTimeInterval:0.2); if process.isRunning { kill(process.processIdentifier,SIGKILL) }; process.waitUntilExit(); throw MigrationError("目标引擎验证超时，未安装词库。") }
        guard process.terminationStatus == 0 else { throw MigrationError("目标引擎未通过副本验证，未安装词库。") }
    }
    static func verifyActiveTarget(_ target: URL) throws {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.lastPathComponent == "DoubaoIme.app" }
        guard !apps.isEmpty else { return }
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath:"/usr/sbin/lsof")
        p.arguments = ["-a","-p",apps.map { String($0.processIdentifier) }.joined(separator:","),"-Fn"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let prefix = "n" + target.deletingLastPathComponent().path + "/"
        guard String(decoding:data,as:UTF8.self).split(separator:"\n").contains(where: { $0.hasPrefix(prefix) }) else {
            throw MigrationError("无法核对豆包正在使用的账号目录，已停止。请切换到豆包使用一次后重试。")
        }
    }
    static func stopDoubao() throws -> [URL] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.lastPathComponent == "DoubaoIme.app" }
        let urls = Array(Set(apps.compactMap(\.bundleURL)))
        for app in apps { _ = app.terminate() }
        let deadline = Date().addingTimeInterval(8)
        while apps.contains(where: { !$0.isTerminated }) && Date() < deadline { Thread.sleep(forTimeInterval:0.1) }
        guard apps.allSatisfy(\.isTerminated) else { restart(urls); throw MigrationError("豆包尚未退出，未改写词库。请切换到系统输入法并退出豆包后重试。") }
        return urls
    }
    static func restart(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let group = DispatchGroup()
        for url in urls {
            group.enter()
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration()) { _,_ in group.leave() }
            }
        }
        // All callers run off the main thread; CLI keeps its main run loop alive.
        _ = group.wait(timeout:.now()+10)
    }
    static func run(file: URL?, prepareOnly: Bool = false, cancelled: () -> Bool, tick: (MigrationTick) -> Void) throws -> (MigrationReceipt?,Int) {
        let lock = try MigrationLock(); defer { lock.release() }
        func check() throws { if cancelled() { throw MigrationError("迁移已取消，输入法词库未修改。") } }
        tick(.init(phase:0,fraction:0,count:0,total:0,word:"",message:"正在检查这台 Mac…"))
        let targets = Lexicon.discoverDoubao(), report = Compatibility.inspect()
        guard targets.count == 1, report.sameEngine else { throw MigrationError("当前豆包版本、引擎或账号无法唯一确认，自动安装暂不可用。可在文件工具中保留完整档案。") }
        let target = targets[0]
        try verifyActiveTarget(target)
        let session = MigrationStore.root.appendingPathComponent("work-"+UUID().uuidString)
        try MigrationStore.privateFolder(session)
        defer { try? FileManager.default.removeItem(at:session) }
        let source: Data
        if let file { source = try Lexicon.boundedRead(file) }
        else { source = try BaiduAutomation.export(to:session.appendingPathComponent("source.txt"),cancelled:cancelled,progress: { message in
            tick(.init(phase:0,fraction:0,count:0,total:0,word:"",message:message))
        }) }
        let entries = try Formats.read(source).entries
        try check()
        tick(.init(phase:0,fraction:1,count:entries.count,total:entries.count,word:"",message:"已读取 \(entries.count.formatted()) 条词条"))
        let original = try Lexicon.boundedRead(target)
        let symbols = Array(Set(entries.filter(\.hasBoundaries).flatMap(\.syllables).map { $0.lowercased() }.filter { !$0.isEmpty && $0.utf8.count <= 65535 })).sorted()
        let keys = session.appendingPathComponent("symbols.json"), mapped = session.appendingPathComponent("mapping.json")
        try Lexicon.saveNew(JSONEncoder().encode(symbols),at:keys)
        try helper(["map",keys.path,mapped.path])
        let raw = try JSONSerialization.jsonObject(with:Data(contentsOf:mapped)) as? [String:[NSNumber]] ?? [:]
        let mapping = raw.reduce(into:[String:Int]()) { result, item in if item.value.count == 2 && item.value[0].boolValue { result[item.key] = item.value[1].intValue } }
        let selection = DoubaoMerge.select(entries,mapping:mapping)
        tick(.init(phase:1,fraction:0,count:0,total:entries.count,word:"",message:"合并词条，保留目标原有记录…"))
        let merged = try DoubaoMerge.build(original,entries:selection.accepted,mapping:mapping) { n,e in
            try check(); tick(.init(phase:1,fraction:Double(n)/Double(max(1,selection.accepted.count)),count:n,total:entries.count,word:e.word,message:"正在核对词条"))
        }
        if merged.added == 0 && selection.rejected.isEmpty && !prepareOnly { return (nil,entries.count) }
        try check()
        if merged.added > 0 {
        tick(.init(phase:2,fraction:0,count:entries.count,total:entries.count,word:"",message:"正在用豆包原生引擎验证副本…"))
        let isolated = session.appendingPathComponent("engine"); try MigrationStore.privateFolder(isolated)
        try Lexicon.saveNew(merged.data,at:isolated.appendingPathComponent("usr.dat"))
        let baseline = session.appendingPathComponent("baseline"); try MigrationStore.privateFolder(baseline)
        try Lexicon.saveNew(original,at:baseline.appendingPathComponent("usr.dat"))
        let beforeCount = session.appendingPathComponent("before-count"), afterCount = session.appendingPathComponent("after-count")
        try helper(["cpp",baseline.path,beforeCount.path])
        try helper(["cpp",isolated.path,afterCount.path])
        guard let before = Int(try String(contentsOf:beforeCount,encoding:.utf8)),
              let after = Int(try String(contentsOf:afterCount,encoding:.utf8)), after-before == merged.added,
              try Data(contentsOf:URL(fileURLWithPath:beforeCount.path+".errors")) == Data(contentsOf:URL(fileURLWithPath:afterCount.path+".errors")) else {
            throw MigrationError("原生引擎未确认全部新增词条，未安装词库。")
        }
        }
        try check()
        let archive = MigrationSource(data:source,entries:entries,rejected:selection.rejected,existing:merged.existing)
        let receipt = try MigrationStore.prepare(target:target,before:original,after:merged.data,added:merged.added,source:archive)
        // Unsupported records never turn an ordinary start into an implicit partial write.
        if prepareOnly || !selection.rejected.isEmpty { return (receipt,merged.existing) }
        tick(.init(phase:3,fraction:0,count:entries.count,total:entries.count,word:"",message:"备份已保存，正在安装…"))
        try check()
        let installed = try installPrepared(receipt)

        tick(.init(phase:3,fraction:1,count:entries.count,total:entries.count,word:"",message:"安装与回读校验完成"))
        return (installed,merged.existing)
    }
    static func validateTarget(_ receipt: MigrationReceipt) throws {
        let targets = Lexicon.discoverDoubao()
        guard targets.count == 1, targets[0].path == receipt.target, Compatibility.inspect().sameEngine else {
            throw MigrationError("目标账号或引擎发生变化，请重新生成计划。")
        }
        try verifyActiveTarget(targets[0])
    }
    // Caller holds MigrationLock; GUI and CLI share this exact commit path.
    static func installPrepared(_ receipt: MigrationReceipt, allowPartial: Bool = false) throws -> MigrationReceipt {
        try validateTarget(receipt)
        _ = try MigrationStore.checkedPlan(receipt,allowPartial:allowPartial)
        if receipt.added == 0 { return try MigrationStore.commitPlan(receipt,allowPartial:allowPartial) }
        let urls = try stopDoubao(); defer { restart(urls) }
        return try MigrationStore.commitPlan(receipt,allowPartial:allowPartial)
    }

    static func apply(id: String, allowPartial: Bool = false) throws -> MigrationReceipt {
        let lock = try MigrationLock(); defer { lock.release() }
        return try installPrepared(MigrationStore.load(id:id),allowPartial:allowPartial)
    }
    static func restoreChecked(_ receipt: MigrationReceipt) throws -> MigrationReceipt {
        let lock = try MigrationLock(); defer { lock.release() }
        let current = try MigrationStore.load(id:receipt.id)
        guard current.state == "installed" else { throw MigrationError("只有已安装记录可以恢复。") }
        try validateTarget(current)
        let urls = try stopDoubao(); defer { restart(urls) }
        return try MigrationStore.restore(current)
    }

}

@MainActor final class MigrationModel: ObservableObject {
    @Published var source = "百度输入法"
    @Published var target = "豆包输入法"
    @Published var busy = false
    @Published var tick = MigrationTick(phase:0,fraction:0,count:0,total:0,word:"",message:"选择来源和去向，其余交给词渡。")
    @Published var words: [String] = []
    @Published var error: String?
    @Published var notice: String?
    @Published var complete = false
    @Published var receipt: MigrationReceipt?
    @Published var review: MigrationReceipt?
    @Published var receipts = MigrationStore.receipts()
    @Published var file: URL?
    @Published var showWords = false
    @Published var showHistory = false
    @Published var showAdvanced = false
    @Published var showPermissionGuide = false
    private let cancellation = MigrationCancellation()
    @Published var preflight: PreflightReport?
    @Published var checking = false
    private var checkGeneration = 0
    private var pendingStart: (source:String,target:String,file:URL?)?
    var waitingForPermission: Bool { pendingStart != nil }
    var canRun: Bool { !busy && !checking && preflight?.canBegin == true }
    func permissionGuideDismissed() { pendingStart = nil }
    func refresh() {
        guard !busy else { return }
        checkGeneration += 1
        let generation = checkGeneration, source = source, target = target, file = file
        checking = true; preflight = nil
        DispatchQueue.global(qos:.userInitiated).async {
            let report = Preflight.inspect(source:source,target:target,file:file)
            DispatchQueue.main.async {
                guard generation == self.checkGeneration else { return }
                self.preflight = report; self.checking = false
                if let pending = self.pendingStart, report.ready,
                   pending.source == self.source, pending.target == self.target, pending.file == self.file {
                    self.pendingStart = nil; self.showPermissionGuide = false
                    DispatchQueue.main.async { self.start() }
                }
            }
        }
    }
    func pollPermission() {
        guard !busy, !checking, source == "百度输入法", file == nil,
              let previous = preflight?.checks.first(where: { $0.id == "permission" }) else { return }
        if previous.passed != AccessibilityAccess.allowed { refresh() }
    }
    func remedy(_ action: PreflightAction) {
        switch action {
        case .file: chooseFile()
        case .advanced: showAdvanced = true
        case .accessibility: showPermissionGuide = true
        case .inputSettings: NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
        case .sourceApp:
            if let url = Preflight.installation("百度输入法").0 { NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration()) }
        }
    }
    func chooseFile() {
        let p = NSOpenPanel(); p.message = "可选：使用已经导出的词库文件"; p.canChooseDirectories = false
        if p.runModal() == .OK { file = p.url }
    }
    func cancel() { cancellation.set(true) }
    func resetResult() {
        complete = false; receipt = nil; review = nil; error = nil; notice = nil
        words = []; showWords = false; pendingStart = nil
        refresh()
    }
    func revealArchive(_ receipt: MigrationReceipt) {
        guard let dir = try? MigrationStore.directory(id:receipt.id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir.appendingPathComponent(receipt.skipped > 0 ? "unmigrated.json" : "source.json")])
    }
    func start() {
        guard canRun else { return }
        if preflight?.needsPermission == true {
            pendingStart = (source,target,file); showPermissionGuide = true; return
        }
        pendingStart = nil; busy = true; complete = false; error = nil; notice = nil; words = []; showWords = false; receipt = nil; review = nil
        cancellation.set(false)
        let file = self.file, cancellation = self.cancellation, source = self.source, target = self.target
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result {
                let report = Preflight.inspect(source:source,target:target,file:file)
                guard report.ready else { throw MigrationError(report.checks.filter { !$0.passed }.map(\.detail).joined(separator:"\n")) }
                return try MigrationWorker.run(file:file,cancelled:{ cancellation.get() },tick:{ event in
                DispatchQueue.main.async { self.tick = event; if !event.word.isEmpty { self.words.insert(event.word,at:0); self.words = Array(self.words.prefix(8)) } }
            }) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let (receipt,existing)):
                    self.receipts = MigrationStore.receipts()
                    if let receipt, receipt.state == "prepared" { self.review = receipt; self.complete = false }
                    else {
                        self.receipt = receipt; self.complete = true
                        self.tick.message = receipt == nil ? "这些词条已全部存在，无需重复迁移。" : "已新增 \(receipt!.added.formatted()) 条，\(existing.formatted()) 条已存在。"
                    }
                case .failure(let error): self.error = error.localizedDescription; self.receipts = MigrationStore.receipts()
                }
                NSApp.activate(ignoringOtherApps:true)
            }
        }
    }
    func applyReview() {
        guard !busy, let plan = review, plan.added > 0 else { return }
        busy = true; error = nil; notice = nil
        tick = MigrationTick(phase:3,fraction:0,count:0,total:plan.sourceCount ?? 0,word:"",message:"备份已保存，正在安装已验证词条…")
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result { try MigrationWorker.apply(id:plan.id,allowPartial:true) }
            DispatchQueue.main.async {
                self.busy = false; self.receipts = MigrationStore.receipts()
                switch result {
                case .success(let installed):
                    self.receipt = installed; self.review = nil; self.complete = true
                    var message = "已新增 \(installed.added.formatted()) 条"
                    if let existing = installed.existingCount { message += "，\(existing.formatted()) 条已存在" }
                    if installed.sourceFiles != nil {
                        message += installed.skipped > 0 ? "；\(installed.skipped.formatted()) 条未迁移，完整来源与未迁移档案已保留。" : "。完整来源档案已保留。"
                    } else { message += "。安装前快照已保留，可撤销。" }
                    self.tick = MigrationTick(phase:3,fraction:1,count:installed.added + (installed.existingCount ?? 0),total:installed.sourceCount ?? 0,word:"",message:message)
                case .failure(let e): self.error = (e as? MigrationError)?.message ?? "安装未完成，请检查文件与权限。"
                }
            }
        }
    }
    func restore(_ receipt: MigrationReceipt) {
        guard !busy else { return }; busy = true; error = nil; notice = nil; complete = false; review = nil; words = []; showWords = false
        tick = MigrationTick(phase:3,fraction:0,count:0,total:0,word:"",message:"正在恢复迁移前的词库…")
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result { () -> Void in
                _ = try MigrationWorker.restoreChecked(receipt)
            }
            DispatchQueue.main.async {
                self.busy = false; self.receipts = MigrationStore.receipts()
                switch result { case .success: self.notice = "已恢复到这次迁移之前，原词库已回读确认。"; self.receipt = nil; self.refresh()
                case .failure(let e): self.error = e.localizedDescription }
            }
        }
    }
}
