import AppKit
import ScreenCaptureKit
import Vision
import CoreGraphics
import CoreVideo

struct CaptureRegion {
    let displayID: CGDirectDisplayID
    let rect: CGRect // Points, origin at top-left of the selected display.
    let scale: CGFloat
}
struct OCRFrame {
    let lines: [OCRLine]
    let elapsedMilliseconds: Double
}
enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value)=self {return value};return nil }
}

@MainActor final class CaptureOCR {
    private var preparation=SessionGeneration()
    func cancelPreparation() { _ = preparation.next() }
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private var picker: RegionPicker?
    private(set) var region: CaptureRegion?

    func selectRegion(completion:@escaping(CaptureRegion?)->Void) {
        picker?.cancel()
        let newPicker=RegionPicker { [weak self] region in
            self?.picker=nil
            completion(region)
        }
        picker=newPicker;newPicker.show()
    }
    func prepare(_ region:CaptureRegion) async throws {
        let token=preparation.next()
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw ReaderError.message("画面収録の許可が必要です。システム設定の「プライバシーとセキュリティ」→「画面収録／画面とシステムオーディオ録音」でこのアプリを許可し、アプリを再起動してください。")
        }
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard preparation.isCurrent(token), !Task.isCancelled else {throw CancellationError()}
        guard let display=content.displays.first(where:{$0.displayID==region.displayID}) else {
            throw ReaderError.message("選択したディスプレイが見つかりません。画面範囲を選び直してください。")
        }
        let own=content.applications.filter{$0.bundleIdentifier==Bundle.main.bundleIdentifier}
        filter=SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
        let config=SCStreamConfiguration()
        config.sourceRect=region.rect
        let reduction=min(1,1800/max(region.rect.width*region.scale,region.rect.height*region.scale))
        config.width=max(1,Int(region.rect.width*region.scale*reduction))
        config.height=max(1,Int(region.rect.height*region.scale*reduction))
        config.showsCursor=false
        config.capturesAudio=false
        config.pixelFormat=kCVPixelFormatType_32BGRA
        configuration=config;self.region=region
    }
    func capture() async throws -> OCRFrame {
        guard let filter=filter,let config=configuration else {
            throw ReaderError.message("先にコメント欄の範囲を選択してください。")
        }
        let start=ProcessInfo.processInfo.systemUptime
        let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
        let lines=try await Task.detached(priority:.userInitiated) { try Self.recognize(image) }.value
        return OCRFrame(lines:lines,elapsedMilliseconds:(ProcessInfo.processInfo.systemUptime-start)*1000)
    }
    nonisolated static func recognize(_ image:CGImage) throws -> [OCRLine] {
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages=["ja-JP","en-US"]
        request.usesLanguageCorrection=true
        let handler=VNImageRequestHandler(cgImage:image,options:[:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let result=observation.topCandidates(1).first else {return nil}
            let rect=observation.boundingBox
            return OCRLine(text:result.string,confidence:Double(result.confidence),x:rect.minX,y:1-rect.maxY,width:rect.width,height:rect.height)
        }
    }
}

@MainActor private final class SelectionPanel:NSPanel {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
}
@MainActor private final class RegionPicker {
    private var panels:[NSPanel]=[]
    private var completion:((CaptureRegion?)->Void)?
    init(completion:@escaping(CaptureRegion?)->Void) {self.completion=completion}
    func show() {
        for screen in NSScreen.screens {
            guard let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {continue}
            let panel=SelectionPanel(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            panel.setFrame(screen.frame,display:true)
            panel.isReleasedWhenClosed=false
            panel.level = .screenSaver;panel.isOpaque=false;panel.backgroundColor = .clear
            panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            let view=SelectionView(frame:NSRect(origin:.zero,size:screen.frame.size)) { [weak self] rect in
                guard let rect=rect else {self?.cancel();return}
                let crop=CGRect(x:rect.minX,y:screen.frame.height-rect.maxY,width:rect.width,height:rect.height)
                self?.finish(CaptureRegion(displayID:number.uint32Value,rect:crop,scale:screen.backingScaleFactor))
            }
            panel.contentView=view;panels.append(panel);panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(view)
        }
        if panels.isEmpty {cancel()}
    }
    func cancel() {finish(nil)}
    private func finish(_ region:CaptureRegion?) {
        let callback=completion;completion=nil
        panels.forEach{$0.close()};panels=[];callback?(region)
    }
}
@MainActor private final class SelectionView:NSView {
    private var start:NSPoint?
    private var selection:NSRect = .zero
    private let done:(NSRect?)->Void
    override var acceptsFirstResponder:Bool {true}
    init(frame:NSRect,done:@escaping(NSRect?)->Void) {self.done=done;super.init(frame:frame)}
    required init?(coder:NSCoder) {fatalError("not supported")}
    override func draw(_ dirtyRect:NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill();bounds.fill()
        if !selection.isEmpty {
            NSColor.systemBlue.withAlphaComponent(0.25).setFill();selection.fill()
            NSColor.white.setStroke();let path=NSBezierPath(rect:selection);path.lineWidth=2;path.stroke()
        }
        ("コメント欄をドラッグして選択してください。Escでキャンセル" as NSString).draw(at:NSPoint(x:35,y:bounds.height-65),withAttributes:[.font:NSFont.systemFont(ofSize:21,weight:.semibold),.foregroundColor:NSColor.white])
    }
    override func mouseDown(with event:NSEvent) {start=convert(event.locationInWindow,from:nil)}
    override func mouseDragged(with event:NSEvent) {
        guard let start=start else {return};let end=convert(event.locationInWindow,from:nil)
        selection=NSRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(end.x-start.x),height:abs(end.y-start.y)).intersection(bounds)
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        mouseDragged(with:event)
        if selection.width>=40 && selection.height>=40 {done(selection)}
    }
    override func keyDown(with event:NSEvent) {if event.keyCode==53 {done(nil)}}
}
