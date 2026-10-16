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
let words=[line("太郎",0.16,0.37,0.20),line("こんばんは〜",0.16,0.44,0.45)]
for c:(UInt8,UInt8,UInt8) in [(210,20,160),(10,140,240),(0,0,0),(25,95,120)] {
 let result=analyzer.structuralMessages(in:image(true,c),lines:words)
 check("body extracted independently of bubble color \(c)",result.map{$0.text}==["こんばんは〜"])
}
check("square photo avatar accepted",analyzer.structuralMessages(in:image(true,square:true),lines:words).count==1)
check("bubble and username without image excluded",analyzer.structuralMessages(in:image(false),lines:words).isEmpty)
check("image and announcement without username excluded",analyzer.structuralMessages(in:image(),lines:[words[1]]).isEmpty)
check("username without body excluded",analyzer.structuralMessages(in:image(),lines:[words[0]]).isEmpty)
check("right seat texts excluded",analyzer.structuralMessages(in:image(),lines:[line("太郎",0.84,0.37),line("こんにちは",0.84,0.44)]).isEmpty)
check("input text excluded",analyzer.structuralMessages(in:image(),lines:words+[line("メッセージを送信",0.16,0.94)]).map{$0.text}==["こんばんは〜"])
let multi=words+[line("また来ます",0.16,0.475,0.3)]
check("multiline body joined without username",analyzer.structuralMessages(in:image(),lines:multi).first?.text=="こんばんは〜 また来ます")
// A real-looking name/image pair above a keyboard must not bless key text.
for tone:UInt8 in [55,250] {
 var keyboard=image();let w=keyboard.width,h=keyboard.height
 var bytes=keyboard.rgba
 func pixel(_ x:Int,_ y:Int,_ r:UInt8,_ g:UInt8,_ b:UInt8) {let p=(y*w+x)*4;bytes[p]=r;bytes[p+1]=g;bytes[p+2]=b}
 for y in 308..<336 {for x in 15..<43 {pixel(x,y,220,170,200)}}
 for row in 0..<3 {for col in 0..<9 {
  let x=Int((0.02+Double(col)*0.108)*Double(w)),y=Int((0.60+Double(row)*0.09)*Double(h))
  for dy in 0..<36 {for dx in 0..<27 {pixel(x+dx,y+dy,tone,tone,tone)}}
 }}
 keyboard=LayoutRaster(width:w,height:h,rgba:bytes)
 check("structural keyboard exclusion tone \(tone)",analyzer.structuralMessages(in:keyboard,lines:[line("太郎",0.16,0.55),line("あいうえお",0.16,0.64)]).isEmpty)
}
print("RESULT \(checks-failures)/\(checks) passed");exit(failures==0 ? 0:1)
