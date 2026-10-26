import Foundation

extension CoreTests {
    static func migrationTests(in dir: URL) throws {
        let original = fixture()
        let entries = try Lexicon.parseBaidu(Data("示例(shi|li) 7\n重庆(chong|qing) 6\n重庆(chong|qing) 9\n𠮷野(ji|ye) 8".utf8))
        let mapping = ["shi":100,"li":101,"chong":255,"qing":256,"ji":20,"ye":21]
        var seen = 0
        let merged = try DoubaoMerge.build(original,entries:entries,mapping:mapping) { n,_ in seen = n }
        try check(merged.added == 2 && merged.existing == 2 && seen == 4,"merge de-duplicates exact native keys and reports actual progress")
        let decoded = try Lexicon.decodeDoubao(merged.data)
        try check(decoded.consistent && decoded.decoded == 3,"merged output structurally valid")
        try check(decoded.entries.map(\.word).contains("𠮷野"),"merge nonBMP preserved")
        try check(decoded.entries.map { $0.nativeSyllables! } == [[20,21],[100,101],[255,256]],"numeric index ordering")
        let oldOffset = try Lexicon.u32([UInt8](original),40), newOffset = try Lexicon.u32([UInt8](merged.data),40)
        try check(original.subdata(in:oldOffset..<oldOffset+40) == merged.data.subdata(in:newOffset..<newOffset+40),"entire used original payload byte-identical")
        let again = try DoubaoMerge.build(merged.data,entries:entries,mapping:mapping)
        try check(again.added == 0 && again.data == merged.data,"repeat migration is byte-identical no-op")
        try fails("unknown code blocks complete merge") { _ = try DoubaoMerge.build(original,entries:entries,mapping:[:]) }
        try fails("cancellation prevents merge result") { _ = try DoubaoMerge.build(original,entries:entries,mapping:mapping) { _,_ in throw MigrationError("cancel") } }
        let root = dir.appendingPathComponent("Transactions"), target = dir.appendingPathComponent("target.dat")
        try Lexicon.saveNew(original,at:target)
        var receipt = try MigrationStore.prepare(target:target,before:original,after:merged.data,added:2,root:root)
        try check(try Data(contentsOf:target) == original,"backup preparation never changes target")
        try check(MigrationStore.receipts(in:root).count == 1,"backup receipt discoverable")
        let loaded = try MigrationStore.load(id:receipt.id,root:root)
        try check(loaded.beforeHash == receipt.beforeHash,"plan load preserves fingerprint")
        let planned = try MigrationStore.checkedPlan(loaded,root:root)
        try check(planned.0 == original && planned.1 == merged.data,"plan validates both private snapshots")
        try fails("plan traversal ID rejected") { _ = try MigrationStore.load(id:"../target.dat",root:root) }
        let expired = MigrationReceipt(id:receipt.id,createdAt:Date().addingTimeInterval(-86401),target:receipt.target,beforeHash:receipt.beforeHash,afterHash:receipt.afterHash,added:receipt.added,state:"prepared")
        try fails("expired plan rejected") { _ = try MigrationStore.checkedPlan(expired,root:root) }
        let altered = root.appendingPathComponent(receipt.id).appendingPathComponent("after.dat")
        try Data("damaged".utf8).write(to:altered)
        try fails("tampered candidate rejected") { _ = try MigrationStore.checkedPlan(receipt,root:root) }
        try merged.data.write(to:altered)
        let lock = try MigrationLock(root:root)
        try fails("overlapping GUI CLI operation refused") { _ = try MigrationLock(root:root) }
        lock.release()
        let nextLock = try MigrationLock(root:root); nextLock.release()
        try check(try Data(contentsOf:target) == original,"planning and lock tests leave target unchanged")

        let committed = try MigrationStore.commitPlan(receipt,root:root)
        try check(committed.state == "installed", "shared GUI CLI commit records installation")
        try fails("stale plan rejects changed target") { _ = try MigrationStore.checkedPlan(receipt,root:root) }
        receipt.state = "installed"; try MigrationStore.save(receipt,root:root)
        try fails("already applied plan cannot replay") { _ = try MigrationStore.checkedPlan(receipt,root:root) }
        try check(try Data(contentsOf:target) == merged.data,"atomic installation exact bytes")
        try fails("concurrent target changes block replacement") { try MigrationStore.replace(target:target,expected:receipt.beforeHash,replacement:original) }
        let restored = try MigrationStore.restore(receipt,root:root)
        try check(restored.state == "restored" && (try Data(contentsOf:target)) == original,"rollback restores original bytes")
        try fails("rollback refuses changed target") { _ = try MigrationStore.restore(receipt,root:root) }
        let noOp = try MigrationStore.prepare(target:target,before:original,after:original,added:0,root:root)
        let noChange = try MigrationStore.commitPlan(noOp,root:root)
        try check(noChange.state == "unchanged" && (try Data(contentsOf:target)) == original,"zero addition plan commits without changing dictionary")
        let wrongCount = MigrationReceipt(id:noOp.id,createdAt:noOp.createdAt,target:noOp.target,beforeHash:noOp.beforeHash,afterHash:noOp.afterHash,added:9,state:"prepared")
        try fails("plan count mismatch refused") { _ = try MigrationStore.checkedPlan(wrongCount,root:root) }
        let link = dir.appendingPathComponent("linked.dat")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        try fails("symlink target blocked") { try MigrationStore.replace(target:link,expected:receipt.beforeHash,replacement:merged.data) }
        let corruptPlan = try MigrationStore.prepare(target:target,before:original,after:merged.data,added:2,root:root)
        let corruptReceipt = try MigrationStore.commitPlan(corruptPlan,root:root)
        let backup = root.appendingPathComponent(corruptReceipt.id).appendingPathComponent("before.dat")
        try Data("damaged".utf8).write(to:backup)
        try fails("corrupt backup blocked for installed receipt") { _ = try MigrationStore.restore(corruptReceipt,root:root) }
        try check(try Data(contentsOf:target) == merged.data,"damaged backup refusal preserves installed target")
        try original.write(to:target) // Reset this synthetic target for the interruption cases.

        // A crash or disk-full error between target replacement and final receipt save.
        let interrupted = try MigrationStore.prepare(target:target,before:original,after:merged.data,added:2,root:root)
        try fails("intent save failure prevents all target writes") {
            _ = try MigrationStore.commitPlan(interrupted,root:root,persist:{ _ in throw MigrationError("disk full") })
        }
        try check(try Data(contentsOf:target) == original,"failed intent leaves original intact")
        var intent = interrupted; intent.state = "installing"; try MigrationStore.save(intent,root:root)
        try check(try MigrationStore.load(id:intent.id,root:root).state == "prepared","interruption before rename is safely retryable")
        try fails("final installation receipt failure reported") {
            _ = try MigrationStore.commitPlan(interrupted,root:root,persist:{ r in
                if r.state == "installed" { throw MigrationError("disk full") }
                try MigrationStore.save(r,root:root)
            })
        }
        let recovered = try MigrationStore.load(id:interrupted.id,root:root)
        try check(recovered.state == "installed" && (try Data(contentsOf:target)) == merged.data,"interrupted installation remains discoverable and restorable")
        try check(MigrationStore.receipts(in:root).contains { $0.id == recovered.id && $0.state == "installed" },"history reconciles interrupted installation")
        try fails("final restore receipt failure reported") {
            _ = try MigrationStore.restore(recovered,root:root,persist:{ r in
                if r.state == "restored" { throw MigrationError("disk full") }
                try MigrationStore.save(r,root:root)
            })
        }
        try check(try MigrationStore.load(id:recovered.id,root:root).state == "restored","interrupted restore recognized from exact original bytes")
        try check(try Data(contentsOf:target) == original,"restore survives final record failure")
        try Data("external change".utf8).write(to:target)
        try check(try MigrationStore.load(id:recovered.id,root:root).state == "interrupted","changed target never guessed as installed or restored")
        try fails("interrupted changed target cannot be overwritten") { _ = try MigrationStore.restore(recovered,root:root) }
        try check(try String(contentsOf:target,encoding:.utf8) == "external change","interrupted recovery preserves external changes")
        try original.write(to:target)

        let mixed = entries + [Entry(word:"待适配示例",syllables:["invalid-syllable"],sourceValue:3,source:"synthetic")]
        let selection = DoubaoMerge.select(mixed,mapping:mapping)
        try check(selection.accepted == entries && selection.rejected.map(\.index) == [5],"partition keeps source order and unsupported row")
        let sourceBytes = try Lexicon.archive(mixed)
        let partial = try MigrationStore.prepare(target:target,before:original,after:merged.data,added:2,source:MigrationSource(data:sourceBytes,entries:mixed,rejected:selection.rejected,existing:2),root:root)
        try fails("partial installation requires explicit opt-in") { _ = try MigrationStore.commitPlan(partial,root:root) }
        try check(try Data(contentsOf:target) == original,"refused partial plan leaves target unchanged")
        let partialDir = root.appendingPathComponent(partial.id)
        try check(try Data(contentsOf:partialDir.appendingPathComponent("source.original")) == sourceBytes,"partial plan preserves source bytes")
        try check(try Formats.read(Lexicon.boundedRead(partialDir.appendingPathComponent("source.json"))).entries == mixed,"partial plan preserves all original metadata")
        let rejected = try JSONDecoder().decode([RejectedEntry].self,from:Lexicon.boundedRead(partialDir.appendingPathComponent("unmigrated-reasons.json")))
        try check(rejected.count == 1 && rejected[0].entry == mixed.last!,"unmigrated archive is lossless")
        try check(try Formats.read(Lexicon.boundedRead(partialDir.appendingPathComponent("unmigrated.json"))).entries == [mixed.last!],"unmigrated archive can be reopened in file tools")
        var overflow = MigrationReceipt(id:partial.id,createdAt:partial.createdAt,target:partial.target,beforeHash:partial.beforeHash,afterHash:partial.afterHash,added:Int.max,state:"prepared")
        overflow.sourceCount = Int.max; overflow.existingCount = 1; overflow.rejectedCount = 0; overflow.sourceFiles = partial.sourceFiles
        try MigrationStore.save(overflow,root:root)
        try fails("decoded receipt count overflow refused without trap") {
            _ = try MigrationStore.checkedPlan(MigrationStore.load(id:partial.id,root:root),root:root)
        }
        var missingMetadata = partial; missingMetadata.sourceFiles = nil
        try MigrationStore.save(missingMetadata,root:root)
        try fails("incomplete source metadata refused before history display") { _ = try MigrationStore.load(id:partial.id,root:root) }
        try check(try Data(contentsOf:target) == original,"malformed receipt preserves target")
        try MigrationStore.save(partial,root:root)
        let partialInstalled = try MigrationStore.commitPlan(partial,root:root,allowPartial:true)
        try check(partialInstalled.skipped == 1 && partialInstalled.statusTitle == "部分迁移完成","partial completion never labeled full success")
        _ = try MigrationStore.restore(partialInstalled,root:root)
        try check(try Data(contentsOf:target) == original,"partial migration can be rolled back")
        let empty = DoubaoMerge.select([mixed.last!],mapping:mapping)
        let blocked = try MigrationStore.prepare(target:target,before:original,after:original,added:0,source:MigrationSource(data:sourceBytes,entries:[mixed.last!],rejected:empty.rejected,existing:0),root:root)
        try fails("all unsupported records cannot be installed") { _ = try MigrationStore.commitPlan(blocked,root:root,allowPartial:true) }
        let tampered = try MigrationStore.prepare(target:target,before:original,after:merged.data,added:2,source:MigrationSource(data:sourceBytes,entries:mixed,rejected:selection.rejected,existing:2),root:root)
        try Data("broken".utf8).write(to:root.appendingPathComponent(tampered.id).appendingPathComponent("unmigrated.json"))
        try fails("partial migration rejects damaged retained records") { _ = try MigrationStore.commitPlan(tampered,root:root,allowPartial:true) }
        let countBefore = MigrationStore.receipts(in:root).count
        try fails("invalid preparation rejected") { _ = try MigrationStore.prepare(target:target,before:original,after:merged.data,added:9,source:MigrationSource(data:sourceBytes,entries:mixed,rejected:selection.rejected,existing:2),root:root) }
        try check(MigrationStore.receipts(in:root).count == countBefore,"failed preparation leaves no incomplete receipt")
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path)
        try MigrationStore.privateFolder(root)
        try check(try FileManager.default.attributesOfItem(atPath:root.path)[.posixPermissions] as? Int == 0o700,"existing backup directory permissions tightened")
        let fakeID = UUID().uuidString
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent(fakeID),withDestinationURL:partialDir)
        try fails("linked transaction directory rejected") { _ = try MigrationStore.load(id:fakeID,root:root) }
        try check(MigrationStore.receipts(in:root).count == countBefore,"history ignores invalid transaction directory")
        try check(try FileManager.default.attributesOfItem(atPath:partialDir.appendingPathComponent("receipt.json").path)[.posixPermissions] as? Int == 0o600,"atomic receipt writes remain private")
    }
}
