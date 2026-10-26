import Foundation
@main struct PreflightTests {
    static func main() throws {
        func check(_ value:Bool,_ name:String) { if !value { fatalError(name) } }
        check(!PreflightReport(sourceStatus:"",targetStatus:"",checks:[]).ready,"empty check cannot enable")
        let good = PreflightCheck(id:"ok",title:"",passed:true,detail:"")
        let bad = PreflightCheck(id:"bad",title:"",passed:false,detail:"")
        check(PreflightReport(sourceStatus:"",targetStatus:"",checks:[good]).ready,"all passed")
        check(!PreflightReport(sourceStatus:"",targetStatus:"",checks:[good,bad]).ready,"one failure blocks")
        let unsupported = Preflight.inspect(source:"搜狗输入法",target:"系统拼音",file:nil)
        check(!unsupported.ready,"unsupported route")
        check(unsupported.checks.contains { $0.id == "source-adapter" && $0.action == .file },"source guidance")
        check(unsupported.checks.contains { $0.id == "route" && $0.action == .advanced },"target guidance")
        let missing = Preflight.inspect(source:"搜狗输入法",target:"系统拼音",file:URL(fileURLWithPath:"/nonexistent/cidu-test.txt"))
        check(missing.checks.contains { $0.id == "source" && !$0.passed },"missing file blocks")
        // A known fixture ensures source-file checks are independent of the selected installed source.
        let fixture = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("fixtures/baidu-demo.txt")
        let report = Preflight.inspect(source:"搜狗输入法",target:"系统拼音",file:fixture)
        check(report.sourceStatus == "使用已导出文件","file source identity")
        check(!report.checks.contains { $0.id == "source-adapter" },"file bypasses auto adapter")
        check(report.checks.contains { $0.id == "source" && $0.passed },"valid file parsed")
        let permission = PreflightCheck(id:"permission",title:"",passed:false,detail:"")
        let firstRun = PreflightReport(sourceStatus:"",targetStatus:"",checks:[good,permission])
        check(firstRun.canBegin && firstRun.needsPermission && !firstRun.ready,"permission starts guided flow, never bypasses readiness")
        check(!PreflightReport(sourceStatus:"",targetStatus:"",checks:[]).canBegin,"empty cannot begin")
        check(!PreflightReport(sourceStatus:"",targetStatus:"",checks:[permission,bad]).canBegin,"permission does not bypass another failure")
        check(!PreflightReport(sourceStatus:"",targetStatus:"",checks:[good]).needsPermission,"no spurious permission flow")
        check(PreflightReport(sourceStatus:"",targetStatus:"",checks:[good]).canBegin,"ready begins")
        let automatic = Preflight.inspect(source:"百度输入法",target:"系统拼音",file:nil)
        check(!automatic.checks.contains { ["source-window","source-running"].contains($0.id) },"closed source settings never require manual preparation")
        check(!automatic.canBegin,"automatic preparation cannot bypass an unsupported target")
        print("PASS: 17 preflight gating and guidance checks")
    }
}
