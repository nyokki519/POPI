import Foundation

/// Upright RGBA thumbnail. All output rectangles use top-left normalized coordinates.
struct LayoutRaster {let width:Int;let height:Int;let rgba:[UInt8]}
struct ChatRegion {
    let x:Double;let y:Double;let width:Double;let height:Double
}
struct ChatLayoutAnalyzer {
    private struct Component {var x:Int;var y:Int;var maxX:Int;var maxY:Int;var area:Int
        var width:Int {maxX-x+1};var height:Int {maxY-y+1}
    }
    func bubbles(in raster:LayoutRaster)->[ChatRegion] {
        let w=raster.width,h=raster.height
        guard w>=32,h>=32,w<=1024,h<=1024,raster.rgba.count==w*h*4 else {return []}
        let pixels=raster.rgba
        // Detect the app's visible viewport, including letterboxed/windowed layouts.
        let foreground=components(w:w,h:h) {p in
            Int(pixels[p*4])+Int(pixels[p*4+1])+Int(pixels[p*4+2])>60
        }
        let largest=foreground.max{$0.area<$1.area}
        let viewport:Component
        if let c=largest,c.area>w*h/5 {viewport=c}
        else {viewport=Component(x:0,y:0,maxX:w-1,maxY:h-1,area:w*h)}
        let vw=Double(viewport.width),vh=Double(viewport.height)
        // This version deliberately supports light chat bubbles. Unsupported styles
        // are omitted rather than reverting to reading the full screen.
        let light=components(w:w,h:h) {p in
            pixels[p*4]>=205 && pixels[p*4+1]>=205 && pixels[p*4+2]>=205
        }
        var found:[ChatRegion]=[]
        for c in light {
            let left=Double(c.x-viewport.x)/vw,top=Double(c.y-viewport.y)/vh
            let bottom=Double(c.maxY-viewport.y+1)/vh
            guard left>=0.11,left<=0.36,top>=0.18,bottom<=0.94,
                Double(c.width)>=vw*0.17,Double(c.width)<=vw*0.76,
                Double(c.height)>=vw*0.035,Double(c.height)<=vh*0.28,
                Double(c.width)/Double(c.height)>=1.45,
                Double(c.area)/Double(c.width*c.height)>=0.55,
                hasAvatar(leftOf:c,viewport:viewport,pixels:pixels,w:w,h:h) else {continue}
            found.append(ChatRegion(x:Double(c.x)/Double(w),y:Double(c.y)/Double(h),width:Double(c.width)/Double(w),height:Double(c.height)/Double(h)))
        }
        return Array(found.sorted{$0.y<$1.y}.suffix(10))
    }
    private func components(w:Int,h:Int,include:(Int)->Bool)->[Component] {
        var visited=Array(repeating:UInt8(0),count:w*h),pending:[Int]=[],result:[Component]=[]
        pending.reserveCapacity(w*h)
        for seed in 0..<w*h where visited[seed]==0 {
            visited[seed]=1
            guard include(seed) else {continue}
            pending.removeAll(keepingCapacity:true);pending.append(seed)
            var head=0,c=Component(x:seed%w,y:seed/w,maxX:seed%w,maxY:seed/w,area:0)
            while head<pending.count {
                let p=pending[head];head += 1
                let x=p%w,y=p/w;c.area += 1;c.x=min(c.x,x);c.maxX=max(c.maxX,x);c.y=min(c.y,y);c.maxY=max(c.maxY,y)
                let neighbors=[x>0 ? p-1:-1,x+1<w ? p+1:-1,y>0 ? p-w:-1,y+1<h ? p+w:-1]
                for n in neighbors where n>=0 && visited[n]==0 {
                    visited[n]=1;if include(n) {pending.append(n)}
                }
            }
            if c.area>=6 {result.append(c)}
        }
        return result
    }
    private func hasAvatar(leftOf bubble:Component,viewport:Component,pixels:[UInt8],w:Int,h:Int)->Bool {
        let minRadius=max(3,Int(Double(viewport.width)*0.029))
        let maxRadius=max(minRadius,Int(Double(viewport.width)*0.058))
        let angles=(0..<24).map{Double($0)*2*Double.pi/24}
        for radius in stride(from:minRadius,through:maxRadius,by:2) {
            let minX=max(viewport.x+radius,Int(Double(bubble.x)-Double(radius)*3.1))
            let maxX=min(bubble.x-radius-2,viewport.x+Int(Double(viewport.width)*0.22))
            let minY=max(radius,Int(Double(bubble.y)-Double(radius)*2.7))
            let maxY=min(h-radius-1,bubble.y+radius/2)
            guard minX<=maxX,minY<=maxY else {continue}
            for cy in stride(from:minY,through:maxY,by:2) {
                for cx in stride(from:minX,through:maxX,by:2) {
                    var edges=0
                    for a in angles {
                        let ix=Int((Double(cx)+cos(a)*Double(radius)*0.83).rounded()),iy=Int((Double(cy)+sin(a)*Double(radius)*0.83).rounded())
                        let ox=Int((Double(cx)+cos(a)*Double(radius)*1.17).rounded()),oy=Int((Double(cy)+sin(a)*Double(radius)*1.17).rounded())
                        guard ix>=0,iy>=0,ox>=0,oy>=0,ix<w,ox<w,iy<h,oy<h else {continue}
                        let i=(iy*w+ix)*4,o=(oy*w+ox)*4
                        let contrast=abs(Int(pixels[i])-Int(pixels[o]))+abs(Int(pixels[i+1])-Int(pixels[o+1]))+abs(Int(pixels[i+2])-Int(pixels[o+2]))
                        if contrast>=100 {edges += 1}
                    }
                    if edges>=19 {return true}
                }
            }
        }
        return false
    }
}

/// Limit duty cycle after expensive frames and when the phone becomes hot.
struct RecognitionBudget {
    private var last:Double?
    private var interval=1.2
    mutating func shouldProcess(now:Double,thermal:Int)->Bool {
        guard thermal<3 else {return false}
        let wait=max(interval,thermal>=2 ? 3.0:1.2)
        guard last.map({now-$0>=wait}) ?? true else {return false}
        last=now;return true
    }
    mutating func record(duration:Double) {interval=min(5,max(1.2,duration*3))}
}
