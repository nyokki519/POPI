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
        let muted=components(w:w,h:h) {p in
            let r=Int(pixels[p*4]),g=Int(pixels[p*4+1]),b=Int(pixels[p*4+2])
            let low=min(r,min(g,b)),high=max(r,max(g,b))
            return low>=24 && high<=230 && high-low<=55 && low<205
        }
        let surfaces=light+muted
        // A keyboard row contains many small separated bright key caps. Suppress
        // the whole band, even if an old chat avatar remains immediately above it.
        let keys=surfaces.filter { c in
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
        var found:[ChatRegion]=[]
        for c in surfaces {
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
    /// Filled surfaces at the shipped 192px thumbnail size. No avatar or username gate.
    func balancedRegions(in raster:LayoutRaster)->[ChatRegion] {
        let w=raster.width,h=raster.height
        guard w>=32,h>=32,w<=1024,h<=1024,raster.rgba.count==w*h*4 else {return []}
        let width=Double(w),height=Double(h),patches=colorPatches(raster)
        let keys=patches.filter {c in
            let x=Double(c.width)/width,y=Double(c.height)/height
            return Double(c.y)/height>0.45 && x>=0.04 && x<=0.30 && y>=0.025 && y<=0.13
        }
        var rows:[[Component]]=[]
        for key in keys.sorted(by:{$0.y<$1.y}) {
            if let last=rows.last,let first=last.first,abs(first.y-key.y)<=max(2,Int(height*0.012)) {rows[rows.count-1].append(key)}
            else {rows.append([key])}
        }
        let qwerty=rows.filter {$0.count>=6 && Double($0.map{$0.maxX}.max()! - $0.map{$0.x}.min()!)>width*0.55}
        let kana=rows.filter {$0.count>=3 && Double($0.map{$0.maxX}.max()! - $0.map{$0.x}.min()!)>width*0.65}
        let keyRows=qwerty.count>=2 ? qwerty:(kana.count>=3 ? kana:[])
        let keyboardTop=keyRows.compactMap{$0.first?.y}.min() ?? h
        let surfaces=patches.filter {c in
            let x=Double(c.x)/width,y=Double(c.y)/height
            return x>=0.11 && x<=0.45 && y>=0.28 && Double(c.maxY+1)/height<=0.90 && c.maxY<keyboardTop &&
                Double(c.width)/width>=0.07 && Double(c.width)/width<=0.78 &&
                Double(c.height)/height>=0.028 && Double(c.height)/height<=0.34 &&
                Double(c.width)/Double(c.height)>=0.9 && Double(c.area)/Double(c.width*c.height)>=0.55
        }
        return Array(surfaces.sorted{$0.y<$1.y}.suffix(10)).map {c in
            ChatRegion(x:Double(c.x)/width,y:Double(c.y)/height,width:Double(c.width)/width,height:Double(c.height)/height)
        }
    }
    func balancedMessages(in raster:LayoutRaster,lines:[OCRLine],regions:[ChatRegion]?=nil)->[OCRLine] {
        var result:[OCRLine]=[]
        for region in regions ?? balancedRegions(in:raster) {
            let body=lines.filter {line in
                let x=line.x+line.width/2,y=line.y+line.height/2
                return x.isFinite && y.isFinite && line.width>0 && line.height>0 &&
                    x>=region.x && x<=region.x+region.width && y>=region.y && y<=region.y+region.height
            }.sorted {$0.y == $1.y ? $0.x<$1.x:$0.y<$1.y}
            let text=body.map{normalizeComment($0.text)}.filter{!$0.isEmpty}.joined(separator:" ")
            if !text.isEmpty {result.append(OCRLine(text:text,confidence:1,x:region.x,y:region.y,width:region.width,height:region.height))}
        }
        return result.sorted{$0.y<$1.y}
    }
    /// Legacy v0.7 recall-first path; retained for regression and comparison.
    func readingLines(in raster:LayoutRaster,lines:[OCRLine])->[OCRLine] {
        let w=raster.width,h=raster.height
        guard w>=32,h>=32,w<=1024,h<=1024,raster.rgba.count==w*h*4 else {return []}
        let width=Double(w),height=Double(h)
        let keys=colorPatches(raster).filter {c in
            let x=Double(c.width)/width,y=Double(c.height)/height
            return Double(c.y)/height>0.45 && x>=0.04 && x<=0.30 && y>=0.025 && y<=0.13
        }
        var rows:[[Component]]=[]
        for key in keys.sorted(by:{$0.y<$1.y}) {
            if let last=rows.last,let first=last.first,abs(first.y-key.y)<=max(3,Int(height*0.012)) {rows[rows.count-1].append(key)}
            else {rows.append([key])}
        }
        let qwerty=rows.filter {row in
            row.count>=6 && Double(row.map{$0.maxX}.max()! - row.map{$0.x}.min()!)>width*0.55
        }
        let kana=rows.filter {row in
            row.count>=3 && Double(row.map{$0.maxX}.max()! - row.map{$0.x}.min()!)>width*0.65
        }
        let keyboardRows=qwerty.count>=2 ? qwerty:(kana.count>=3 ? kana:[])
        let keyboardTop=Double(keyboardRows.compactMap{$0.first?.y}.min() ?? h)/height
        let valid=lines.filter {line in
            line.confidence>=0 && line.x.isFinite && line.y.isFinite && line.width.isFinite && line.height.isFinite &&
            line.x>=0.015 && line.x<0.78 && line.y>=0.17 && line.width>0 && line.height>0 &&
            line.x+line.width<=1.01 && line.y+line.height<=min(0.90,keyboardTop) &&
            !normalizeComment(line.text).isEmpty
        }.sorted {$0.y == $1.y ? $0.x<$1.x:$0.y<$1.y}
        // Recognize this reader's own controls only as a pair. No generic
        // announcement, entry, username or word-content blacklist is applied.
        let labels=valid.map {normalizeComment($0.text)}
        if labels.contains("画面配信をはじめる") && labels.contains("読まれないときの確認") {return []}
        if labels.contains("スクリーンショットを選ぶ") && labels.contains("認識した文字を試し読み") {return []}
        return Array(valid.suffix(60))
    }
    /// Legacy text/image association; not used by the shipped lightweight path.
    func structuralMessages(in raster:LayoutRaster,lines:[OCRLine])->[OCRLine] {
        let w=raster.width,h=raster.height
        guard w>=32,h>=32,w<=1024,h<=1024,raster.rgba.count==w*h*4 else {return []}
        let pixels=raster.rgba
        let foreground=components(w:w,h:h) {p in Int(pixels[p*4])+Int(pixels[p*4+1])+Int(pixels[p*4+2])>60}
        let largest=foreground.max{$0.area<$1.area}
        let viewport:Component
        if let c=largest,c.area>w*h/5 {viewport=c}
        else {viewport=Component(x:0,y:0,maxX:w-1,maxY:h-1,area:w*h)}
        let vw=Double(viewport.width),vh=Double(viewport.height)
        let ox=Double(viewport.x),oy=Double(viewport.y)
        let sorted=lines.filter { l in
            l.confidence>=0.2 && l.x.isFinite && l.y.isFinite && l.width.isFinite && l.height.isFinite &&
            l.x>=0 && l.y>=0 && l.width>0 && l.height>0 && l.x+l.width<=1.01 && l.y+l.height<=1.01 && !normalizeComment(l.text).isEmpty
        }.sorted {$0.y == $1.y ? $0.x<$1.x:$0.y<$1.y}
        let labels=sorted.map {normalizeComment($0.text)}.joined(separator:" ")
        if (labels.contains("おしゃべり") && labels.contains("画面配信")) ||
           (labels.contains("スクリーンショットを選ぶ") && labels.contains("認識した本文")) {return []}
        // Repeated small key surfaces identify a keyboard independently of OCR
        // spelling. A local color-distance flood has no preferred palette.
        let patches=colorPatches(raster)
        let keys=patches.filter {c in
            Double(c.y)-oy>vh*0.45 && Double(c.width)>=vw*0.04 && Double(c.width)<=vw*0.14 &&
            Double(c.height)>=vh*0.025 && Double(c.height)<=vh*0.12
        }
        var rows:[[Component]]=[]
        for key in keys.sorted(by:{$0.y<$1.y}) {
            if let last=rows.last,let first=last.first,abs(first.y-key.y)<=max(3,Int(vh*0.012)) {rows[rows.count-1].append(key)}
            else {rows.append([key])}
        }
        let keyRows=rows.filter {$0.count>=6 && ($0.map{$0.maxX}.max()! - $0.map{$0.x}.min()!)>Int(vw*0.55)}
        let keyTop=keyRows.count>=2 ? Double(keyRows.compactMap{$0.first?.y}.min()!):Double(h)
        let nameIndices=sorted.indices.filter {index in
            let l=sorted[index]
            let x=l.x*Double(w),y=l.y*Double(h)
            guard (x-ox)/vw>=0.11,(x-ox)/vw<=0.42,(y-oy)/vh>=0.18,
                y+l.height*Double(h)<min(keyTop,oy+vh*0.88),l.width*Double(w)<=vw*0.65,
                l.height*Double(h)<=vh*0.055 else {return false}
            let c=Component(x:Int(x),y:Int(y),maxX:Int((l.x+l.width)*Double(w)),maxY:Int((l.y+l.height)*Double(h)),area:0)
            return hasAvatar(leftOf:c,viewport:viewport,pixels:pixels,w:w,h:h,nameAligned:true) ||
                hasImagePatch(beside:c,viewport:viewport,raster:raster)
        }
        var messages:[OCRLine]=[]
        for (position,index) in nameIndices.enumerated() {
            let name=sorted[index]
            let end=position+1<nameIndices.count ? sorted[nameIndices[position+1]].y:1.0
            var body:[OCRLine]=[]
            for line in sorted.dropFirst(index+1) {
                if line.y>=end {break}
                let x=(line.x*Double(w)-ox)/vw
                let bottom=(line.y+line.height)*Double(h)
                guard line.y>=name.y+name.height*0.9,
                    line.y-name.y<=0.27*vh/Double(h),bottom<min(keyTop,oy+vh*0.89),
                    line.x>=name.x-0.035*vw/Double(w),line.x<=name.x+0.18*vw/Double(w),
                    x>=0.10,(line.x+line.width)*Double(w)<=ox+vw*0.90 else {continue}
                if let last=body.last {
                    if line.y-last.y-last.height>0.045*vh/Double(h) {break}
                } else if line.y-name.y-name.height>0.12*vh/Double(h) {break}
                body.append(line)
            }
            guard !body.isEmpty else {continue}
            let x=body.map{$0.x}.min()!,y=body.map{$0.y}.min()!
            let right=body.map{$0.x+$0.width}.max()!,bottom=body.map{$0.y+$0.height}.max()!
            let text=body.map{normalizeComment($0.text)}.joined(separator:" ")
            messages.append(OCRLine(text:text,confidence:1,x:x,y:y,width:right-x,height:bottom-y))
        }
        // A name is helpful, never mandatory. Attach remaining OCR rows to
        // the nearest image above-left, independently of bubble palette.
        let textAreas=sorted.map {line in
            Component(x:Int(line.x*Double(w)),y:Int(line.y*Double(h)),maxX:Int((line.x+line.width)*Double(w)),maxY:Int((line.y+line.height)*Double(h)),area:0)
        }
        var fallback:[(OCRLine,(Int,Int,Int))]=[]
        for (index,line) in sorted.enumerated() {
            if nameIndices.contains(index) {continue}
            let x=line.x*Double(w),y=line.y*Double(h)
            let bottom=(line.y+line.height)*Double(h)
            guard (x-ox)/vw>=0.11,(x-ox)/vw<=0.50,(y-oy)/vh>=0.30,
                bottom<min(keyTop,oy+vh*0.89),(line.x+line.width)*Double(w)<=ox+vw*0.90 else {continue}
            if messages.contains(where:{line.y>=($0.y-0.005) && line.y+line.height<=($0.y+$0.height+0.005)}) {continue}
            let rect=Component(x:Int(x),y:Int(y),maxX:Int((line.x+line.width)*Double(w)),maxY:Int(bottom),area:0)
            guard let anchor=avatarAnchor(leftOf:rect,viewport:viewport,pixels:pixels,w:w,h:h,bodyAligned:true,excluding:textAreas) ?? imagePatchAnchor(beside:rect,viewport:viewport,raster:raster,bodyAligned:true,excluding:textAreas) else {continue}
            if let last=fallback.last,abs(last.1.0-anchor.0)<=anchor.2,
                abs(last.1.1-anchor.1)<=anchor.2,
                line.y-last.0.y-last.0.height<=0.045*vh/Double(h),
                line.y-last.0.y<=0.27*vh/Double(h) {
                let joined=last.0
                let left=min(joined.x,line.x),right=max(joined.x+joined.width,line.x+line.width)
                fallback[fallback.count-1]=(OCRLine(text:joined.text+" "+normalizeComment(line.text),confidence:1,x:left,y:joined.y,width:right-left,height:line.y+line.height-joined.y),anchor)
            } else {
                fallback.append((OCRLine(text:normalizeComment(line.text),confidence:1,x:line.x,y:line.y,width:line.width,height:line.height),anchor))
            }
        }
        messages.append(contentsOf:fallback.map{$0.0})
        messages.sort {$0.y<$1.y}
        return Array(messages.suffix(10))
    }
    private func colorPatches(_ raster:LayoutRaster)->[Component] {
        let w=raster.width,h=raster.height,pixels=raster.rgba
        var visited=Array(repeating:UInt8(0),count:w*h),pending:[Int]=[],result:[Component]=[]
        for seed in 0..<w*h where visited[seed]==0 {
            visited[seed]=1;pending.removeAll(keepingCapacity:true);pending.append(seed)
            let base=seed*4;var head=0,c=Component(x:seed%w,y:seed/w,maxX:seed%w,maxY:seed/w,area:0)
            while head<pending.count {
                let p=pending[head];head += 1;let x=p%w,y=p/w
                c.area += 1;c.x=min(c.x,x);c.maxX=max(c.maxX,x);c.y=min(c.y,y);c.maxY=max(c.maxY,y)
                for n in [x>0 ? p-1:-1,x+1<w ? p+1:-1,y>0 ? p-w:-1,y+1<h ? p+w:-1] where n>=0 && visited[n]==0 {
                    let q=n*4
                    let difference=abs(Int(pixels[q])-Int(pixels[base]))+abs(Int(pixels[q+1])-Int(pixels[base+1]))+abs(Int(pixels[q+2])-Int(pixels[base+2]))
                    if difference<=36 {visited[n]=1;pending.append(n)}
                }
            }
            if c.area>=6 {result.append(c)}
        }
        return result
    }
    private func hasImagePatch(beside name:Component,viewport:Component,raster:LayoutRaster)->Bool {
        imagePatchAnchor(beside:name,viewport:viewport,raster:raster) != nil
    }
    private func imagePatchAnchor(beside name:Component,viewport:Component,raster:LayoutRaster,bodyAligned:Bool=false,excluding:[Component]=[])->(Int,Int,Int)? {
        // Image texture plus edges on three sides admits square / heavily
        // decorated photos without accepting a nearby text stroke alone.
        let w=raster.width,h=raster.height,bytes=raster.rgba
        let r=max(4,Int(Double(viewport.width)*0.035))
        let minX=max(viewport.x+r,name.x-Int(Double(viewport.width)*0.18))
        let maxX=name.x-r-2
        let minY=max(r,bodyAligned ? name.y-r*4:name.y-r/2)
        let maxY=min(h-r-2,bodyAligned ? name.y-r/2:name.maxY+r/2)
        guard minX<=maxX,minY<=maxY else {return nil}
        func difference(_ x:Int,_ y:Int,_ a:Int,_ b:Int)->Int {
            guard x>=0,y>=0,a>=0,b>=0,x<w,a<w,y<h,b<h else {return 0}
            let p=(y*w+x)*4,q=(b*w+a)*4
            return abs(Int(bytes[p])-Int(bytes[q]))+abs(Int(bytes[p+1])-Int(bytes[q+1]))+abs(Int(bytes[p+2])-Int(bytes[q+2]))
        }
        for cy in stride(from:maxY,through:minY,by:-3) {for cx in stride(from:minX,through:maxX,by:3) {
            if excluding.contains(where:{cx+r/2 >= $0.x && cx-r/2 <= $0.maxX && cy+r/2 >= $0.y && cy-r/2 <= $0.maxY}) {continue}
            var sides=0,texture=0
            for d in [-r/2,0,r/2] {
                if difference(cx-r/2,cy+d,cx-r-2,cy+d)>60 {sides |= 1}
                if difference(cx+r/2,cy+d,cx+r+2,cy+d)>60 {sides |= 2}
                if difference(cx+d,cy-r/2,cx+d,cy-r-2)>60 {sides |= 4}
                if difference(cx+d,cy+r/2,cx+d,cy+r+2)>60 {sides |= 8}
                if difference(cx-r/2,cy+d,cx+r/2,cy+d)>40 {texture += 1}
            }
            if sides.nonzeroBitCount >= (bodyAligned ? 4:3),texture>=2 {return (cx,cy,r)}
        }}
        return nil
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
    private func hasAvatar(leftOf bubble:Component,viewport:Component,pixels:[UInt8],w:Int,h:Int,nameAligned:Bool=false)->Bool {
        avatarAnchor(leftOf:bubble,viewport:viewport,pixels:pixels,w:w,h:h,nameAligned:nameAligned) != nil
    }
    private func avatarAnchor(leftOf bubble:Component,viewport:Component,pixels:[UInt8],w:Int,h:Int,nameAligned:Bool=false,bodyAligned:Bool=false,excluding:[Component]=[])->(Int,Int,Int)? {
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
            let minX=max(viewport.x+radius,Int(Double(bubble.x)-Double(radius)*(bodyAligned ? 4.5:3.1)))
            let maxX=min(bubble.x-radius-2,viewport.x+Int(Double(viewport.width)*0.22))
            let minY=nameAligned ? max(radius,bubble.y-radius/2):max(radius,Int(Double(bubble.y)-Double(radius)*(bodyAligned ? 4.0:2.7)))
            let maxY=min(h-radius-1,bodyAligned ? bubble.y-radius/2:(nameAligned ? bubble.maxY:bubble.y)+radius/2)
            guard minX<=maxX,minY<=maxY else {continue}
            for cy in stride(from:maxY,through:minY,by:-2) {
                for cx in stride(from:minX,through:maxX,by:2) {
                    if excluding.contains(where:{cx+radius/2 >= $0.x && cx-radius/2 <= $0.maxX && cy+radius/2 >= $0.y && cy-radius/2 <= $0.maxY}) {continue}
                    var edges=0,sectors=[0,0,0,0]
                    for (index,offset) in offsets.enumerated() {
                        let ix=cx+offset.0,iy=cy+offset.1,ox=cx+offset.2,oy=cy+offset.3
                        guard ix>=0,iy>=0,ox>=0,oy>=0,ix<w,ox<w,iy<h,oy<h else {continue}
                        let i=(iy*w+ix)*4,o=(oy*w+ox)*4
                        let contrast=abs(Int(pixels[i])-Int(pixels[o]))+abs(Int(pixels[i+1])-Int(pixels[o+1]))+abs(Int(pixels[i+2])-Int(pixels[o+2]))
                        if contrast>=70 {edges += 1;sectors[index/6] += 1}
                    }
                    if edges >= (bodyAligned ? 20:16) && sectors.allSatisfy({$0 >= (bodyAligned ? 4:2)}) {return (cx,cy,radius)}
                }
            }
        }
        return nil
    }
}

/// Limit duty cycle after expensive frames and when the phone becomes hot.
struct RecognitionBudget {
    private let economy:Bool
    init(economy:Bool=false) {self.economy=economy}
    private var last:Double?
    private var interval=1.2
    mutating func shouldProcess(now:Double,thermal:Int)->Bool {
        guard thermal<3 else {return false}
        let wait=max(interval,thermal>=2 ? (economy ? 8.0:3.0):(economy ? 3.0:1.2))
        guard last.map({now-$0>=wait}) ?? true else {return false}
        last=now;return true
    }
    mutating func record(duration:Double) {interval=economy ? min(30,max(3,duration*10)):min(5,max(1.2,duration*3))}
}
