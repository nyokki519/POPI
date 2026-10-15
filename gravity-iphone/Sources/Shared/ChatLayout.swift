import Foundation

/// Upright RGBA thumbnail. All output rectangles use top-left normalized coordinates.
struct LayoutRaster {let width:Int;let height:Int;let rgba:[UInt8]}
struct ChatRegion {
    let x:Double;let y:Double;let width:Double;let height:Double
}
struct ChatLayoutAnalyzer {
    private static let directions=(0..<24).map { i -> (Double,Double) in
        let angle=Double(i)*2*Double.pi/24;return (cos(angle),sin(angle))
    }
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
        // Separate light and muted/dark surfaces. Keep avatar and geometry checks
        // for both; never fall back to recognizing the entire screen.
        let light=components(w:w,h:h) {p in
            pixels[p*4]>=205 && pixels[p*4+1]>=205 && pixels[p*4+2]>=205
        }
        // A keyboard row contains many small separated bright key caps. Suppress
        // the whole band, even if an old chat avatar remains immediately above it.
        let keys=light.filter { c in
            Double(c.y-viewport.y)>vh*0.45 && Double(c.width)>=vw*0.04 && Double(c.width)<=vw*0.14 &&
            Double(c.height)>=vh*0.025 && Double(c.height)<=vh*0.12
        }
        var keyRows:[[Component]]=[]
        for key in keys.sorted(by:{$0.y<$1.y}) {
            if let last=keyRows.last,let first=last.first,abs(first.y-key.y)<=max(3,Int(vh*0.012)) {keyRows[keyRows.count-1].append(key)}
            else {keyRows.append([key])}
        }
        let keyboardRows=keyRows.filter { row in
            row.count>=6 && (row.map{$0.maxX}.max()! - row.map{$0.x}.min()!)>Int(vw*0.55)
        }
        let keyboardTop=keyboardRows.count>=2 ? keyboardRows.compactMap{$0.first?.y}.min()!:h
        let muted=components(w:w,h:h) {p in
            let r=Int(pixels[p*4]),g=Int(pixels[p*4+1]),b=Int(pixels[p*4+2])
            let low=min(r,min(g,b)),high=max(r,max(g,b))
            return low>=24 && high<=230 && high-low<=55 && low<205
        }
        var found:[ChatRegion]=[]
        for c in light+muted {
            let left=Double(c.x-viewport.x)/vw,top=Double(c.y-viewport.y)/vh
            let bottom=Double(c.maxY-viewport.y+1)/vh
            guard left>=0.11,left<=0.36,top>=0.18,bottom<=0.94,c.maxY<keyboardTop,
                Double(c.width)>=vw*0.08,Double(c.width)<=vw*0.76,
                Double(c.height)>=vw*0.035,Double(c.height)<=vh*0.28,
                Double(c.width)/Double(c.height)>=0.9,
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
        for radius in stride(from:minRadius,through:maxRadius,by:2) {
            // A wide annulus tolerates oval/crowned paid frames. Require evidence
            // around all four sides; a nearby text stroke alone is insufficient.
            // Keep each arithmetic step and the tuple element types explicit.
            // Swift 5.7.2 (Xcode 14.2) otherwise exhausts its constraint solver
            // while inferring a four-Int tuple inside a generic map closure.
            var offsets:[(Int,Int,Int,Int)]=[]
            offsets.reserveCapacity(Self.directions.count)
            let radiusValue:Double=Double(radius)
            for direction in Self.directions {
                let xAtRadius:Double=direction.0*radiusValue
                let yAtRadius:Double=direction.1*radiusValue
                let innerX:Int=Int((xAtRadius*0.70).rounded())
                let innerY:Int=Int((yAtRadius*0.70).rounded())
                let outerX:Int=Int((xAtRadius*1.35).rounded())
                let outerY:Int=Int((yAtRadius*1.35).rounded())
                offsets.append((innerX,innerY,outerX,outerY))
            }
            let minX=max(viewport.x+radius,Int(Double(bubble.x)-Double(radius)*3.1))
            let maxX=min(bubble.x-radius-2,viewport.x+Int(Double(viewport.width)*0.22))
            let minY=max(radius,Int(Double(bubble.y)-Double(radius)*2.7))
            let maxY=min(h-radius-1,bubble.y+radius/2)
            guard minX<=maxX,minY<=maxY else {continue}
            for cy in stride(from:minY,through:maxY,by:2) {
                for cx in stride(from:minX,through:maxX,by:2) {
                    var edges=0,sectors=[0,0,0,0]
                    for (index,offset) in offsets.enumerated() {
                        let ix=cx+offset.0,iy=cy+offset.1,ox=cx+offset.2,oy=cy+offset.3
                        guard ix>=0,iy>=0,ox>=0,oy>=0,ix<w,ox<w,iy<h,oy<h else {continue}
                        let i=(iy*w+ix)*4,o=(oy*w+ox)*4
                        let contrast=abs(Int(pixels[i])-Int(pixels[o]))+abs(Int(pixels[i+1])-Int(pixels[o+1]))+abs(Int(pixels[i+2])-Int(pixels[o+2]))
                        if contrast>=70 {edges += 1;sectors[index/6] += 1}
                    }
                    if edges>=16 && sectors.allSatisfy({$0>=2}) {return true}
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
