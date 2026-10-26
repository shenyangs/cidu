import Foundation
import Darwin

struct MergeOutput { let data: Data; let added: Int; let existing: Int }
struct RejectedEntry: Codable { let index: Int; let reason: String; let entry: Entry }
struct MigrationSelection { let accepted: [Entry]; let rejected: [RejectedEntry] }
struct MigrationSource { let data: Data; let entries: [Entry]; let rejected: [RejectedEntry]; let existing: Int }

enum DoubaoMerge {
    static func select(_ entries: [Entry], mapping: [String:Int]) -> MigrationSelection {
        var accepted = [Entry](), rejected = [RejectedEntry]()
        for (i, e) in entries.enumerated() {
            let reason: String?
            if !e.hasBoundaries || e.syllables.isEmpty { reason = "缺少可靠音节边界" }
            else if !e.syllables.allSatisfy({ mapping[$0.lowercased()].map { (0...65535).contains($0) } == true }) { reason = "编码未通过目标引擎验证" }
            else if e.word.isEmpty || e.syllables.count >= 32768 || 4 + e.syllables.joined().lowercased().utf8.count + 2 * e.word.utf16.count >= 65536 { reason = "超过目标词条长度上限" }
            else { reason = nil }
            if let reason { rejected.append(RejectedEntry(index:i+1,reason:reason,entry:e)) }
            else { accepted.append(e) }
        }
        return MigrationSelection(accepted:accepted,rejected:rejected)
    }
    static func build(_ original: Data, entries: [Entry], mapping: [String: Int], progress: (Int, Entry) throws -> Void = { _,_ in }) throws -> MergeOutput {
        let report = try Lexicon.decodeDoubao(original)
        guard report.consistent else { throw MigrationError("目标词库未通过完整性检查，未作修改。") }
        let b = [UInt8](original)
        var h = try (0..<16).map { try Lexicon.u32(b, $0*4) }
        var payload = Data(b[h[10]..<h[10]+h[12]])
        var records: [(ids: [Int], offset: Int)] = []
        for i in 0..<h[9] { records.append((report.entries[i].nativeSyllables!, try Lexicon.u32(b, h[6]+i*4))) }
        var keys = Set(report.entries.map { $0.word + "\u{1f}" + $0.nativeSyllables!.map(String.init).joined(separator: ",") })
        var added = 0
        let pt = report.entries.compactMap { $0.nativeAttributes?[1] }.max() ?? 0
        for (i, e) in entries.enumerated() {
            guard e.hasBoundaries, !e.syllables.isEmpty else { throw MigrationError("存在无法可靠映射的编码；已停止，全部原词库保持不变。") }
            let syllables = e.syllables.map { $0.lowercased() }
            var ids = [Int]()
            for s in syllables {
                if let v = mapping[s], v >= 0 && v <= 65535 { ids.append(v) }
                else { throw MigrationError("有词条的编码未通过目标引擎验证，已停止迁移；原词库未改动。") }
            }
            let key = e.word + "\u{1f}" + ids.map(String.init).joined(separator: ",")
            if keys.insert(key).inserted {
                let py = [UInt8](syllables.joined().utf8), word = Array(e.word.utf16)
                guard !word.isEmpty, py.count < 65536, ids.count < 32768, 4+py.count+2*word.count < 65536 else { throw MigrationError("词条超过目标输入法的长度上限。") }
                var raw = Data()
                for v in [1, pt, Int(Date().timeIntervalSince1970), 0] { put(v, bytes: 4, into: &raw) }
                put(ids.count*2, bytes: 2, into: &raw)
                for v in ids { put(v, bytes: 2, into: &raw) }
                put(4+py.count+2*word.count, bytes: 2, into: &raw)
                put(py.count, bytes: 2, into: &raw)
                raw.append(contentsOf: py.map { let v = Int($0 ^ 0xa5); return UInt8((v<<5 | v>>3)&255) })
                put(word.count, bytes: 2, into: &raw)
                for w in word { let v = Int(w)^0x65c9; put((v<<9 | v>>7)&65535, bytes: 2, into: &raw) }
                records.append((ids, payload.count)); payload.append(raw); added += 1
            }
            if i % 64 == 0 || i == entries.count-1 { try progress(i+1, e) }
        }
        if added == 0 { return MergeOutput(data: original, added: 0, existing: entries.count) }
        records.sort { $0.ids.lexicographicallyPrecedes($1.ids) }
        let slots = max(h[8], ((records.count+9999)/10000)*10000)
        guard slots <= 1_000_000, payload.count < Lexicon.sizeLimit/2 else { throw MigrationError("合并后的词库超出安全容量。") }
        h[7] = slots*4; h[8] = slots; h[9] = records.count; h[10] = h[6]+h[7]; h[12] = payload.count
        payload.append(Data(count: max(65536,payload.count/5))); h[11] = payload.count; h[3] = h[10]+h[11]
        var out = Data(); for v in h { put(v, bytes: 4, into: &out) }
        out.append(contentsOf: b[64..<h[6]])
        for r in records { put(r.offset, bytes: 4, into: &out) }
        out.append(Data(count: (slots-records.count)*4)); out.append(payload)
        let verified = try Lexicon.decodeDoubao(out)
        guard verified.consistent, verified.decoded == report.decoded+added,
              out.subdata(in: h[10]..<h[10]+reportDataLength(b)) == original.subdata(in: (try Lexicon.u32(b,40))..<(try Lexicon.u32(b,40))+reportDataLength(b)) else { throw MigrationError("合并校验失败，未安装。") }
        return MergeOutput(data: out, added: added, existing: entries.count-added)
    }
    private static func reportDataLength(_ b: [UInt8]) -> Int { (try? Lexicon.u32(b,48)) ?? 0 }
    static func put(_ value: Int, bytes: Int, into data: inout Data) { for i in 0..<bytes { data.append(UInt8((value >> (i*8))&255)) } }
}

