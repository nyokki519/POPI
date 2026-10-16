import Foundation
var failures=0,checks=0
func check(_ name:String,_ value:Bool) {checks += 1;if !value {failures += 1};print("\(value ? "PASS":"FAIL") \(name)")}
func line(_ text:String,_ x:Double,_ y:Double,_ width:Double=0.3)->OCRLine {OCRLine(text:text,confidence:0.9,x:x,y:y,width:width,height:0.025)}
func image(_ avatar:Bool=true,_ color:(UInt8,UInt8,UInt8)=(210,20,160),square:Bool=false)->LayoutRaster {
 let w=320,h=560;var bytes=Array(repeating:UInt8(0),count:w*h*4)
 for y in 0..<h {for x in 0..<w {
  var c:(UInt8,UInt8,UInt8)=(25,95,120)
  if x>=51,x<240,y>=235,y<300 {c=color}
  let dx=x-29,dy=y-221
  if avatar,(square ? abs(dx)<14 && abs(dy)<14:dx*dx+dy*dy<196) {c=(UInt8(120+(x%3)*40),160,220)}
  let p=(y*w+x)*4;bytes[p]=c.0;bytes[p+1]=c.1;bytes[p+2]=c.2;bytes[p+3]=255
 }}
 return LayoutRaster(width:w,height:h,rgba:bytes)
}
let analyzer=ChatLayoutAnalyzer()
let body=line("こんばんは〜",0.16,0.44,0.45)
func name(_ confidence:Double=0.9,_ height:Double=0.025)->OCRLine {
 OCRLine(text:"太郎",confidence:confidence,x:0.16,y:0.37,width:0.2,height:height)
}
let cases:[(String,[OCRLine],Int)]=[
 ("name_and_body",[name(),body],1),
 ("name_not_recognized",[body],0),
 ("name_confidence_019",[name(0.19),body],0),
 ("name_confidence_020",[name(0.20),body],1),
 ("name_box_height_006",[name(0.9,0.06),body],0),
 ("body_reaches_right_081",[name(),line("こんばんは〜",0.16,0.44,0.65)],0)
]
var geometry:[[String:Any]]=[]
for (label,rows,expected) in cases {
 let found=analyzer.structuralMessages(in:image(),lines:rows)
 precondition(found.count==expected)
 geometry.append(["case":label,"recognized_body_rows":1,"matched_messages":found.count])
}
func messages(_ values:[String])->[OCRLine] {values.enumerated().map { index,text in OCRLine(text:text,confidence:1,x:0.16,y:0.3+Double(index)*0.1,width:0.4,height:0.03)}}
func trace(_ frames:[[String]])->[[String]] {
 let detector=CommentDetector(filterSystemLabels:false)
 return frames.map {detector.ingest(messages($0))}
}
let sequential=trace([["BASE"],["BASE","こんにちは"],["BASE","こんにちは"]])
let replaced=trace([["こんにちは"],["こんばんは"],["こんばんは"],["またね"],["またね"]])
let firstAfterEmpty=trace([[],[],["こんばんは"],["こんばんは"]])
precondition(sequential.flatMap{$0}==["こんにちは"])
precondition(replaced.flatMap{$0}.isEmpty && firstAfterEmpty.flatMap{$0}.isEmpty)
var queue=FreshSpeechQueue(capacity:6,maxAge:8,maxCharacters:120)
queue.enqueue("こんばんは",now:0)
let expired=queue.pop(now:9)==nil
let record:[String:Any]=["scope":"Executed production Swift logic with synthetic OCR rows; not actual GRAVITY or iPhone audio","geometry":geometry,"detector":["appended_frames":sequential,"all_visible_text_replaced":replaced,"first_arrival_after_empty":firstAfterEmpty],"expired_after_9_seconds":expired]
let data=try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys])
print(String(data:data,encoding:.utf8)!)
