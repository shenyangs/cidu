import AppKit

// JSON-only output: never expose entries, source bytes or helper diagnostics.
enum CiduCLI {
    static var version: String {
        let plist = URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        let info = (try? Data(contentsOf:plist)).flatMap { try? PropertyListSerialization.propertyList(from:$0,format:nil) as? [String:Any] }
        return info?["CFBundleShortVersionString"] as? String ?? "development"
    }
    static func emit(_ value: [String:Any]) {
        let data = (try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])) ?? Data("{}".utf8)
        FileHandle.standardOutput.write(data + Data([10]))
    }
    static func receipt(_ r: MigrationReceipt) -> [String:Any] {
        var value: [String:Any] = ["id":r.id,"state":r.state,"added":r.added,"unmigrated":r.skipped,"partialConfirmationRequired":r.state == "prepared" && r.skipped > 0,"createdAt":ISO8601DateFormatter().string(from:r.createdAt),"beforeHash":r.beforeHash,"afterHash":r.afterHash]
        value["existing"] = r.existingCount.map { $0 as Any } ?? NSNull()
        return value
    }
    static func run(_ args: [String]) -> Int32 {
        do {
            guard let command = args.first else { throw MigrationError("缺少命令，请运行 help。") }
            let tail = Array(args.dropFirst())
            switch command {
            case "help", "--help":
                guard tail.isEmpty else { throw MigrationError("help 不接受参数。") }
                emit(["ok":true,"version":version,"commands":["status [--file PATH]","plan [--file PATH]","apply ID --confirm [--allow-partial]","history","restore ID --confirm"],"route":"百度自动导出或已有导出文件 → 豆包","planLifetimeHours":24,"privacy":"默认输出统计，不输出词语；plan 只写本机私有备份，不安装词库。"])
            case "status", "plan":
                let file: URL?
                if tail.isEmpty { file = nil }
                else if tail.count == 2 && tail[0] == "--file" { file = URL(fileURLWithPath:tail[1]).standardizedFileURL }
                else { throw MigrationError("参数无效。使用 status/plan [--file PATH]。") }
                let report = Preflight.inspect(source:"百度输入法",target:"豆包输入法",file:file)
                if command == "status" {
                    emit(["ok":true,"ready":report.ready,"checks":report.checks.map { c -> [String:Any] in
                        var value: [String:Any] = ["id":c.id,"passed":c.passed,"title":c.title,"detail":c.detail]
                        if let action = c.action { value["remedy"] = action.rawValue }
                        return value
                    }]); return report.ready ? 0 : 2
                }
                guard report.ready else { emit(["ok":false,"code":"preflight_failed","failedChecks":report.checks.filter { !$0.passed }.map(\.id),"message":"先运行 status 查看处理建议。"]); return 2 }
                let (r,existing) = try MigrationWorker.run(file:file,prepareOnly:true,cancelled:{false},tick:{_ in})
                guard let r else { throw MigrationError("未生成计划。") }
                let next = r.skipped > 0 ? (r.added == 0 ? "没有可新增词条；请保留档案，等待适配或更换来源。" : "先审阅未迁移数量与保留档案。明确接受部分迁移后：apply \(r.id) --confirm --allow-partial") : "apply \(r.id) --confirm"
                emit(["ok":true,"plan":receipt(r),"existing":existing,"installed":false,"next":next])
            case "apply", "restore":
                let partial = command == "apply" && tail.count == 3 && tail.last == "--allow-partial"
                guard (tail.count == 2 || partial), tail[1] == "--confirm", UUID(uuidString:tail[0]) != nil else { throw MigrationError("执行需要记录 ID 和 --confirm；部分迁移还须明确 --allow-partial。请先审阅计划或恢复记录。") }
                let r = command == "apply" ? try MigrationWorker.apply(id:tail[0],allowPartial:partial) : try MigrationWorker.restoreChecked(MigrationStore.load(id:tail[0]))
                emit(["ok":true,"receipt":receipt(r)])
            case "history":
                guard tail.isEmpty else { throw MigrationError("history 不接受参数。") }
                emit(["ok":true,"receipts":MigrationStore.receipts().map(receipt)])
            default: throw MigrationError("未知命令，请运行 help。")
            }
            return 0
        } catch {
            // Parser/Cocoa errors can embed words or private paths. Only our own fixed messages are exposed.
            let message = (error as? MigrationError)?.localizedDescription ?? "操作失败；请检查文件与权限，必要时在词渡中查看。"
            emit(["ok":false,"code":"operation_failed","message":message]); return 1
        }
    }
}
#if CIDU_CLI
@main struct CiduCommand {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        DispatchQueue.global(qos:.userInitiated).async {
            let result = CiduCLI.run(args)
            DispatchQueue.main.async { exit(result) }
        }
        // AX automation and input-method restarts require an active main run loop.
        RunLoop.main.run()
    }
}
#endif
