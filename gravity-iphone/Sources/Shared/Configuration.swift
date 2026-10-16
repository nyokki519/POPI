import Foundation
struct ReaderConfiguration {
    let top:Double
    let bottom:Double
    let rate:Double
    init(_ info:[String:NSObject]? = nil) {
        func number(_ key:String,_ fallback:Double)->Double {
            guard let n=info?[key] as? NSNumber,n.doubleValue.isFinite else {return fallback}
            return n.doubleValue
        }
        top=min(0.8,max(0,number("top",0.45)))
        bottom=min(1,max(top+0.1,number("bottom",0.9)))
        rate=min(0.6,max(0.35,number("rate",0.5)))
    }
}

// Re-signers may rewrite host and extension identifiers differently. Read the
// installed upload extension instead of guessing hostID + ".Upload".
func bundledUploadIdentifier(applicationURL:URL)->String? {
    let directory=applicationURL.appendingPathComponent("PlugIns",isDirectory:true)
    guard let urls=try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) else {return nil}
    for url in urls.sorted(by:{$0.lastPathComponent<$1.lastPathComponent}) where url.pathExtension=="appex" {
        guard let data=try? Data(contentsOf:url.appendingPathComponent("Info.plist")),
            let info=(try? PropertyListSerialization.propertyList(from:data,options:[],format:nil)) as? [String:Any],
            let settings=info["NSExtension"] as? [String:Any],
            settings["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload",
            let identifier=info["CFBundleIdentifier"] as? String,!identifier.isEmpty,!identifier.contains("$(") else {continue}
        return identifier
    }
    return nil
}
