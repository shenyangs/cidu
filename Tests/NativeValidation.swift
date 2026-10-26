import Foundation
@main struct NativeValidation {
 static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("cidu-native-"+UUID().uuidString)
  try MigrationStore.privateFolder(root); defer { try? FileManager.default.removeItem(at:root) }
  let helper = URL(fileURLWithPath:CommandLine.arguments[1])
  func probe(_ args:[String]) throws { let p=Process(); p.executableURL=helper; p.arguments=args; p.standardOutput=FileHandle.nullDevice; p.standardError=FileHandle.standardError; try p.run(); p.waitUntilExit(); guard p.terminationStatus==0 else { throw MigrationError("probe failed status \(p.terminationStatus)") } }
  let paths=Lexicon.discoverDoubao(); guard paths.count==1 else { throw MigrationError("ambiguous target") }
  let original=try Lexicon.boundedRead(paths[0]), digest=Compatibility.hash(original)
  let keys=root.appendingPathComponent("keys.json"), mapped=root.appendingPathComponent("mapped.json")
  try Lexicon.saveNew(JSONEncoder().encode(["ci","du","yan","zheng"]),at:keys)
  try probe(["map",keys.path,mapped.path])
  let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:mapped)) as! [String:[NSNumber]]
  var mapping=[String:Int](); for (k,v) in raw where v[0].boolValue { mapping[k]=v[1].intValue }
  let entries=try Lexicon.parseBaidu(Data("词渡验证词渡(ci|du|yan|zheng|ci|du) 1".utf8))
  let merged=try DoubaoMerge.build(original,entries:entries,mapping:mapping)
  for (name,data) in [("before",original),("after",merged.data)] { let d=root.appendingPathComponent(name); try MigrationStore.privateFolder(d); try Lexicon.saveNew(data,at:d.appendingPathComponent("usr.dat")); try probe(["cpp",d.path,root.appendingPathComponent(name+".count").path]) }
  let a=Int(try String(contentsOf:root.appendingPathComponent("before.count"),encoding:.utf8))!, b=Int(try String(contentsOf:root.appendingPathComponent("after.count"),encoding:.utf8))!
  guard try Data(contentsOf:root.appendingPathComponent("before.count.errors")) == Data(contentsOf:root.appendingPathComponent("after.count.errors")), b-a==merged.added, Compatibility.hash(try Lexicon.boundedRead(paths[0]))==digest else { throw MigrationError("verification failed") }
  print("PASS isolated native load/count delta; live dictionary unchanged")
 }
}
