import SwiftUI
import AppKit

@MainActor final class ShandianshuoReviewModel: ObservableObject {
    struct Row: Identifiable {
        let id: Int
        let entry: Entry
        var pronunciation: String
        var confirmed = false
    }
    @Published var rows = [Row]()
    @Published var original = Data()
    @Published var name = ""
    @Published var error: String?
    @Published var busy = false
    @Published var page = 0
    var confirmedCount: Int { rows.filter(\.confirmed).count }
    var indices: Range<Int> { let start = min(page * 50, rows.count); return start..<min(start + 50, rows.count) }

    func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Shandianshuo/workspace/library")
        if FileManager.default.fileExists(atPath: library.path) { panel.directoryURL = library }
        panel.message = "选择闪电说资料库中的 DICTIONARY.md 或其副本。只读取词典，不读取账号、录音或其他资料。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Lexicon.boundedRead(url) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let data): self.load(data, name: url.lastPathComponent)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    func load(_ data: Data, name: String) {
        busy = true; error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Shandianshuo.read(data).entries.enumerated().map { Row(id: $0.offset, entry: $0.element, pronunciation: Shandianshuo.suggestion($0.element.word)) } }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let rows): self.rows = rows; self.original = data; self.name = name; self.page = 0
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    func save(completion: @escaping (URL) -> Void) {
        guard !busy, confirmedCount > 0 else { return }
        busy = true; error = nil
        let rows = rows, original = original
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> URL in
                let pronunciations = Dictionary(uniqueKeysWithValues: rows.filter(\.confirmed).map { ($0.id, $0.pronunciation) })
                let imported = try Shandianshuo.reviewed(rows.map(\.entry), pronunciations: pronunciations)
                let parent = MigrationStore.root.appendingPathComponent("imports")
                try MigrationStore.privateFolder(parent)
                return try Packages.create(in: parent, source: original, imported: imported, format: .archive)
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let url): completion(url)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
}

struct ShandianshuoReview: View {
    @StateObject private var model = ShandianshuoReviewModel()
    @Environment(\.dismiss) private var dismiss
    var initialData: Data? = nil
    let completion: (URL) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("把闪电说的词，带到豆包").font(.title2.bold())
                    Text("读取词典 → 核对读音 → 检查豆包并迁移").foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }.disabled(model.busy)
            }
            Text(Shandianshuo.warning).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.rows.isEmpty ? "选择闪电说词典…" : "更换词典…", action: model.choose).disabled(model.busy)
                Text(model.name).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            if model.rows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("在闪电说的资料库中找到「词典」，选择对应的 DICTIONARY.md 文件。也可以从另一台电脑复制词典后读取。")
                    Text("普通词条一行一个；纠错规则使用「错写 → 正确写法」。无需在这台电脑安装闪电说。")
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Text("拼音是本机生成的建议，请特别核对人名、多音字。空格分隔音节，ü 写作 v；修改后需重新勾选。").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.indices), id: \.self) { index in
                            HStack(alignment: .center, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.rows[index].entry.word).textSelection(.enabled)
                                    if let from = Shandianshuo.origin(model.rows[index].entry)?.correctionFrom {
                                        Text("原纠错：\(from) → \(model.rows[index].entry.word)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.frame(width: 230, alignment: .leading)
                                TextField("例如：chong qing", text: Binding(get: { model.rows[index].pronunciation }, set: {
                                    model.rows[index].pronunciation = $0; model.rows[index].confirmed = false
                                })).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("\(model.rows[index].entry.word)的拼音")
                                Toggle("读音已核对", isOn: $model.rows[index].confirmed)
                                    .disabled((try? Shandianshuo.syllables(model.rows[index].pronunciation)) == nil)
                            }
                            Divider()
                        }
                    }.padding(.trailing, 8)
                }.disabled(model.busy)
                HStack {
                    Text("已核对 \(model.confirmedCount) / \(model.rows.count) 条").monospacedDigit()
                    Spacer()
                    Button("上一页") { model.page -= 1 }.disabled(model.page == 0 || model.busy)
                    Text("\(model.page + 1) / \(max(1, (model.rows.count + 49) / 50))").monospacedDigit()
                    Button("下一页") { model.page += 1 }.disabled((model.page + 1) * 50 >= model.rows.count || model.busy)
                }.font(.caption)
            }
            if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            HStack {
                Text("原文件和所有条目都会留档；未勾选的条目暂不迁移。此步骤不会修改豆包。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("保存并继续") { model.save { url in completion(url); dismiss() } }
                    .buttonStyle(.borderedProminent).disabled(model.busy || model.confirmedCount == 0)
            }
        }.padding(26).frame(width: 850, height: 620)
            .onAppear { if let initialData { model.load(initialData, name: "闪电说词典副本") } }
    }
}
