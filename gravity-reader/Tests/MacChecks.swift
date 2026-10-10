import AppKit
import Foundation

@main struct MacChecks {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let image = NSImage(size:NSSize(width:900,height:160))
        image.lockFocus()
        NSColor.white.setFill();NSRect(x:0,y:0,width:900,height:160).fill()
        ("こんにちは テストコメントです" as NSString).draw(at:NSPoint(x:25,y:65),withAttributes:[.font:NSFont.systemFont(ofSize:38),.foregroundColor:NSColor.black])
        image.unlockFocus()
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { fatalError("fixture image") }
        do {
            let rows = try CaptureOCR.recognize(cg)
            let text=rows.map(\.text).joined().replacingOccurrences(of:" ",with:"")
            guard text.contains("こんにちは"),text.contains("テストコメント") else { fatalError("Japanese OCR failed: \(text)") }
            print("PASS Apple Vision Japanese image OCR")
            let devices=SpeechOutput.devices()
            guard Set(devices.map(\.id)).count==devices.count else { fatalError("duplicate device identifiers") }
            print("PASS CoreAudio enumeration; output devices=\(devices.count)")
            if devices.isEmpty { print("NOT VERIFIED: actual audio output; no hardware device") }
        } catch { fatalError("\(error)") }
    }
}
