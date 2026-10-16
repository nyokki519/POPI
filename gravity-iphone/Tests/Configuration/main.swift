import Foundation
let defaults=ReaderConfiguration()
precondition(defaults.top == 0.45 && defaults.bottom == 0.9 && defaults.rate == 0.5)
let reversed=ReaderConfiguration(["top":NSNumber(value:0.7),"bottom":NSNumber(value:0.1),"rate":NSNumber(value:2)])
precondition(abs(reversed.bottom-0.8)<0.00001 && reversed.rate==0.6)
let invalid=ReaderConfiguration(["top":NSNumber(value:Double.nan),"bottom":NSNumber(value:Double.infinity)])
precondition(invalid.top==defaults.top && invalid.bottom==defaults.bottom)
let outside=ReaderConfiguration(["top":NSNumber(value:-10),"bottom":NSNumber(value:2),"rate":NSNumber(value:-1)])
precondition(outside.top==0 && outside.bottom==1 && outside.rate==0.35)
print("PASS configuration defaults, reversed boundaries, nonfinite values and limits")
let app=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Reader.app")
let plugin=app.appendingPathComponent("PlugIns/Upload.appex")
try FileManager.default.createDirectory(at:plugin,withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:app.deletingLastPathComponent())}
for identifier in ["jp.nyokki519.GravityReader.Upload","jp.nyokki519.GravityReader.Upload.TEAM123"] {
 let info:[String:Any]=["CFBundleIdentifier":identifier,"NSExtension":["NSExtensionPointIdentifier":"com.apple.broadcast-services-upload"]]
 try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:plugin.appendingPathComponent("Info.plist"))
 precondition(bundledUploadIdentifier(applicationURL:app)==identifier,"Must discover actual signed extension identifier")
}
precondition(bundledUploadIdentifier(applicationURL:app.appendingPathComponent("missing"))==nil)
print("PASS original and re-signed upload extension discovery; missing bundle rejected")
