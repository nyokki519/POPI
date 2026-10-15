import AppKit
import CoreText
import CoreImage
import ImageIO
import Foundation
var failures=0
func check(_ name:String,_ condition:Bool) {print("\(condition ? "PASS":"FAIL") \(name)");if !condition {failures += 1;print("::error::"+name)}}
func room(width:Int,height:Int,withAvatar:Bool=true,comment:String="こんばんは",keyboard:Bool=false,three:Bool=false,tint:CGFloat=0.98)->CIImage {
    let color=CGColorSpaceCreateDeviceRGB()
    let cg=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:color,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w=CGFloat(width),h=CGFloat(height)
    func rect(_ x:CGFloat,_ y:CGFloat,_ rw:CGFloat,_ rh:CGFloat,_ color:CGColor) {cg.setFillColor(color);cg.fill(CGRect(x:x*w,y:(1-y-rh)*h,width:rw*w,height:rh*h))}
    func text(_ text:String,_ x:CGFloat,_ y:CGFloat) {
        let font=CTFontCreateWithName("HiraginoSans-W3" as CFString,w*0.041,nil)
        let attrs:[NSAttributedString.Key:Any]=[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:tint<0.5 ? 1:0,alpha:1)]
        let line=CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:attrs))
        cg.textPosition=CGPoint(x:x*w,y:(1-y)*h);CTLineDraw(line,cg)
    }
    rect(0,0,1,1,CGColor(red:0.10,green:0.38,blue:0.48,alpha:1))
    rect(0.16,0.42,0.55,comment.contains("\n") ? 0.14:0.075,CGColor(gray:tint,alpha:1))
    for (index,line) in comment.components(separatedBy:"\n").enumerated() {text(line,0.185,0.468+CGFloat(index)*0.035)}
    if withAvatar {cg.setFillColor(CGColor(red:0.86,green:0.67,blue:0.78,alpha:1));cg.fillEllipse(in:CGRect(x:0.047*w,y:(1-0.395)*h-0.043*w,width:0.086*w,height:0.086*w))}
    rect(0.025,0.28,0.60,0.075,CGColor(gray:0.98,alpha:1));text("公式アナウンス",0.045,0.33)
    rect(0.025,0.90,0.45,0.055,CGColor(gray:0.98,alpha:1));text("メッセージを送信",0.045,0.94)
    if keyboard {
        for row in 0..<3 {for col in 0..<9 {rect(0.02+CGFloat(col)*0.108,0.60+CGFloat(row)*0.09,0.085,0.065,CGColor(gray:0.98,alpha:1));text("あ",0.025+CGFloat(col)*0.108,0.645+CGFloat(row)*0.09)}}
    }
    if three {
        for (y,word) in [(CGFloat(0.58),"ありがとう"),(CGFloat(0.74),"よろしく")] {
            rect(0.16,y,0.55,0.075,CGColor(gray:y<0.7 ? tint:0.98,alpha:1))
            text(word,0.185,y+0.048)
            cg.setFillColor(CGColor(red:0.86,green:0.67,blue:0.78,alpha:1));cg.fillEllipse(in:CGRect(x:0.047*w,y:(1-y+0.025)*h-0.043*w,width:0.086*w,height:0.086*w))
        }
    }
    return CIImage(cgImage:cg.makeImage()!)
}
for (w,h) in [(750,1334),(1170,2532),(1290,2796)] {
 let processor=ChatFrameProcessor()
 let input=room(width:w,height:h)
 let first=try processor.process(input,orientation:.up)
 check("native OCR \(w)x\(h) includes comment only",first.messages?.map{$0.text.replacingOccurrences(of:" ",with:"")} == ["こんばんは"])
 check("native layout has one avatar-backed bubble",first.bubbles==1)
 let cached=try processor.process(input,orientation:.up)
 check("unchanged frame performs no new OCR",cached.recognitions==0 && cached.messages?.count==1)
 let changed=try processor.process(room(width:w,height:h,comment:"ありがとう"),orientation:.up)
 check("changed text invalidates cache",changed.recognitions==1 && changed.messages?.first?.text.replacingOccurrences(of:" ",with:"")=="ありがとう")
 let keyboard=try processor.process(room(width:w,height:h,keyboard:true),orientation:.up)
 check("native keyboard text excluded",keyboard.messages?.map{$0.text.replacingOccurrences(of:" ",with:"")} == ["こんばんは"])
}
let noAvatar=try ChatFrameProcessor().process(room(width:750,height:1334,withAvatar:false),orientation:.up)
check("native announcement without avatar excluded",noAvatar.messages?.isEmpty==true)
let animated=ChatFrameProcessor()
var completed=false
for i in 0..<4 {
    let frame=try animated.process(room(width:750,height:1334,three:true,tint:0.90+CGFloat(i)*0.025),orientation:.up)
    check("per-frame OCR limit remains two",frame.recognitions<=2)
    if let messages=frame.messages,messages.count==3 {completed=true}
}
check("animated upper bubbles cannot starve third message",completed)
let rotate=room(width:750,height:1334)
let rotated=try ChatFrameProcessor().process(rotate.oriented(forExifOrientation:8),orientation:.right)
check("rotated sample returns upright chat",rotated.messages?.first?.text.replacingOccurrences(of:" ",with:"")=="こんばんは")
for (message,expectedWords) in [("@しおちゃん おかえりー！",["しおちゃん","おかえり"]),("@ぱやみ 多分2人は\nおこちゃまなんだよ",["ぱやみ","おこちゃまなんだよ"])] {
 let sample=room(width:1170,height:2532,comment:message)
 let extracted=try ChatFrameProcessor().process(sample,orientation:.up)
 let body=normalizeComment(extracted.messages?.first?.text ?? "").replacingOccurrences(of:" ",with:"")
 print("::notice::Synthetic mention OCR bubbles=\(extracted.bubbles) count=\(extracted.messages?.count ?? -1) text=\(body)")
 check("mentioned user and message body retained: \(expectedWords[0])",expectedWords.allSatisfy{body.contains($0)})
}
for tint:CGFloat in [0.22,0.72] {
 let dark=try ChatFrameProcessor().process(room(width:750,height:1334,tint:tint),orientation:.up)
 check("gray bubble native OCR \(tint)",dark.messages?.first?.text.replacingOccurrences(of:" ",with:"")=="こんばんは")
 let noIcon=try ChatFrameProcessor().process(room(width:750,height:1334,withAvatar:false,tint:tint),orientation:.up)
 check("gray bubble without avatar is excluded \(tint)",noIcon.messages?.isEmpty==true)
}
print("Native Vision tests: \(failures==0 ? "PASS":"FAIL") — generated test images, not a GRAVITY recording")
exit(failures==0 ? 0:1)