struct MigrationReceipt: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let target: String
    let beforeHash: String
    let afterHash: String
    let added: Int
    var state: String
    var sourceCount: Int? = nil
    var existingCount: Int? = nil
    var rejectedCount: Int? = nil
    var sourceFiles: [String:String]? = nil
    var skipped: Int { rejectedCount ?? 0 }
    var statusTitle: String {
        switch state {
        case "installed": return skipped > 0 ? "部分迁移完成" : "已安装"
        case "restored": return "已恢复"
        case "unchanged": return "无需新增"
        case "interrupted": return "操作中断，词库已有变化"
        case "installing", "restoring": return "操作中断，待核对"
        default: return skipped > 0 ? (added > 0 ? "有词条待适配，尚未安装" : "无可新增词条，尚未安装") : "计划待执行"
        }
    }
}

enum MigrationStore {
    static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cidu/Transactions") }
    static func privateFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw MigrationError("备份目录必须是本机普通目录，不能是符号链接。") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd,&info) == 0, info.st_uid == getuid(), fchmod(fd,0o700) == 0 else { throw MigrationError("无法设置备份目录的私密权限。") }
    }
    static func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw MigrationError("无法同步词库目录。") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw MigrationError("目录写入未完成，请检查磁盘空间。") }
    }
    static func directory(id: String, root: URL = root) throws -> URL {
        guard UUID(uuidString:id) != nil else { throw MigrationError("记录 ID 无效。") }
        for url in [root, root.appendingPathComponent(id)] {
            let rv = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard rv.isDirectory == true, rv.isSymbolicLink != true else { throw MigrationError("备份目录无效或已被替换。") }
        }
        return root.appendingPathComponent(id)
    }
    static func receipts(in root: URL = root) -> [MigrationReceipt] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .compactMap { try? load(id:$0.lastPathComponent,root:root) }.sorted { $0.createdAt > $1.createdAt }
    }
    static func prepare(target: URL, before: Data, after: Data, added: Int, source: MigrationSource? = nil, root: URL = root) throws -> MigrationReceipt {
        try privateFolder(root)
        var receipt = MigrationReceipt(id: UUID().uuidString, createdAt: Date(), target: target.path, beforeHash: Compatibility.hash(before), afterHash: Compatibility.hash(after), added: added, state: "prepared")
        let dir = root.appendingPathComponent(receipt.id); try privateFolder(dir)
        do {
            try Lexicon.saveNew(before, at: dir.appendingPathComponent("before.dat"))
            try Lexicon.saveNew(after, at: dir.appendingPathComponent("after.dat"))
            if let source {
                guard added >= 0, added <= source.entries.count,
                      source.existing >= 0, source.existing <= source.entries.count - added,
                      source.rejected.count == source.entries.count - added - source.existing else { throw MigrationError("迁移统计不一致，未作修改。") }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                let files = ["source.original":source.data, "source.json":try Lexicon.archive(source.entries), "unmigrated.json":try Lexicon.archive(source.rejected.map(\.entry)), "unmigrated-reasons.json":try encoder.encode(source.rejected)]
                var hashes = [String:String]()
                for (name,data) in files {
                    guard data.count <= Lexicon.sizeLimit else { throw MigrationError("完整档案超过 64 MB，请先拆分来源。") }
                    try Lexicon.saveNew(data,at:dir.appendingPathComponent(name)); hashes[name] = Compatibility.hash(data)
                }
                receipt.sourceCount = source.entries.count; receipt.existingCount = source.existing
                receipt.rejectedCount = source.rejected.count; receipt.sourceFiles = hashes
            }
            try save(receipt, root: root)
            try syncDirectory(root)
            return receipt
        } catch { try? FileManager.default.removeItem(at:dir); throw error }
    }
    static func save(_ receipt: MigrationReceipt, root: URL = root) throws {
        let data = try JSONEncoder().encode(receipt)
        let dir = try directory(id:receipt.id,root:root)
        let url = dir.appendingPathComponent("receipt.json"), stage = dir.appendingPathComponent(".receipt-"+UUID().uuidString)
        try Lexicon.saveNew(data,at:stage)
        defer { try? FileManager.default.removeItem(at:stage) }
        guard rename(stage.path,url.path) == 0 else { throw MigrationError("无法保存迁移记录。") }
        try syncDirectory(dir)
    }
    static func replace(target: URL, expected: String, replacement: Data) throws {
        let rv = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard rv.isSymbolicLink != true, rv.isRegularFile == true, Compatibility.hash(try Lexicon.boundedRead(target)) == expected else { throw MigrationError("词库在操作期间发生变化。已停止以保留最新词条，请重试。") }
        let stage = target.deletingLastPathComponent().appendingPathComponent(".cidu-"+UUID().uuidString)
        try Lexicon.saveNew(replacement, at: stage)
        defer { try? FileManager.default.removeItem(at: stage) }
        guard Compatibility.hash(try Lexicon.boundedRead(target)) == expected else { throw MigrationError("词库发生变化，尚未替换。") }
        guard rename(stage.path,target.path) == 0 else { throw MigrationError("无法安装词库，备份已保留。") }
        try syncDirectory(target.deletingLastPathComponent())
        guard try Lexicon.boundedRead(target) == replacement else { throw MigrationError("安装后回读不一致，请使用恢复入口。") }
    }
    static func restore(_ receipt: MigrationReceipt, root: URL = root, persist: ((MigrationReceipt) throws -> Void)? = nil) throws -> MigrationReceipt {
        let current = try load(id:receipt.id,root:root)
        guard current.state == "installed" else { throw MigrationError("只有已安装记录可以恢复。") }
        let before = try Lexicon.boundedRead(try directory(id:current.id,root:root).appendingPathComponent("before.dat"))
        guard Compatibility.hash(before) == current.beforeHash else { throw MigrationError("备份校验失败，未作修改。") }
        let write = persist ?? { try save($0,root:root) }
        var restored = current; restored.state = "restoring"
        try write(restored) // Durable intent must precede the target rename.
        try replace(target:URL(fileURLWithPath:current.target),expected:current.afterHash,replacement:before)
        restored.state = "restored"
        do { try write(restored) } catch { throw MigrationError("原词库已恢复，记录收尾未完成；重新打开迁移记录即可核对。") }
        return restored
    }
}

