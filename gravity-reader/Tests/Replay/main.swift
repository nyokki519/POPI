import Foundation
let detector=CommentDetector()
var queue=FreshSpeechQueue()
var received:[String]=[]
let snapshots=[
 ["花子:こんにちは","太郎:こんばんは"],
 ["花子:こんにちは","太郎:こんばんは","次郎:読み上げのテストです"],
 ["太郎:こんばんは","次郎:読み上げのテストです","花子:日本語のコメントです"],
 ["次郎:読み上げのテストです","花子:日本語のコメントです","太郎:同じ文章も追加できます"],
 ["花子:日本語のコメントです","太郎:同じ文章も追加できます","太郎:同じ文章も追加できます"]
]
let started=ProcessInfo.processInfo.systemUptime
for i in 0..<24 {
 let time=Double(i)*0.5
 let text=snapshots[min(i/4,snapshots.count-1)]
 let lines=text.enumerated().map{OCRLine(text:$0.element,confidence:0.99,x:0,y:Double($0.offset)*0.15,width:1,height:0.08)}
 for comment in detector.ingest(lines) {queue.enqueue(comment,now:time)}
 while let comment=queue.pop(now:time) {received.append(comment)}
}
let expected=["次郎:読み上げのテストです","花子:日本語のコメントです","太郎:同じ文章も追加できます","太郎:同じ文章も追加できます"]
precondition(received==expected,"simulated OCR -> detector -> queue did not preserve new comment sequence")
let elapsed=(ProcessInfo.processInfo.systemUptime-started)*1000
let result:[String:Any]=["status":"PASS","frames":24,"received":received,"core_elapsed_ms":elapsed,"scope":"Simulated OCR rows -> real Swift detector -> real queue; no native screen OCR or speech hardware"]
let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
print(String(data:data,encoding:.utf8)!)
