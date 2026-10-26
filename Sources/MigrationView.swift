import SwiftUI
import AppKit

struct MigrationView: View {
    @StateObject private var model = MigrationModel()
    @State private var showAgentGuide = false
    @State private var showCheckDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let sources = ["百度输入法","搜狗输入法","鼠须管 Rime","QQ 输入法","微信输入法","系统拼音"]
    private let targets = ["豆包输入法","百度输入法","搜狗输入法","鼠须管 Rime","微信输入法","系统拼音"]
    private let phases = ["读取词库","合并词条","引擎验证","安装完成"]
    var body: some View {
        ZStack {
            Color(nsColor:.windowBackgroundColor)
            if !reduceTransparency {
                GeometryReader { geo in
                    Ellipse().fill(Color.blue.opacity(0.13)).frame(width:geo.size.width*0.8,height:420).blur(radius:110).offset(x:-220,y:-220)
                    Ellipse().fill(Color.cyan.opacity(0.10)).frame(width:600,height:350).blur(radius:100).offset(x:geo.size.width-430,y:geo.size.height-180)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            VStack(spacing:0) {
                HStack {
                    Label("词渡",systemImage:"arrow.triangle.swap").font(.headline)
                    Spacer()
                    Button { model.receipts = MigrationStore.receipts(); model.showHistory = true } label: { Label("迁移记录",systemImage:"clock.arrow.circlepath") }.disabled(model.busy)
                    Menu { Button("交给我的 AI 助手") { showAgentGuide = true }; Button("文件转换工具") { model.showAdvanced = true }; Button("选择已有词库文件…",action:model.chooseFile); if model.file != nil { Button("改用自动读取") { model.file = nil } } } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).frame(width:28).disabled(model.busy).accessibilityLabel("更多工具")
                }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal,30).padding(.top,22)
                Spacer(minLength:18)
                VStack(spacing:12) {
                    Text(model.review != nil ? "迁移前，再看一眼。" : model.complete ? ((model.receipt?.skipped ?? 0) > 0 ? "可用词条已到站。" : "你的词，已经到站。") : "熟悉的词，换个地方继续。")
                        .font(.system(size:32,weight:.semibold)).multilineTextAlignment(.center)
                    Text(model.busy ? "全程在这台 Mac 上处理" : "选好两端，一键迁移。原词库自动备份，支持回退。")
                        .font(.system(size:14)).foregroundStyle(.secondary)
                }.padding(.bottom,28)
                HStack(spacing:26) {
                    endpoint("从这里",selection:$model.source,options:sources,symbol:"tray.full",color:.blue)
                    Image(systemName:"arrow.right").font(.system(size:24,weight:.medium)).foregroundStyle(.secondary).accessibilityHidden(true)
                    endpoint("到这里",selection:$model.target,options:targets,symbol:"tray.and.arrow.down",color:.teal)
                }.padding(.horizontal,50).disabled(model.busy)
                if let file = model.file { Text("使用文件：\(file.lastPathComponent)").font(.caption).foregroundStyle(.secondary).padding(.top,10) }
                VStack(spacing:16) {
                    if model.busy || model.complete { activity }
                    else if let receipt = model.review { reviewPanel(receipt) }
                    else {
                        preflightPanel
                    }
                    if let error = model.error {
                        HStack(alignment:.top,spacing:10) {
                            Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.orange)
                            VStack(alignment:.leading,spacing:8) {
                                Text(error).font(.callout).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                                if error.contains("辅助功能") {
                                    Button("查看授权步骤") { model.showPermissionGuide = true }
                                }
                            }
                        }.padding(14).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12)).frame(maxWidth:580)
                    }
                    if let notice = model.notice { Label(notice,systemImage:"checkmark.circle.fill").font(.callout).foregroundStyle(.teal) }
                }.frame(maxWidth:.infinity,minHeight:170).padding(.horizontal,45)
                Spacer(minLength:16)
                VStack(spacing:14) {
                    if model.busy {
                        if model.tick.phase < 3 { Button("取消迁移",action:model.cancel).buttonStyle(.bordered) }
                        else { Text("正在安全安装，请稍候…").font(.callout).foregroundStyle(.secondary) }
                    } else if let receipt = model.review {
                        HStack(spacing:16) {
                            if receipt.added > 0 {
                                Button(receipt.skipped > 0 ? "只迁移已验证的 \(receipt.added.formatted()) 条" : "安装 \(receipt.added.formatted()) 条",action:model.applyReview).buttonStyle(.borderedProminent)
                            }
                            Button("保留档案并返回",action:model.resetResult).buttonStyle(.bordered)
                        }.controlSize(.large)
                    } else if model.complete {
                        HStack(spacing:16) {
                            Button("再迁移一次",action:model.resetResult).buttonStyle(.borderedProminent)
                            if let receipt = model.receipt, receipt.state == "installed" { Button("撤销本次迁移") { model.restore(receipt) }.buttonStyle(.bordered) }
                        }.controlSize(.large)
                    } else {
                        Button(action:model.start) { Label(model.preflight?.needsPermission == true ? "授权并继续" : model.error == nil ? "开始迁移" : "重试迁移",systemImage:"arrow.right").font(.system(size:16,weight:.semibold)).padding(.horizontal,34).padding(.vertical,6) }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canRun).keyboardShortcut(.return,modifiers:[])
                    }
                    HStack(spacing:6) { Image(systemName:"lock.shield"); Text("本机处理 · 自动备份 · 不上传词库") }.font(.caption).foregroundStyle(.secondary)
                }.padding(.bottom,28)
            }
        }.frame(minWidth:820,minHeight:650)
        .sheet(isPresented:$model.showAdvanced) { VStack { HStack { Spacer(); Button("返回迁移") { model.showAdvanced = false } }.padding(12); AdvancedView() }.frame(width:1060,height:800) }
        .sheet(isPresented:$showAgentGuide) { AgentGuide() }
        .sheet(isPresented:$model.showPermissionGuide,onDismiss:model.permissionGuideDismissed) { PermissionGuide(model:model) }
        .onReceive(Timer.publish(every:2,on:.main,in:.common).autoconnect()) { _ in model.pollPermission() }
        .sheet(isPresented:$model.showHistory) { history }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .onChange(of:model.file) { _ in model.resetResult() }
        .onChange(of:model.source) { _ in model.file = nil; model.resetResult() }
        .onChange(of:model.target) { _ in model.resetResult() }
    }
    func reviewPanel(_ receipt: MigrationReceipt) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Text("豆包词库尚未修改").font(.headline)
            HStack(spacing:24) {
                Label("可新增 \(receipt.added.formatted()) 条",systemImage:"plus.circle").foregroundStyle(.teal)
                if let existing = receipt.existingCount { Text("已存在 \(existing.formatted()) 条") }
                Text("未迁移 \(receipt.skipped.formatted()) 条").foregroundStyle(.orange)
            }.font(.callout)
            Text(receipt.sourceFiles == nil ? "这是旧版计划，保留了安装前后快照，未保存完整来源档案。执行前会重新核对目标词库；也可以返回并重新生成计划。" : receipt.skipped == 0 ? "本次来源全部通过编码检查。完整来源已保存在本机，安装前还会重新核对目标词库。" : receipt.added > 0 ? "未通过验证的编码不会猜测或丢弃。完整来源和未迁移词条已保存在本机；你可以只迁移已验证的部分。" : "可验证词条已存在，或本次没有兼容词条。完整来源和未迁移词条已保存在本机，供以后适配。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if receipt.sourceFiles != nil { Button("查看保留的档案") { model.revealArchive(receipt) }.font(.callout) }
        }.padding(20).frame(maxWidth:650,alignment:.leading).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:16))
    }
    var preflightPanel: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                if model.checking { ProgressView().controlSize(.small); Text("正在检查这台 Mac…") }
                else { Label(model.preflight?.ready == true ? "准备好了，点击开始即可" : model.preflight?.needsPermission == true && model.preflight?.canBegin == true ? "首次使用，需要开启一次权限" : "迁移前，还需要准备一下",systemImage:model.preflight?.ready == true ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(model.preflight?.ready == true ? Color.teal : Color.orange) }
                Spacer()
                Button("重新检测",action:model.refresh).disabled(model.checking)
            }.font(.callout)
            if let report = model.preflight {
                if report.ready {
                    Text(model.file == nil ? "词渡会自动打开百度设置、导出并迁移。过程中请暂时不要操作输入法窗口。" : "将读取你选好的文件，保留豆包原有词条。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                let failures = report.checks.filter { !$0.passed }
                if !failures.isEmpty {
                    ScrollView { VStack(alignment:.leading,spacing:10) { ForEach(failures) { checkRow($0) } } }.frame(maxHeight:failures.count == 1 ? 75 : 150)
                }
                DisclosureGroup("查看 \(report.checks.filter(\.passed).count) 项通过的检查",isExpanded:$showCheckDetails) {
                    ScrollView { VStack(alignment:.leading,spacing:10) { ForEach(report.checks.filter(\.passed)) { checkRow($0) } }.padding(.top,8) }.frame(height:130)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.top,16).frame(maxWidth:650)
    }
    func checkRow(_ item: PreflightCheck) -> some View {
        HStack(alignment:.top,spacing:8) {
            Image(systemName:item.passed ? "checkmark.circle" : "exclamationmark.circle.fill").foregroundStyle(item.passed ? Color.teal : Color.orange)
            VStack(alignment:.leading,spacing:3) {
                Text(item.title).font(.caption.bold())
                Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:4)
            if let action = item.action { Button(action.rawValue) { model.remedy(action) }.controlSize(.small) }
        }
    }
    func endpoint(_ title: String, selection: Binding<String>, options:[String], symbol:String, color:Color) -> some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text(title).font(.callout).foregroundStyle(.secondary); Spacer(); Image(systemName:symbol).foregroundStyle(color).font(.title2) }
            Picker(title,selection:selection) { ForEach(options,id:\.self) { Text($0).tag($0) } }.labelsHidden().font(.system(size:22,weight:.semibold)).pickerStyle(.menu).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
            Text(model.checking ? "正在检查本机安装…" : (title == "从这里" ? model.preflight?.sourceStatus : model.preflight?.targetStatus) ?? "等待检查").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading).modifier(MigrationGlass())
    }
    var activity: some View {
        VStack(spacing:18) {
            HStack(spacing:0) {
                ForEach(Array(phases.enumerated()),id:\.offset) { index,title in
                    HStack(spacing:6) {
                        Image(systemName: model.complete || index < model.tick.phase ? "checkmark.circle.fill" : index == model.tick.phase ? "circle.inset.filled" : "circle")
                        Text(title)
                    }.font(.caption).foregroundStyle(model.complete || index <= model.tick.phase ? Color.accentColor : Color.secondary)
                    if index < phases.count-1 { Rectangle().fill(Color.secondary.opacity(0.2)).frame(height:1).padding(.horizontal,14) }
                }
            }
            ProgressView(value:model.complete ? 1 : (Double(model.tick.phase)+model.tick.fraction)/4).accessibilityLabel("迁移进度")
            HStack {
                Text(model.tick.message).font(.callout)
                Spacer()
                if model.tick.total > 0 { Text("\(model.tick.count.formatted()) / \(model.tick.total.formatted())").font(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }
            HStack(spacing:18) {
                Image(systemName:"tray.full.fill").font(.title2).foregroundStyle(.blue).accessibilityHidden(true)
                VStack(spacing:7) {
                    ForEach(Array(model.words.prefix(3).enumerated()),id:\.offset) { index, word in
                        Text(model.showWords ? word : "••••••")
                            .font(.system(size: index == 0 ? 18 : 14,weight:index == 0 ? .semibold : .regular))
                            .lineLimit(1).padding(.horizontal,22).padding(.vertical,7)
                            .background(.thinMaterial,in:Capsule())
                            .opacity(index == 0 ? 1 : index == 1 ? 0.65 : 0.35)
                            .frame(maxWidth:.infinity,alignment:index == 1 ? .trailing : .center)
                    }
                    if model.words.isEmpty { Text("读取完成后，词条会显示在这里").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth:.infinity,minHeight:96)
                .animation(reduceMotion ? nil : .easeOut(duration:0.25),value:model.tick.count)
                Image(systemName:model.complete ? "checkmark.circle.fill" : "tray.and.arrow.down.fill").font(.title2).foregroundStyle(.teal).accessibilityHidden(true)
                Button { model.showWords.toggle() } label: { Image(systemName:model.showWords ? "eye" : "eye.slash") }.buttonStyle(.plain).accessibilityLabel(model.showWords ? "隐藏词语" : "显示词语")
            }

        }.padding(.top,20)
    }
    var history: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text("迁移与恢复").font(.title2.bold()); Spacer(); Button("完成") { model.showHistory = false }.keyboardShortcut(.cancelAction) }
            Text("每次安装前都保存原始词库。若迁移后词库已有变化，回退会停止，避免覆盖新学的词。").foregroundStyle(.secondary)
            if model.receipts.isEmpty { Text("还没有安装记录。完成迁移后，备份会自动出现在这里。").padding(.vertical,35) }
            ScrollView {
                VStack(spacing:0) { ForEach(model.receipts) { receipt in
                    HStack {
                        VStack(alignment:.leading,spacing:6) {
                            Text(receipt.createdAt,style:.date).font(.headline)
                            Text("\(receipt.state == "prepared" ? "可新增" : "新增") \(receipt.added) 条 · \(receipt.statusTitle)").foregroundStyle(.secondary)
                            if receipt.skipped > 0 { Text("另有 \(receipt.skipped) 条未迁移，完整档案已保留").font(.caption).foregroundStyle(.secondary) }
                            if receipt.state == "interrupted" { Text("当前内容与前后快照均不同；已停止覆盖，请先保留当前词库。备份仍在记录文件夹内。").font(.caption).foregroundStyle(.orange) }
                        }
                        Spacer()
                        if receipt.state == "prepared" {
                            Button("查看") { model.review = receipt; model.complete = false; model.error = nil; model.showHistory = false }.disabled(model.busy)
                        }
                        if receipt.sourceFiles != nil { Button("档案") { model.revealArchive(receipt) }.disabled(model.busy) }
                        Button("恢复") { model.restore(receipt) }.disabled(model.busy || receipt.state != "installed")
                    }.padding(.vertical,16)
                    Divider()
                } }
            }
            if let error = model.error { Text(error).foregroundStyle(.orange).font(.callout) }
            if let notice = model.notice { Text(notice).foregroundStyle(.teal).font(.callout) }
        }.padding(28).frame(width:620,height:430)
    }
}

struct MigrationGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:24)) }
        else if #available(macOS 26.0, *) { content.glassEffect(.regular,in:RoundedRectangle(cornerRadius:24)) }
        else { content.background(.regularMaterial,in:RoundedRectangle(cornerRadius:24)) }
    }
}

@main struct CiduApp: App {
    var body: some Scene {
        WindowGroup("词渡") { MigrationView() }.defaultSize(width:900,height:700).windowStyle(.hiddenTitleBar)
            .commands { CommandGroup(replacing:.newItem) {} }
    }
}