// A single nonblocking lock prevents GUI/CLI transactions overlapping.
final class MigrationLock {
    private var descriptor: Int32 = -1
    init(root: URL = MigrationStore.root) throws {
        try MigrationStore.privateFolder(root)
        descriptor = open(root.appendingPathComponent(".lock").path,O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard descriptor >= 0 else { throw MigrationError("无法取得迁移锁。") }
        guard flock(descriptor,LOCK_EX | LOCK_NB) == 0 else { close(descriptor); descriptor = -1; throw MigrationError("另一个词渡操作正在进行，请稍后重试。") }
    }
    func release() { if descriptor >= 0 { flock(descriptor,LOCK_UN); close(descriptor); descriptor = -1 } }
    deinit { release() }
}
extension MigrationStore {
    static func load(id: String, root: URL = root) throws -> MigrationReceipt {
        let url = try directory(id:id,root:root).appendingPathComponent("receipt.json")
        var receipt = try JSONDecoder().decode(MigrationReceipt.self,from:Lexicon.boundedRead(url,limit:1024*1024))
        guard receipt.id == id, receipt.target.hasPrefix("/"), receipt.added >= 0,
              receipt.skipped >= 0, (receipt.sourceCount ?? 0) >= 0, (receipt.existingCount ?? 0) >= 0,
              ["prepared","installing","installed","restoring","restored","unchanged","interrupted"].contains(receipt.state) else { throw MigrationError("记录字段无效。") }
        let legacy = receipt.sourceFiles == nil && receipt.sourceCount == nil && receipt.existingCount == nil && receipt.rejectedCount == nil
        if !legacy {
            guard let files = receipt.sourceFiles, let total = receipt.sourceCount,
                  let existing = receipt.existingCount, let rejected = receipt.rejectedCount,
                  Set(files.keys) == ["source.original","source.json","unmigrated.json","unmigrated-reasons.json"],
                  receipt.added <= total, existing <= total - receipt.added,
                  rejected == total - receipt.added - existing else { throw MigrationError("来源档案统计无效。") }
        }
        // Read-only reconciliation: no automatic write to a dictionary after a crash.
        if ["installing","restoring"].contains(receipt.state) {
            let digest = (try? Lexicon.boundedRead(URL(fileURLWithPath:receipt.target))).map(Compatibility.hash)
            if digest == receipt.beforeHash { receipt.state = receipt.state == "installing" ? "prepared" : "restored" }
            else if digest == receipt.afterHash { receipt.state = "installed" }
            else { receipt.state = "interrupted" }
        }
        return receipt
    }
    static func checkedPlan(_ receipt: MigrationReceipt, root: URL = root, allowPartial: Bool = false) throws -> (Data,Data) {
        guard receipt.state == "prepared", UUID(uuidString:receipt.id) != nil,
              Date().timeIntervalSince(receipt.createdAt) >= -60,
              Date().timeIntervalSince(receipt.createdAt) < 86400 else { throw MigrationError("计划已执行或超过 24 小时，请重新生成。") }
        guard receipt.skipped == 0 || allowPartial else { throw MigrationError("有 \(receipt.skipped) 条尚不能迁移，原文已保留。请审阅数量后明确选择部分迁移。") }
        guard receipt.skipped == 0 || receipt.added > 0 else { throw MigrationError("没有可新增的词条；未迁移记录已完整保留，词库未修改。") }
        let dir = try directory(id:receipt.id,root:root)
        if let files = receipt.sourceFiles {
            guard Set(files.keys) == ["source.original","source.json","unmigrated.json","unmigrated-reasons.json"],
                  let total = receipt.sourceCount, let existing = receipt.existingCount,
                  receipt.added >= 0, receipt.added <= total,
                  existing >= 0, existing <= total - receipt.added,
                  receipt.skipped == total - receipt.added - existing else { throw MigrationError("来源档案统计无效。") }
            for (name,hash) in files {
                guard Compatibility.hash(try Lexicon.boundedRead(dir.appendingPathComponent(name))) == hash else { throw MigrationError("来源档案完整性校验失败，未安装。") }
            }
        } else if receipt.skipped > 0 { throw MigrationError("缺少未迁移词条的完整档案，未安装。") }
        let before = try Lexicon.boundedRead(dir.appendingPathComponent("before.dat"))
        let after = try Lexicon.boundedRead(dir.appendingPathComponent("after.dat"))
        guard Compatibility.hash(before) == receipt.beforeHash, Compatibility.hash(after) == receipt.afterHash,
              Compatibility.hash(try Lexicon.boundedRead(URL(fileURLWithPath:receipt.target))) == receipt.beforeHash,
              try Lexicon.decodeDoubao(after).consistent else { throw MigrationError("计划或词库已变化，请重新生成计划。") }
        let old = try Lexicon.decodeDoubao(before), new = try Lexicon.decodeDoubao(after)
        guard old.consistent, receipt.added >= 0, new.decoded-old.decoded == receipt.added else {
            throw MigrationError("计划新增数量与词库不一致。")
        }
        return (before,after)
    }
}

extension MigrationStore {
    // Caller validates the installed engine/account and holds the migration lock.
    static func commitPlan(_ receipt: MigrationReceipt, root: URL = root, allowPartial: Bool = false, persist: ((MigrationReceipt) throws -> Void)? = nil) throws -> MigrationReceipt {
        let current = try load(id:receipt.id,root:root)
        guard current.state == "prepared", current.beforeHash == receipt.beforeHash, current.afterHash == receipt.afterHash else { throw MigrationError("计划状态已经变化，请重新读取记录。") }
        let (before,after) = try checkedPlan(current,root:root,allowPartial:allowPartial)
        let write = persist ?? { try save($0,root:root) }
        var committed = current
        if current.added == 0 {
            guard before == after else { throw MigrationError("零新增计划内容不一致。") }
            committed.state = "unchanged"; try write(committed); return committed
        }
        let target = URL(fileURLWithPath:current.target)
        committed.state = "installing"; try write(committed)
        try replace(target:target,expected:current.beforeHash,replacement:after)
        committed.state = "installed"
        do { try write(committed) } catch { throw MigrationError("词库已安装，记录收尾未完成；重新打开迁移记录可核对或恢复。") }
        return committed
    }
}
