import Foundation
import CoreImage
import Vision
import ImageIO

struct ChatFrameResult {
    // nil means the bounded OCR budget has not completed this screen yet.
    let messages:[OCRLine]?
    let bubbles:Int
    let recognitions:Int
}

/// Runs synchronously during ReplayKit's sample callback. No video buffers escape.
final class ChatFrameProcessor {
    private let context=CIContext(options:[.cacheIntermediates:false])
    private let analyzer=ChatLayoutAnalyzer()
    private var cache:[UInt64:String]=[:]
    private var order:[UInt64]=[]
    func reset() {cache.removeAll();order.removeAll()}
    func process(_ source:CIImage,orientation:CGImagePropertyOrientation)throws->ChatFrameResult {
        let oriented=source.oriented(forExifOrientation:Int32(orientation.rawValue))
        let image=oriented.transformed(by:CGAffineTransform(translationX:-oriented.extent.minX,y:-oriented.extent.minY))
        let extent=image.extent
        guard extent.width>0,extent.height>0 else {return ChatFrameResult(messages:[],bubbles:0,recognitions:0)}
        let scale=min(1,640/max(extent.width,extent.height))
        let small=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        let tw=Int(small.extent.width),th=Int(small.extent.height)
        guard tw>=32,th>=32,let thumbnail=context.createCGImage(small,from:CGRect(x:0,y:0,width:tw,height:th)),
              let raster=Self.raster(thumbnail) else {return ChatFrameResult(messages:[],bubbles:0,recognitions:0)}
        let regions=analyzer.bubbles(in:raster)
        var messages:[OCRLine]=[],recognitions=0,pending=false
        for region in regions {
            let key=fingerprint(raster,region)
            let text:String
            if let cached=cache[key] {text=cached}
            else {
                // At most two fresh bubble recognitions per frame, no full-screen OCR.
                guard recognitions<2 else {pending=true;continue}
                let rect=CGRect(x:region.x*extent.width,y:(1-region.y-region.height)*extent.height,width:region.width*extent.width,height:region.height*extent.height).intersection(extent)
                let cropped=image.cropped(to:rect).transformed(by:CGAffineTransform(translationX:-rect.minX,y:-rect.minY))
                let downscale=min(1,800/max(rect.width,rect.height))
                let limited=cropped.transformed(by:CGAffineTransform(scaleX:downscale,y:downscale))
                guard let cg=context.createCGImage(limited,from:limited.extent) else {pending=true;continue}
                let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
                request.recognitionLanguages=["ja-JP","en-US"];request.usesLanguageCorrection=true
                try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request]);recognitions += 1
                let rows=(request.results ?? []).filter{($0.topCandidates(1).first?.confidence ?? 0)>=0.55}
                    .sorted{a,b in a.boundingBox.midY == b.boundingBox.midY ? a.boundingBox.minX<b.boundingBox.minX:a.boundingBox.midY>b.boundingBox.midY}
                text=rows.compactMap{$0.topCandidates(1).first?.string}.joined(separator:" ")
                cache[key]=text;order.append(key)
                if order.count>40 {cache.removeValue(forKey:order.removeFirst())}
            }
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {continue}
            messages.append(OCRLine(text:text,confidence:1,x:region.x,y:region.y,width:region.width,height:region.height))
        }
        return ChatFrameResult(messages:pending ? nil:messages,bubbles:regions.count,recognitions:recognitions)
    }
    private static func raster(_ image:CGImage)->LayoutRaster? {
        let w=image.width,h=image.height
        var bytes=Array(repeating:UInt8(0),count:w*h*4)
        let ok=bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let cg=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {return false}
            cg.draw(image,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        return ok ? LayoutRaster(width:w,height:h,rgba:bytes):nil
    }
    private func fingerprint(_ raster:LayoutRaster,_ r:ChatRegion)->UInt64 {
        let w=raster.width,h=raster.height
        let x=max(0,Int(r.x*Double(w))+2),y=max(0,Int(r.y*Double(h))+2)
        let endX=min(w,Int((r.x+r.width)*Double(w))-2),endY=min(h,Int((r.y+r.height)*Double(h))-2)
        var value:UInt64=14695981039346656037
        func mix(_ v:UInt64) {value=(value ^ v) &* 1099511628211}
        mix(UInt64(max(0,endX-x)));mix(UInt64(max(0,endY-y)))
        if x<endX,y<endY {
            for j in y..<endY {for i in x..<endX {let p=(j*w+i)*4
                for c in 0..<3 {mix(UInt64(raster.rgba[p+c]/16))}
            }}
        }
        return value
    }
}
