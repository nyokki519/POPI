import Foundation
import CoreImage
import Vision
import ImageIO

struct ChatFrameResult {
    // nil means the bounded OCR budget has not completed this snapshot yet.
    let messages:[OCRLine]?
    let bubbles:Int
    let recognitions:Int
    let capturedAt:Double
}

/// ReplayKit buffers never escape. A multi-bubble batch owns bounded bitmap copies
/// of one snapshot, so changing upper decorations cannot restart lower OCR work.
final class ChatFrameProcessor {
    private struct PendingBubble {
        let region:ChatRegion
        let key:UInt64
        var image:CGImage?
        var text:String?
    }
    private let context=CIContext(options:[.cacheIntermediates:false])
    private let analyzer=ChatLayoutAnalyzer()
    private var cache:[UInt64:String]=[:]
    private var order:[UInt64]=[]
    private var pending:[PendingBubble]?
    private var capturedAt=0.0
    func reset() {cache.removeAll();order.removeAll();pending=nil}
    func process(_ source:CIImage,orientation:CGImagePropertyOrientation)throws->ChatFrameResult {
        let now=ProcessInfo.processInfo.systemUptime
        // Do not finish old snapshots after a long pause or thermal interruption.
        if pending != nil,now-capturedAt>6 {pending=nil}
        if pending==nil {
            capturedAt=now
            let oriented=source.oriented(forExifOrientation:Int32(orientation.rawValue))
            let image=oriented.transformed(by:CGAffineTransform(translationX:-oriented.extent.minX,y:-oriented.extent.minY))
            let extent=image.extent
            guard extent.width>0,extent.height>0 else {return result([],0,0)}
            let scale=min(1,640/max(extent.width,extent.height))
            let small=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            let tw=Int(small.extent.width),th=Int(small.extent.height)
            guard tw>=32,th>=32,let thumbnail=context.createCGImage(small,from:CGRect(x:0,y:0,width:tw,height:th)),
                  let raster=Self.raster(thumbnail) else {return result([],0,0)}
            let regions=analyzer.bubbles(in:raster)
            var batch:[PendingBubble]=[]
            // <=10 copied crops, <=150,000 pixels each (~6MB RGBA total).
            for region in regions {
                let key=fingerprint(raster,region)
                if let text=cache[key] {batch.append(PendingBubble(region:region,key:key,image:nil,text:text));continue}
                let rect=CGRect(x:region.x*extent.width,y:(1-region.y-region.height)*extent.height,width:region.width*extent.width,height:region.height*extent.height).intersection(extent)
                guard rect.width>0,rect.height>0 else {continue}
                let cropped=image.cropped(to:rect).transformed(by:CGAffineTransform(translationX:-rect.minX,y:-rect.minY))
                let downscale=min(1,800/max(rect.width,rect.height),sqrt(150_000/(rect.width*rect.height)))
                let limited=cropped.transformed(by:CGAffineTransform(scaleX:downscale,y:downscale))
                guard let cg=context.createCGImage(limited,from:limited.extent),let owned=Self.copyBitmap(cg) else {continue}
                batch.append(PendingBubble(region:region,key:key,image:owned,text:nil))
            }
            pending=batch
        }
        var batch=pending ?? [],recognitions=0
        for i in batch.indices where batch[i].text==nil {
            if let text=cache[batch[i].key] {batch[i].text=text;batch[i].image=nil;continue}
            guard recognitions<2,let cg=batch[i].image else {continue}
            let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
            request.recognitionLanguages=["ja-JP","en-US"];request.usesLanguageCorrection=true
            try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request]);recognitions += 1
            // Japanese Vision candidates can be correct at confidence 0.5 (verified
            // with mention/multiline fixtures). Geometry has already restricted
            // recognition to an avatar-backed bubble; do not discard those rows.
            let rows=(request.results ?? []).filter{($0.topCandidates(1).first?.confidence ?? 0)>=0.4}
                .sorted{a,b in a.boundingBox.midY == b.boundingBox.midY ? a.boundingBox.minX<b.boundingBox.minX:a.boundingBox.midY>b.boundingBox.midY}
            let text=rows.compactMap{$0.topCandidates(1).first?.string}.joined(separator:" ")
            batch[i].text=text;batch[i].image=nil
            cache[batch[i].key]=text;order.append(batch[i].key)
            if order.count>40 {cache.removeValue(forKey:order.removeFirst())}
        }
        guard batch.allSatisfy({$0.text != nil}) else {pending=batch;return result(nil,batch.count,recognitions)}
        let messages=batch.compactMap { item -> OCRLine? in
            guard let text=item.text,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return nil}
            let r=item.region
            return OCRLine(text:text,confidence:1,x:r.x,y:r.y,width:r.width,height:r.height)
        }
        pending=nil
        return result(messages,batch.count,recognitions)
    }
    private func result(_ messages:[OCRLine]?,_ bubbles:Int,_ recognitions:Int)->ChatFrameResult {
        ChatFrameResult(messages:messages,bubbles:bubbles,recognitions:recognitions,capturedAt:capturedAt)
    }
    private static func copyBitmap(_ image:CGImage)->CGImage? {
        guard let cg=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return nil}
        cg.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return cg.makeImage()
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
