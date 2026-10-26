import SwiftUI
import AppKit

struct AgentGuide: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var skill: URL { Bundle.main.resourceURL!.appendingPathComponent("cidu-migrate") }
    private var cli: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/cidu-cli") }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("交给我的 AI 助手").font(.title2.bold()); Spacer(); Button("完成") { dismiss() } }
            Text("让你正在使用的 Agent 帮你检查环境、解释迁移计划，再调用词渡完成迁移。与桌面操作共用备份和恢复机制。").foregroundStyle(.secondary)
            Text("1. 把词渡 Skill 交给你的 Agent").font(.headline)
            Text("点击复制指引，粘贴到能访问本机文件、执行命令的 Agent 中。也可以打开 Skill 文件夹，按该工具的方式安装。").font(.callout)
            HStack {
                Button(copied ? "已复制" : "复制给 Agent 的指引") {
                    let text = "请读取词渡 Skill：\(skill.appendingPathComponent("SKILL.md").path)。本机 CLI：\(cli.path)。先检查环境并向我解释迁移计划；我目前只要求检查，请勿直接安装或恢复词库。"
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string); copied = true
                }.buttonStyle(.borderedProminent)
                Button("打开 Skill 文件夹") { NSWorkspace.shared.activateFileViewerSelecting([skill]) }
            }
            Text("2. 检查环境，审阅计划").font(.headline)
            Text("Agent 默认只能看到状态、数量和记录编号。生成计划不会安装词库，计划在 24 小时后失效；词库变化后也需要重新生成。").font(.callout)
            Text("3. 按你的要求执行，保留恢复记录").font(.headline)
            Text("授权迁移后，Agent 使用计划编号执行。若需要系统权限，仍须由你开启；Agent 不会自动获得更多权限。").font(.callout)
            Divider()
            Text("当前提供 CLI + Skill，支持百度自动读取或已有导出文件迁入已适配的豆包版本。MCP 接口尚未提供。").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width:600)
    }
}
