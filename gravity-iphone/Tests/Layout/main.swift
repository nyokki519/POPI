import Foundation
var failures=0,checks=0
func check(_ name:String,_ value:Bool) {checks += 1;if !value {failures += 1};print("\(value ? "PASS":"FAIL") \(name)")}
// Synthetic raster fixture, not a substitute for live GRAVITY/device tests.
struct Canvas {
 let width:Int, height:Int
 var bytes:[UInt8]
 init(_ w:Int,_ h:Int) {width=w;height=h;bytes=Array(repeating:0,count:w*h*4)}
 mutating func pixel(_ x:Int,_ y:Int,_ color:(UInt8,UInt8,UInt8)) {
  guard x>=0,y>=0,x<width,y<height else{return};let p=(y*width+x)*4
  bytes[p]=color.0;bytes[p+1]=color.1;bytes[p+2]=color.2;bytes[p+3]=255
 }
 mutating func rect(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ c:(UInt8,UInt8,UInt8)) {
  for j in Int(y*Double(height))..<Int((y+h)*Double(height)) {for i in Int(x*Double(width))..<Int((x+w)*Double(width)) {pixel(i,j,c)}}
 }
 mutating func circle(_ x:Double,_ y:Double,_ radius:Double) {
  let cx=Int(x*Double(width)),cy=Int(y*Double(height)),r=Int(radius*Double(width))
  for j in -r...r {for i in -r...r where i*i+j*j<=r*r {pixel(cx+i,cy+j,(220,170,200))}}
 }
 var frame:LayoutRaster {LayoutRaster(width:width,height:height,rgba:bytes)}
}
func fixture(_ w:Int,_ h:Int,avatar:Bool=true)->Canvas {
 var c=Canvas(w,h);c.rect(0,0,1,1,(25,95,120))
 c.rect(0.16,0.42,0.46,0.065,(250,250,250))
 if avatar {c.circle(0.09,0.395,0.043)}
 c.rect(0.025,0.28,0.58,0.075,(250,250,250)) // official announcement
 c.rect(0.025,0.9,0.3,0.055,(250,250,250)) // input field
 c.circle(0.87,0.45,0.055) // speaker seat on right
 return c
}
let analyzer=ChatLayoutAnalyzer()
for (w,h) in [(240,440),(320,560),(280,600),(400,500)] {
 let found=analyzer.bubbles(in:fixture(w,h).frame)
 check("avatar-backed message only at \(w)x\(h)",found.count==1)
 if let b=found.first {check("body bounds are scale independent",abs(b.x-0.16)<0.015 && abs(b.y-0.42)<0.015)}
}
check("same bright rectangle without avatar is not speech",analyzer.bubbles(in:fixture(280,500,avatar:false).frame).isEmpty)
var keyboard=Canvas(280,500);keyboard.rect(0,0,1,1,(30,90,110))
for row in 0..<4 {for col in 0..<9 {keyboard.rect(0.02+Double(col)*0.108,0.6+Double(row)*0.09,0.085,0.065,(250,250,250))}}
check("keyboard keys are not comments",analyzer.bubbles(in:keyboard.frame).isEmpty)
var decorated=fixture(320,560)
decorated.rect(0.16,0.6,0.58,0.16,(240,248,255));decorated.circle(0.09,0.575,0.043)
check("multiline decorated-color bubble retained",analyzer.bubbles(in:decorated.frame).count==2)
var short=Canvas(320,560);short.rect(0,0,1,1,(25,95,120));short.circle(0.09,0.395,0.043);short.rect(0.16,0.42,0.115,0.055,(250,250,250))
check("short one-character sized bubble retained",analyzer.bubbles(in:short.frame).count==1)
var raisedKeyboard=Canvas(320,560);raisedKeyboard.rect(0,0,1,1,(25,95,120));raisedKeyboard.circle(0.09,0.575,0.043)
for row in 0..<3 {for col in 0..<9 {raisedKeyboard.rect(0.02+Double(col)*0.108,0.60+Double(row)*0.09,0.085,0.065,(250,250,250))}}
check("keyboard below an old avatar still excluded",analyzer.bubbles(in:raisedKeyboard.frame).isEmpty)
var wideKeyboard=Canvas(400,500);wideKeyboard.rect(0,0,1,1,(25,95,120));wideKeyboard.circle(0.09,0.575,0.043)
for row in 0..<3 {for col in 0..<9 {wideKeyboard.rect(0.02+Double(col)*0.108,0.60+Double(row)*0.09,0.085,0.065,(250,250,250))}}
check("wide viewport keyboard beside old avatar excluded",analyzer.bubbles(in:wideKeyboard.frame).isEmpty)
check("invalid byte count is rejected",analyzer.bubbles(in:LayoutRaster(width:10,height:10,rgba:[])).isEmpty)
var policy=RecognitionBudget()
check("first frame allowed",policy.shouldProcess(now:0,thermal:0))
check("ordinary 30fps callback skipped",!policy.shouldProcess(now:0.03,thermal:0))
policy.record(duration:0.8)
check("expensive OCR creates cooldown",!policy.shouldProcess(now:1.3,thermal:0))
check("cooldown eventually allows frame",policy.shouldProcess(now:3,thermal:0))
check("critical thermal state pauses recognition",!policy.shouldProcess(now:30,thermal:3))
print("RESULT \(checks-failures)/\(checks) passed")
exit(failures==0 ? 0:1)
