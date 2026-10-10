import Foundation
var failures=0; var tests=0
func check(_ name:String,_ condition: @autoclosure ()->Bool) {
 tests += 1
 if condition() { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
}
func lines(_ text:[String]) -> [OCRLine] {
 text.enumerated().map { OCRLine(text:$0.element,confidence:0.95,x:0.05,y:Double($0.offset)*0.15,width:0.8,height:0.06) }
}
func settle(_ detector:CommentDetector,_ text:[String])->[String] {
 _ = detector.ingest(lines(text));return detector.ingest(lines(text))
}
let detector=CommentDetector()
check("startup screen is baseline only",settle(detector,["花子:こんにちは","太郎:こんばんは"]).isEmpty)
check("new comment waits for confirmation",detector.ingest(lines(["花子:こんにちは","太郎:こんばんは","次郎:よろしく"])).isEmpty)
check("confirmed appended comment",detector.ingest(lines(["花子:こんにちは","太郎:こんばんは","次郎:よろしく"])) == ["次郎:よろしく"])
check("same visible screen does not replay",settle(detector,["花子:こんにちは","太郎:こんばんは","次郎:よろしく"]).isEmpty)
check("scroll preserves overlap",settle(detector,["太郎:こんばんは","次郎:よろしく","四郎:ありがとう"]) == ["四郎:ありがとう"])
check("new repeated occurrence speaks",settle(detector,["次郎:よろしく","四郎:ありがとう","四郎:ありがとう"]) == ["四郎:ありがとう"])
check("no overlap rebases without replay",settle(detector,["全く違う画面です","別の内容です"]).isEmpty)
detector.reset()
check("reset prevents backlog replay",settle(detector,["再開前の古いコメント"]).isEmpty)
let transient=CommentDetector();_ = settle(transient,["最初の表示です"])
_ = transient.ingest(lines(["最初の表示です","一瞬だけの誤認識です"]))
check("transient OCR does not speak",settle(transient,["最初の表示です"]).isEmpty)
let system=CommentDetector();_ = settle(system,["基準コメント"])
check("system events excluded",settle(system,["基準コメント","花子が入室しました","コメントを入力"]).isEmpty)
check("Japanese normal comment is retained",settle(system,["基準コメント","花子が入室しました","コメントを入力","今日はいい天気ですね"]) == ["今日はいい天気ですね"])
let uncertain=CommentDetector();_ = settle(uncertain,["初期コメント"])
let weak=[OCRLine(text:"低信頼度の誤読",confidence:0.1,x:0,y:0,width:1,height:0.1)]
_ = uncertain.ingest(weak)
check("low confidence filtered",uncertain.ingest(weak).isEmpty)
check("width and whitespace normalization",normalizeComment(" ＡＢＣ　こんにちは  ") == "ABC こんにちは")
let jitter=CommentDetector();_ = settle(jitter,["長いコメントの文章です"])
check("single OCR typo does not become new comment",settle(jitter,["長いコメントの文草です"]).isEmpty)
var q=FreshSpeechQueue(capacity:2,maxAge:10,maxCharacters:5)
q.enqueue("abcdef",now:0);q.enqueue("second",now:1);q.enqueue("third",now:2)
check("queue capacity drops oldest",q.count==2 && q.dropped==1)
check("queue truncates long comment",q.pop(now:2)=="secon…")
check("queue retains chronological order",q.pop(now:2)=="third")
q.enqueue("old",now:3)
check("stale speech is discarded",q.pop(now:14)==nil)
q.enqueue("fresh",now:20)
check("age boundary is accepted",q.pop(now:30)=="fresh")
q.enqueue("clear",now:40);q.clear()
check("clear cancels pending speech",q.count==0 && q.pop(now:40)==nil)
let excluded=CommentDetector(ignoreWords:["NGワード"]);_ = settle(excluded,["普通の文章"])
check("custom ignore phrase",settle(excluded,["普通の文章","NGワード入りコメント"]).isEmpty)
let rapid=CommentDetector();_ = settle(rapid,["初期A","初期B"])
check("rapid first appearance waits",rapid.ingest(lines(["初期A","初期B","新規C"])).isEmpty)
check("rapid incoming comments still confirm C",rapid.ingest(lines(["初期B","新規C","新規D"])) == ["新規C"])
check("rapid incoming comments still confirm D",rapid.ingest(lines(["新規C","新規D","新規E"])) == ["新規D"])
let correction=CommentDetector();_ = settle(correction,["BASE"])
_ = correction.ingest(lines(["BASE","XXXX","YYYY"]))
check("unresolved prefix waits instead of being swallowed",correction.ingest(lines(["BASE","ZZZZ","YYYY"])).isEmpty)
check("corrected prefix and later comment both survive",correction.ingest(lines(["BASE","ZZZZ","YYYY"])) == ["ZZZZ","YYYY"])
var session=SessionGeneration()
let oldPreparation=session.next();let newerPreparation=session.next()
check("new prepare invalidates old request",!session.isCurrent(oldPreparation))
check("new prepare can commit",session.isCurrent(newerPreparation))
_ = session.next()
check("cancel invalidates in-flight preparation",!session.isCurrent(newerPreparation))
let tight=CommentDetector();_ = settle(tight,["BASE"])
let dense=[OCRLine(text:"BASE",confidence:1,x:0,y:0,width:1,height:0.003),OCRLine(text:"A",confidence:1,x:0.9,y:0.005,width:0.1,height:0.003),OCRLine(text:"B",confidence:1,x:0.1,y:0.012,width:0.1,height:0.003),OCRLine(text:"C",confidence:1,x:0.8,y:0.019,width:0.1,height:0.003)]
_ = tight.ingest(dense)
check("densely spaced rows preserve top to bottom order",tight.ingest(dense)==["A","B","C"])
print("RESULT \(tests-failures)/\(tests) passed")
exit(failures==0 ? 0:1)
