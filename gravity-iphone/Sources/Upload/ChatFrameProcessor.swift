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
    let textRows:Int
}

/// One bounded text pass, then recall-first region filtering (strict legacy path is testable). ReplayKit
/// buffers never escape the callback; cache contains only bounded text results.
final class ChatFrameProcessor {
    private let broadReading:Bool
    private let lightweight:Bool
    init(broadReading:Bool=true,lightweight:Bool=true) {self.broadReading=broadReading;self.lightweight=lightweight && broadReading}
    private let context=CIContext(options:[.cacheIntermediates:false])
    private let analyzer=ChatLayoutAnalyzer()
    private var cache:[UInt64:(messages:[OCRLine],textRows:Int)]=[:]
    private var order:[UInt64]=[]
    func reset() {cache.removeAll();order.removeAll()}
    func process(_ source:CIImage,orientation:CGImagePropertyOrientation)throws->ChatFrameResult {
        let now=ProcessInfo.processInfo.systemUptime
        let oriented=source.oriented(forExifOrientation:Int32(orientation.rawValue))
        let image=oriented.transformed(by:CGAffineTransform(translationX:-oriented.extent.minX,y:-oriented.extent.minY))
        let extent=image.extent
        guard extent.width>0,extent.height>0 else {return ChatFrameResult(messages:[],bubbles:0,recognitions:0,capturedAt:now,textRows:0)}
        let scale=min(1,(lightweight ? 192:640)/max(extent.width,extent.height))
        let small=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        let tw=Int(small.extent.width),th=Int(small.extent.height)
        guard tw>=32,th>=32,let thumbnail=context.createCGImage(small,from:CGRect(x:0,y:0,width:tw,height:th)),
            let raster=Self.raster(thumbnail) else {return ChatFrameResult(messages:[],bubbles:0,recognitions:0,capturedAt:now,textRows:0)}
        // Broad left/central room area. Structural classification below, rather
        // than this ROI alone, decides whether any recognized words can be read.
        let regions=lightweight ? analyzer.balancedRegions(in:raster):[]
        if lightweight && regions.isEmpty {return ChatFrameResult(messages:[],bubbles:0,recognitions:0,capturedAt:now,textRows:0)}
        let roi:ChatRegion
        let key:UInt64
        if lightweight {
            let left=max(0,regions.map{$0.x}.min()!-0.008),top=max(0,regions.map{$0.y}.min()!-0.006)
            let right=min(1,regions.map{$0.x+$0.width}.max()!+0.008),bottom=min(1,regions.map{$0.y+$0.height}.max()!+0.006)
            roi=ChatRegion(x:left,y:top,width:right-left,height:bottom-top)
            var value:UInt64=14695981039346656037
            for region in regions {
                value=(value ^ fingerprint(raster,region)) &* 1099511628211
                for coordinate in [region.x*Double(tw),region.y*Double(th),region.width*Double(tw),region.height*Double(th)] {
                    value=(value ^ UInt64(max(0,Int(coordinate.rounded())))) &* 1099511628211
                }
            }
            key=value
        } else {
            roi=ChatRegion(x:0.015,y:0.17,width:0.88,height:0.72)
            key=fingerprint(raster,roi)
        }
        if let cached=cache[key] {return ChatFrameResult(messages:cached.messages,bubbles:cached.messages.count,recognitions:0,capturedAt:now,textRows:cached.textRows)}
        let rect=CGRect(x:roi.x*extent.width,y:(1-roi.y-roi.height)*extent.height,width:roi.width*extent.width,height:roi.height*extent.height)
        let cropped=image.cropped(to:rect).transformed(by:CGAffineTransform(translationX:-rect.minX,y:-rect.minY))
        let downscale=min(1,(lightweight ? 1000:1280)/max(rect.width,rect.height),sqrt((lightweight ? 220_000:400_000)/(rect.width*rect.height)))
        let limited=cropped.transformed(by:CGAffineTransform(scaleX:downscale,y:downscale))
        guard let cg=context.createCGImage(limited,from:limited.extent) else {return ChatFrameResult(messages:[],bubbles:0,recognitions:0,capturedAt:now,textRows:0)}
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
        request.recognitionLanguages=["ja-JP","en-US"];request.usesLanguageCorrection=true
        request.minimumTextHeight=0.009
        try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request])
        let lines=(request.results ?? []).compactMap {observation -> OCRLine? in
            guard let candidate=observation.topCandidates(1).first,candidate.confidence >= (broadReading ? 0:0.2) else {return nil}
            let box=observation.boundingBox
            return OCRLine(text:candidate.string,confidence:Double(candidate.confidence),x:roi.x+box.minX*roi.width,y:roi.y+(1-box.maxY)*roi.height,width:box.width*roi.width,height:box.height*roi.height)
        }
        let messages:[OCRLine]
        if lightweight {messages=analyzer.balancedMessages(in:raster,lines:lines,regions:regions)}
        else {messages=broadReading ? analyzer.readingLines(in:raster,lines:lines):analyzer.structuralMessages(in:raster,lines:lines)}
        cache[key]=(messages:messages,textRows:lines.count);order.append(key)
        if order.count>12 {cache.removeValue(forKey:order.removeFirst())}
        return ChatFrameResult(messages:messages,bubbles:messages.count,recognitions:1,capturedAt:now,textRows:lines.count)
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
