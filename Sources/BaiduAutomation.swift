import AppKit
import ApplicationServices
import Carbon

/// Uses only the installed input method's official export UI. Personal data stays in a private local folder.
enum BaiduAutomation {
    static func attr(_ e: AXUIElement, _ name: CFString) -> CFTypeRef? { var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(e,name,&v) == .success else { return nil }; return v }
    static func all(_ e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 15 else { return [] }
        let children = attr(e,kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
        return [e] + children.flatMap { all($0,depth:depth+1) }
    }
    static func label(_ e: AXUIElement) -> String {
        [kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute].compactMap { attr(e,$0 as CFString) as? String }.joined(separator: "|")
    }
    static func press(_ root: AXUIElement, matching text: String) throws {
        let matches = all(root).filter { label($0).components(separatedBy: "|").contains(text) }
        for e in matches { if AXUIElementPerformAction(e,kAXPressAction as CFString) == .success { return } }
        throw MigrationError("百度设置界面与当前适配器不一致。请打开百度设置 → 词库 → 用户词库，再重试；无需自己导出文件。")
    }
    static func key(_ code: CGKeyCode, pid: pid_t, flags: CGEventFlags = []) throws {
        guard onMain({ NSWorkspace.shared.frontmostApplication?.processIdentifier }) == pid else {
            throw MigrationError("百度导出窗口已离开前台，请保持该窗口打开后重试；词库未修改。")
        }
        guard let down = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true),
              let up = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false) else {
            throw MigrationError("无法操作百度导出窗口，请重试；词库未修改。")
        }
        down.flags = flags; up.flags = flags
        down.post(tap:.cghidEventTap); up.post(tap:.cghidEventTap)
    }
    static func wait(cancelled: () -> Bool = { false }, failure: String = "等待百度导出窗口超时。请关闭其他弹窗后重试，现有词库未修改。", _ predicate: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if cancelled() { throw MigrationError("迁移已取消，输入法词库未修改。") }
            if predicate() { return }; Thread.sleep(forTimeInterval:0.1)
        }
        throw MigrationError(failure)
    }
    private static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute:work)
    }
    private static func sourceProperty(_ source: TISInputSource, _ key: CFString) -> CFTypeRef? {
        onMain {
            guard let pointer = TISGetInputSourceProperty(source,key) else { return nil }
            return Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
        }
    }
    private static func settingsWindow(_ root: AXUIElement) -> AXUIElement? {
        let windows = attr(root,kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
        return windows.first { label($0).contains("百度输入法设置") }
    }
    private static func raiseSettings(_ root: AXUIElement, app: NSRunningApplication) {
        _ = onMain { app.activate(options:[.activateIgnoringOtherApps]) }
        if let window = settingsWindow(root) { _ = AXUIElementPerformAction(window,kAXRaiseAction as CFString) }
    }
    private static func openMenu(_ item: AXUIElement) -> Bool {
        if AXUIElementPerformAction(item,kAXPressAction as CFString) == .success { return true }
        // The macOS input-menu extra exposes its frame but may reject AXPress.
        // Click that discovered frame rather than assuming a screen or menu-bar position.
        guard let position = attr(item,kAXPositionAttribute as CFString),
              let size = attr(item,kAXSizeAttribute as CFString),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return false }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position,to:AXValue.self),.cgPoint,&point),
              AXValueGetValue(unsafeBitCast(size,to:AXValue.self),.cgSize,&dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return false }
        point.x += dimensions.width / 2; point.y += dimensions.height / 2
        guard let down = CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left),
              let up = CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left) else { return false }
        down.post(tap:.cghidEventTap); up.post(tap:.cghidEventTap)
        return true
    }
    /// Opens the official input-menu action; never sends undocumented messages to Baidu.
    private static func openSettings(_ app: NSRunningApplication, cancelled: () -> Bool) throws {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if settingsWindow(root) != nil { raiseSettings(root,app:app); return }
        let apps = NSWorkspace.shared.runningApplications.filter {
            ["com.apple.TextInputMenuAgent","com.apple.systemuiserver","com.apple.controlcenter","com.baidu.inputmethod.BaiduIM"].contains($0.bundleIdentifier ?? "")
        }
        let roots = apps.map { AXUIElementCreateApplication($0.processIdentifier) }
        var bars: [AXUIElement] = []
        for menuRoot in roots {
            for name in [kAXExtrasMenuBarAttribute,kAXMenuBarAttribute] {
                if let bar = attr(menuRoot,name as CFString) { bars.append(unsafeBitCast(bar,to:AXUIElement.self)) }
            }
        }
        let items = bars.flatMap { all($0) }
        let candidate = items.first {
            guard attr($0,kAXRoleAttribute as CFString) as? String == kAXMenuBarItemRole else { return false }
            let value = label($0)
            let identifier = attr($0,kAXIdentifierAttribute as CFString) as? String ?? ""
            return identifier.localizedCaseInsensitiveContains("menuextra.textinput") || ["百度","输入法","输入菜单","Text Input"].contains { value.localizedCaseInsensitiveContains($0) }
        }
        guard let candidate, openMenu(candidate) else {
            throw MigrationError("暂时无法展开系统输入法菜单。请在屏幕右上角百度菜单中打开「百度输入法设置」，然后重试；词渡会继续完成导出和迁移。")
        }
        var setting: AXUIElement?
        try wait(cancelled:cancelled,failure:"未找到百度设置入口。请从菜单栏打开「百度输入法设置」后重试，词库未修改。") {
            // Extra menu bars are separate AX attributes, not application children.
            // Read only the opened input-menu item, avoiding unrelated app menus.
            setting = all(candidate).first {
                guard attr($0,kAXRoleAttribute as CFString) as? String == kAXMenuItemRole else { return false }
                return label($0).components(separatedBy:"|").contains { $0.contains("百度输入法设置") || ["设置…","设置...","设置","偏好设置…","偏好设置...","偏好设置"].contains($0) }
            }
            if setting == nil {
                setting = (bars + roots).flatMap { all($0) }.first {
                    attr($0,kAXRoleAttribute as CFString) as? String == kAXMenuItemRole && label($0).contains("百度输入法设置")
                }
            }
            return setting != nil
        }
        guard let setting, AXUIElementPerformAction(setting,kAXPressAction as CFString) == .success else {
            throw MigrationError("无法打开百度设置。请从屏幕右上角百度菜单打开设置后重试。")
        }
        try wait(cancelled:cancelled,failure:"已点击百度设置入口，但窗口未出现。请关闭百度的其他弹窗后重试，词库未修改。") { settingsWindow(root) != nil }
        raiseSettings(root,app:app)
    }
    private static func dismissExportSuccess(_ root: AXUIElement) {
        if all(root).contains(where: { label($0).contains("导出用户词成功") }) {
            try? press(root,matching:"好的")
        }
    }
    static func export(to destination: URL, cancelled: () -> Bool = { false }, progress: (String) -> Void = { _ in }) throws -> Data {
        guard AXIsProcessTrusted() else { throw MigrationError("首次自动读取需要辅助功能权限。请在系统设置 → 隐私与安全性 → 辅助功能中允许词渡，然后重试。") }
        let previous = onMain { TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() }
        let sources = onMain { TISCreateInputSourceList(nil,false)?.takeRetainedValue() as? [TISInputSource] ?? [] }
        guard let baidu = sources.first(where: {
            sourceProperty($0,kTISPropertyBundleID) as? String == "com.baidu.inputmethod.BaiduIM" && sourceProperty($0,kTISPropertyInputSourceIsSelectCapable) as? Bool == true && sourceProperty($0,kTISPropertyInputSourceIsEnabled) as? Bool == true
        }) else { throw MigrationError("请先在系统输入法中添加并启用百度输入法，再重试。也可以使用已有导出文件。") }
        progress("正在打开百度输入法设置…")
        guard onMain({ TISSelectInputSource(baidu) }) == noErr else { throw MigrationError("无法切换到百度输入法，请在菜单栏选择百度后重试。") }
        defer { if let previous { _ = onMain { TISSelectInputSource(previous) } } }
        try wait(cancelled:cancelled,failure:"百度输入法未能启动，请在菜单栏选择百度后重试，词库未修改。") { !NSRunningApplication.runningApplications(withBundleIdentifier:"com.baidu.inputmethod.BaiduIM").isEmpty }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:"com.baidu.inputmethod.BaiduIM").first else { throw MigrationError("百度输入法未能启动，请重试。") }
        _ = onMain { app.activate(options:[.activateIgnoringOtherApps]) }
        Thread.sleep(forTimeInterval:0.25)
        _ = onMain { TISSelectInputSource(baidu) }
        Thread.sleep(forTimeInterval:0.2)
        try openSettings(app,cancelled:cancelled)
        let root = AXUIElementCreateApplication(app.processIdentifier)
        dismissExportSuccess(root)
        progress("正在通过百度官方界面导出词库…")
        guard let settings = settingsWindow(root) else { throw MigrationError("百度设置窗口已关闭，请重试。") }
        try press(settings,matching:"词库")
        Thread.sleep(forTimeInterval:0.2)
        if let row = all(settings).first(where: { label($0) == "用户词库" }), let parent = attr(row,kAXParentAttribute as CFString) {
            AXUIElementSetAttributeValue(unsafeBitCast(parent,to:AXUIElement.self),kAXSelectedAttribute as CFString,kCFBooleanTrue)
        }
        Thread.sleep(forTimeInterval:0.2)
        try press(settings,matching:"导出...")
        let saveNames = ["存储","保存","Save","导出"]
        try wait(cancelled:cancelled,failure:"百度未显示导出保存窗口。请关闭百度的其他弹窗后重试，词库未修改。") {
            all(root).contains { element in
                attr(element,kAXRoleAttribute as CFString) as? String == kAXButtonRole && label(element).components(separatedBy:"|").contains { saveNames.contains($0) }
            }
        }
        progress("正在将百度词库保存到本机私有目录…")
        _ = AXUIElementSetAttributeValue(root,kAXFrontmostAttribute as CFString,kCFBooleanTrue)
        if let name = all(root).first(where: { attr($0,kAXIdentifierAttribute as CFString) as? String == "saveAsNameTextField" }) {
            _ = AXUIElementSetAttributeValue(name,kAXFocusedAttribute as CFString,kCFBooleanTrue)
        }
        Thread.sleep(forTimeInterval:0.2)
        try key(5,pid:app.processIdentifier,flags:[.maskCommand,.maskShift])
        var field: AXUIElement?
        try wait(cancelled:cancelled,failure:"无法定位导出文件的保存路径。请关闭百度保存窗口后重试，词库未修改。") {
            field = all(root).first {
                let role = attr($0,kAXRoleAttribute as CFString) as? String
                let identifier = attr($0,kAXIdentifierAttribute as CFString) as? String ?? ""
                return (role == kAXComboBoxRole || role == kAXTextFieldRole) && identifier != "saveAsNameTextField" && identifier != "_NS:8" && (attr($0,kAXFocusedAttribute as CFString) as? Bool == true)
            }
            return field != nil
        }
        guard let field, AXUIElementSetAttributeValue(field,kAXValueAttribute as CFString,destination.deletingLastPathComponent().path as CFString) == .success else { throw MigrationError("无法设置自动保存路径，已停止。") }
        try key(36,pid:app.processIdentifier)
        try wait(cancelled:cancelled,failure:"无法确认导出保存目录，词库未修改。") {
            all(root).contains { attr($0,kAXIdentifierAttribute as CFString) as? String == "saveAsNameTextField" && attr($0,kAXFocusedAttribute as CFString) as? Bool == true }
        }
        guard let name = all(root).first(where: { attr($0,kAXIdentifierAttribute as CFString) as? String == "saveAsNameTextField" }), AXUIElementSetAttributeValue(name,kAXValueAttribute as CFString,destination.lastPathComponent as CFString) == .success else { throw MigrationError("无法设置导出文件名，词库未修改。") }
        let labels = all(root).map(label)
        guard let saveName = saveNames.first(where: { name in labels.contains { $0.components(separatedBy:"|").contains(name) } }) else { throw MigrationError("未找到百度导出确认按钮，词库未修改。") }
        try press(root,matching:saveName)
        try wait(cancelled:cancelled,failure:"百度没有生成导出文件。请关闭保存窗口后重试，词库未修改。") { FileManager.default.fileExists(atPath:destination.path) }
        dismissExportSuccess(root)
        let data = try Lexicon.boundedRead(destination)
        _ = try Lexicon.parseBaidu(data)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
        return data
    }
}
