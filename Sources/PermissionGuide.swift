import AppKit
import SwiftUI
import Combine
import ApplicationServices

@MainActor enum AccessibilityAccess {
    static var allowed: Bool { AXIsProcessTrusted() }
    static func openSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    static func restart() {
        let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at:Bundle.main.bundleURL,configuration:config) { app,error in
            if app != nil && error == nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
        }
    }
}
struct PermissionGuide: View {
    @ObservedObject var model: MigrationModel
    @State private var allowed = AccessibilityAccess.allowed
    private let timer = Timer.publish(every:1,on:.main,in:.common).autoconnect()
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("让词渡帮你读取百度词库").font(.title2.bold()); Spacer(); Button(model.waitingForPermission ? "暂不迁移" : "完成") { model.showPermissionGuide = false } }
            Text("词渡需要操作百度输入法的设置窗口，替你点击导出。权限由 macOS 管理，需要你亲自开启一次。").foregroundStyle(.secondary)
            Label(allowed ? "权限已生效，可以继续准备迁移" : "尚未检测到当前词渡获得权限",systemImage:allowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(allowed ? Color.teal : Color.orange)
            VStack(alignment:.leading,spacing:14) {
                Text("1. 点击下面的「打开系统设置」。").font(.headline)
                Text("2. 找到「词渡」，打开右侧开关。若系统要求验证，请按提示使用触控 ID 或电脑密码。").font(.headline)
                Text(model.waitingForPermission ? "3. 返回词渡，权限生效后自动继续这次迁移。" : "3. 返回词渡。这里会自动确认权限，无需反复点击检测。").font(.headline)
            }
            Text("设置位置：隐私与安全 → 辅助功能。你这类新版 macOS 中可能显示为「设备控制和数据访问」。").font(.callout).foregroundStyle(.secondary)
            HStack { Button("打开系统设置",action:AccessibilityAccess.openSettings).buttonStyle(.borderedProminent); Button("在 Finder 中显示当前词渡",action:AccessibilityAccess.revealApp) }
            DisclosureGroup("找不到「词渡」？") {
                Text("点击「在 Finder 中显示当前词渡」。在系统权限列表点击「＋」，选择这份词渡.app；也可把 Finder 中的词渡拖入列表，再打开开关。").font(.callout).padding(.top,8)
            }
            DisclosureGroup("开关已打开，仍显示未生效？") {
                VStack(alignment:.leading,spacing:10) {
                    Text("先重启词渡。如果仍未生效，可能授权的是旧版本或另一份同名应用：在系统权限列表选中旧的「词渡」，点击「－」，再点「＋」添加 Finder 中这份当前应用并开启。移除权限记录不会删除词库。")
                    Text("当前应用：" + Bundle.main.bundleURL.path).font(.caption).textSelection(.enabled)
                    Button("重启词渡",action:AccessibilityAccess.restart)
                }.font(.callout).padding(.top,8)
            }
            Divider()
            Button("暂不授权，使用已导出的词库文件…") { model.showPermissionGuide = false; model.chooseFile() }
        }.padding(28).frame(width:610)
        .onReceive(timer) { _ in
            let current = AccessibilityAccess.allowed
            if current != allowed { allowed = current; model.refresh() }
        }
    }
}
