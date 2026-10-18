import Foundation

/// Coordinates are normalized, with y measured from the top of the crop.
struct OCRLine {
    let text: String
    let confidence: Double
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

func normalizeComment(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping
        .folding(options: [.widthInsensitive], locale: Locale(identifier: "ja_JP"))
        .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

final class CommentDetector {
    private var previous: [String]?
    private var candidate: [String] = []
    private var counts: [Int] = []
    private let recallMode:Bool
    private let liveMode:Bool
    private var recent:[(String,Double)]=[]
    private let filterSystemLabels:Bool
    private let ignoreWords: [String]
    private let systemPattern = try! NSRegularExpression(pattern:
        "^(?:.+(?:が入室しました|が退出しました|が参加しました|が退室しました)|[0-9]{1,2}:[0-9]{2})$")
    private let systemLabels: Set<String> = ["コメントを入力", "コメントする", "メッセージを入力", "送信", "GRAVITY"]

    init(ignoreWords: [String] = [], filterSystemLabels:Bool=true,liveMode:Bool=false,recallMode:Bool=false) {
        self.recallMode=recallMode
        self.liveMode=liveMode
        self.filterSystemLabels=filterSystemLabels
        self.ignoreWords = ignoreWords.map(normalizeComment).filter { !$0.isEmpty }
    }

    func reset() {
        previous = nil; candidate = []; counts = []; recent=[]
    }

    private func isSystem(_ text: String) -> Bool {
        ignoreWords.contains(where:text.contains) || (filterSystemLabels && (systemLabels.contains(text) ||
            systemPattern.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) != nil))
    }

    /// One edit in a sufficiently long line tolerates a flickering OCR glyph.
    /// Short messages and different repeated occurrences remain distinct.
    private func equivalent(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if recallMode {return false}
        let x = Array(a), y = Array(b)
        guard min(x.count,y.count) >= 8, abs(x.count-y.count) <= 1 else { return false }
        var i=0, j=0, edits=0
        while i<x.count && j<y.count {
            if x[i] == y[j] { i += 1; j += 1; continue }
            edits += 1
            if edits>1 { return false }
            if x.count >= y.count { i += 1 }
            if y.count >= x.count { j += 1 }
        }
        return edits + (x.count-i) + (y.count-j) <= 1
    }

    private func sameScreen(_ a: [String], _ b: [String]) -> Bool {
        a.count == b.count && zip(a,b).allSatisfy { equivalent($0.0,$0.1) }
    }

    func ingest(_ lines: [OCRLine],now:Double=ProcessInfo.processInfo.systemUptime) -> [String] {
        let sorted = lines.filter { $0.confidence >= (recallMode ? 0.2:0.55) }
            .sorted { $0.y == $1.y ? $0.x<$1.x : $0.y<$1.y }
        // Keep OCR rows explicit: do not guess usernames or merge two comments.
        let screen = Array(sorted.map { String(normalizeComment($0.text).prefix(recallMode ? 2000:1000)) }
            .filter { !$0.isEmpty && !isSystem($0) }.suffix(60))
        guard !screen.isEmpty else { candidate=[]; counts=[]; return [] }
        recent.removeAll {now-$0.1>20}
        guard let old=previous else {
            if recallMode {previous=screen;remember(screen,now:now);return screen}
            if liveMode {return confirmLatest(screen,now:now)}
            previous=screen; return []
        }
        if sameScreen(old,screen) { previous=screen;candidate=[];counts=[];return [] }
        // LCS preserves occurrence counts. Only suffix after last overlap is new.
        var dp=Array(repeating:Array(repeating:0,count:screen.count+1),count:old.count+1)
        for i in stride(from:old.count-1,through:0,by:-1) {
            for j in stride(from:screen.count-1,through:0,by:-1) {
                dp[i][j] = equivalent(old[i],screen[j]) ? 1+dp[i+1][j+1] : max(dp[i+1][j],dp[i][j+1])
            }
        }
        guard dp[0][0]>0 else {
            if recallMode {
                let unseen=screen.filter {text in !recent.contains(where:{equivalent($0.0,text)})}
                previous=screen;remember(screen,now:now);return unseen
            }
            if liveMode {return confirmLatest(screen,now:now)}
            previous=screen;candidate=[];counts=[];return []
        } // No overlap: rebase rather than replay old history.
        var i=0, j=0, lastMatch = -1
        var matched=Set<Int>()
        while i<old.count && j<screen.count {
            if equivalent(old[i],screen[j]) { lastMatch=j; matched.insert(j); i += 1; j += 1 }
            else if dp[i+1][j]>=dp[i][j+1] { i += 1 } else { j += 1 }
        }
        let fresh=Array(screen.dropFirst(lastMatch+1))
        if recallMode {
            let unread=screen.indices.filter {!matched.contains($0)}.map{screen[$0]}
            previous=screen;remember(screen,now:now);return unread
        }
        var used=Set<Int>()
        let newCounts=fresh.map { text -> Int in
            if let index=candidate.indices.first(where:{!used.contains($0) && equivalent(candidate[$0],text)}) {
                used.insert(index);return counts[index]+1
            }
            return 1
        }
        let confirmed=Array(fresh.indices.prefix(while:{newCounts[$0]>=2}))
        if let last=confirmed.last {
            previous=Array(screen.prefix(lastMatch+last+2))
            candidate=Array(fresh.dropFirst(last+1));counts=Array(newCounts.dropFirst(last+1))
            let spoken=confirmed.map{fresh[$0]}
            if liveMode {remember(screen,now:now)}
            return spoken
        }
        candidate=fresh;counts=newCounts;return []
    }
    private func remember(_ screen:[String],now:Double) {
        for text in screen {
            recent.removeAll {equivalent($0.0,text)}
            recent.append((text,now))
        }
        recent=Array(recent.suffix(80))
    }
    private func confirmLatest(_ screen:[String],now:Double)->[String] {
        guard let latest=screen.last else {return []}
        if recent.contains(where:{equivalent($0.0,latest)}) {
            previous=screen;candidate=[];counts=[];return []
        }
        if candidate.last.map({equivalent($0,latest)}) == true {
            previous=screen;candidate=[];counts=[];remember(screen,now:now)
            return [latest]
        }
        candidate=[latest];counts=[1];return []
    }

}

struct FreshSpeechQueue {
    private struct Entry { let text:String; let time:Double }
    private var entries: [Entry] = []
    let capacity: Int
    let maxAge: Double
    let maxCharacters: Int
    private(set) var dropped = 0
    var count: Int { entries.count }

    init(capacity:Int=8,maxAge:Double=10,maxCharacters:Int=120) {
        self.capacity=max(1,capacity); self.maxAge=max(0,maxAge); self.maxCharacters=max(1,maxCharacters)
    }
    mutating func enqueue(_ text:String,now:Double) {
        let clean=normalizeComment(text)
        guard !clean.isEmpty else { return }
        expire(now:now)
        if entries.count>=capacity { entries.removeFirst(); dropped += 1 }
        let spoken=clean.count>maxCharacters ? String(clean.prefix(maxCharacters))+"…" : clean
        entries.append(Entry(text:spoken,time:now))
    }
    private mutating func expire(now:Double) {
        let expired=entries.prefix { now-$0.time>maxAge }.count
        if expired>0 { entries.removeFirst(expired); dropped += expired }
    }
    mutating func pop(now:Double)->String? {
        expire(now:now)
        return entries.isEmpty ? nil : entries.removeFirst().text
    }
    mutating func clear() { entries.removeAll() }
}

struct SessionGeneration {
 private var value=0
 mutating func next()->Int {value += 1;return value}
 func isCurrent(_ token:Int)->Bool {token==value}
}
