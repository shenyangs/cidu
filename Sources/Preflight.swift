import AppKit
import ApplicationServices

enum PreflightAction: String { case accessibility = "查看授权步骤", inputSettings = "打开输入法设置", sourceApp = "打开百度输入法", file = "选择已有词库文件", advanced = "打开文件工具" }
struct PreflightCheck: Identifiable {
    let id: String
    let title: String
    let passed: Bool
    let detail: String
    var action: PreflightAction? = nil
}
struct PreflightReport {
    let sourceStatus: String
    let targetStatus: String
    let checks: [PreflightCheck]
    var ready: Bool { !checks.isEmpty && checks.allSatisfy(\.passed) }
    var needsPermission: Bool { checks.contains { $0.id == "permission" && !$0.passed } }
    var canBegin: Bool { !checks.isEmpty && checks.allSatisfy { $0.passed || $0.id == "permission" } }
}
enum Preflight {
    static let names = ["百度输入法":"BaiduIM.app", "豆包输入法":"DoubaoIme.app", "搜狗输入法":"SogouInput.app", "鼠须管 Rime":"Squirrel.app", "QQ 输入法":"QQInput.app", "微信输入法":"WeType.app"]
    static func installation(_ name: String) -> (URL?,String) {
        if name == "系统拼音" { return (nil,"macOS 内置") }
        guard let filename = names[name] else { return (nil,"未识别") }
        let roots = ["/Library/Input Methods", NSHomeDirectory()+"/Library/Input Methods", "/Applications", NSHomeDirectory()+"/Applications"]
        let matches = roots.map { URL(fileURLWithPath:$0).appendingPathComponent(filename) }.filter { FileManager.default.fileExists(atPath:$0.path) }
        guard matches.count == 1, let url = matches.first else { return (nil,matches.isEmpty ? "未在常用安装位置找到" : "发现多个安装副本") }
        let info = NSDictionary(contentsOf:url.appendingPathComponent("Contents/Info.plist"))
        let short = info?["CFBundleShortVersionString"] as? String ?? "版本未知"
        let build = info?["CFBundleVersion"] as? String ?? ""
        let version = build.hasPrefix(short + ".") ? build : short
        return (url,"已安装 · \(version)")
    }
    static func inspect(source: String, target: String, file: URL?) -> PreflightReport {
        let fm = FileManager.default
        let (sourceURL,sourceStatus) = installation(source), (targetURL,targetStatus) = installation(target)
        var checks: [PreflightCheck] = []
        func add(_ id:String,_ title:String,_ ok:Bool,_ detail:String,_ action:PreflightAction? = nil) { checks.append(.init(id:id,title:title,passed:ok,detail:detail,action:ok ? nil : action)) }
        if let file {
            do {
                let imported = try Formats.read(Lexicon.boundedRead(file))
                add("source","来源文件",!imported.entries.isEmpty,imported.entries.isEmpty ? "文件没有可迁移词条，请重新选择。" : "可读取 · \(imported.entries.count.formatted()) 条；合并时继续核验编码。",.file)
            } catch { add("source","来源文件",false,"文件无法读取或格式不支持，请重新选择，或用文件工具检查。",.file) }
        } else if source == "百度输入法" {
            add("source-installed","来源安装",sourceURL != nil,sourceURL == nil ? "请先安装百度输入法，或选择已有导出文件。" : sourceStatus,.file)
            if let sourceURL {
                let info = NSDictionary(contentsOf:sourceURL.appendingPathComponent("Contents/Info.plist"))
                let version = info?["CFBundleVersion"] as? String ?? ""
                add("source-version","来源版本",version == "6.1.12.10",version == "6.1.12.10" ? "百度 6.1.12.10，已适配自动读取。" : "此构建尚未适配自动读取，请使用导出文件。",.file)
                let trusted = AXIsProcessTrusted()
                add("permission","读取权限",trusted,trusted ? "辅助功能权限已允许。" : "需要你在系统设置中开启「词渡」。点右侧查看分步说明；开启后自动检测。",.accessibility)
                add("source-prepare","自动准备",true,"开始后由词渡打开百度设置并导出，无需提前打开窗口。")
            }
        } else { add("source-adapter","来源读取",false,"此来源尚无自动读取适配器。请先在原输入法导出，再选择词库文件。",.file) }
        add("route","迁移路线",target == "豆包输入法",target == "豆包输入法" ? "支持合并到豆包；安装前仍会验证副本。" : "此目标尚无自动安装适配器，可先用文件工具转换。",.advanced)
        if target == "豆包输入法" {
            let expected = URL(fileURLWithPath:"/Library/Input Methods/DoubaoIme.app")
            add("target-installed","目标安装",targetURL == expected,targetURL == nil ? "请先安装并启用豆包输入法，使用一次后重新检测。" : targetURL == expected ? "标准安装位置检查通过。" : "自动安装目前要求豆包位于 /Library/Input Methods。",.inputSettings)
            if targetURL == expected {
                let targets = Lexicon.discoverDoubao(), report = Compatibility.inspect(targets:targets)
                add("target-version","目标版本",report.sameEngine,report.sameEngine ? "豆包 1.0.2 与已验证引擎一致。" : "此版本或引擎尚未适配，暂不能自动安装。可用文件工具保存档案。",.advanced)
                add("account","目标账号",targets.count == 1,targets.isEmpty ? "尚未找到词库。请切换到豆包输入一些文字，再重新检测。" : targets.count > 1 ? "发现多个账号词库，暂不能安全确定目标。请使用文件工具，勿删除账号目录。" : "找到唯一账号词库。",.inputSettings)
                if targets.count == 1 {
                    let path = targets[0]
                    do { let decoded = try Lexicon.decodeDoubao(Lexicon.boundedRead(path)); add("structure","目标词库",decoded.consistent,decoded.consistent ? "结构检查通过；保留已有词条。" : "词库结构不一致，暂不能迁移。",.advanced) }
                    catch { add("structure","目标词库",false,"目标词库无法读取或结构不支持。",.advanced) }
                    do { try MigrationWorker.verifyActiveTarget(path); add("active","使用中的账号",true,"运行状态与目标目录检查通过。") }
                    catch { add("active","使用中的账号",false,"无法核对正在使用的账号。请切换到豆包使用一次，再重新检测。",.inputSettings) }
                    add("writable","安装权限",fm.isWritableFile(atPath:path.path) && fm.isWritableFile(atPath:path.deletingLastPathComponent().path),"需要目标词库及其目录可写；权限不足时请检查该目录权限。",.advanced)
                }
            }
            var backupParent = MigrationStore.root
            while !fm.fileExists(atPath:backupParent.path) && backupParent.path != "/" { backupParent.deleteLastPathComponent() }
            add("backup","备份位置",fm.isWritableFile(atPath:backupParent.path),"备份目录访问检查；开始迁移时创建备份并核验，成功后才安装。",.advanced)
        }
        return .init(sourceStatus:file == nil ? sourceStatus : "使用已导出文件",targetStatus:targetStatus,checks:checks)
    }
}
