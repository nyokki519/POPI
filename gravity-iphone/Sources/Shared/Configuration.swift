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
