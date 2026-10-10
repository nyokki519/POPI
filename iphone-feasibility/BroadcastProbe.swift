// Experimental Broadcast Upload Extension handler, not an installable app.
// iOS16+, Apple SDK and signed device build required. Native APIs UNTESTED here.
// Set RPBroadcastProcessMode=RPBroadcastProcessModeSampleBuffer in extension plist.
// No networking, persisted screen images, or logging of recognized text.
import ReplayKit
import Vision
import AVFoundation
import ImageIO

final class BroadcastProbe: RPBroadcastSampleHandler, AVSpeechSynthesizerDelegate {
    private let speech=AVSpeechSynthesizer()
    private var videoFrames=0
    private var ocrFrames=0
    private var lastOCR:Double=0
    private var lastSpeech:Double=0
    private var paused=false

    override func broadcastStarted(withSetupInfo setupInfo:[String:NSObject]?) {
        videoFrames=0;ocrFrames=0;lastOCR=0;lastSpeech=0;paused=false
        DispatchQueue.main.async { [weak self] in
            guard let self=self else {return};self.speech.delegate=self
        }
        NSLog("GRProbe started: no video/text upload")
        // This is a device experiment, not evidence that extension audio works.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,options:[.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            NSLog("GRProbe audio session activation returned successfully; audibility still needs confirmation")
        } catch {NSLog("GRProbe audio activation failed: %@",String(describing:error))}
    }
    override func processSampleBuffer(_ sampleBuffer:CMSampleBuffer,with type:RPSampleBufferType) {
        guard type == .video,!paused else {return}
        videoFrames += 1
        let now=ProcessInfo.processInfo.systemUptime
        guard now-lastOCR>=0.75,let pixels=CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
        lastOCR=now
        let value=CMGetAttachment(sampleBuffer,key:RPVideoSampleOrientationKey as CFString,attachmentModeOut:nil) as? NSNumber
        let orientation=value.flatMap{CGImagePropertyOrientation(rawValue:$0.uint32Value)} ?? .up
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate;request.recognitionLanguages=["ja-JP","en-US"]
        request.usesLanguageCorrection=true
        do {
            // Consume the buffer synchronously. Apple says it is valid only until
            // this callback returns. Do not retain it for a detached async task.
            try VNImageRequestHandler(cvPixelBuffer:pixels,orientation:orientation,options:[:]).perform([request])
            ocrFrames += 1
            let confident=(request.results ?? []).filter{($0.topCandidates(1).first?.confidence ?? 0)>=0.55}.count
            NSLog("GRProbe video=%d OCR=%d confidentLines=%d latencyMs=%.1f",videoFrames,ocrFrames,confident,(ProcessInfo.processInfo.systemUptime-now)*1000)
            if confident>0,now-lastSpeech>=15 {
                lastSpeech=now
                DispatchQueue.main.async { [weak self] in
                    guard let self=self,!self.speech.isSpeaking else {return}
                    let utterance=AVSpeechUtterance(string:"画面の文字認識と読み上げの検証です。")
                    utterance.voice=AVSpeechSynthesisVoice(language:"ja-JP")
                    self.speech.speak(utterance)
                }
            }
        } catch {NSLog("GRProbe OCR failed: %@",String(describing:error))}
    }
    override func broadcastPaused() {paused=true;stopSpeech()}
    override func broadcastResumed() {paused=false;lastOCR=0}
    override func broadcastFinished() {
        paused=true;stopSpeech()
        NSLog("GRProbe finished video=%d OCR=%d",videoFrames,ocrFrames)
    }
    private func stopSpeech() {
        DispatchQueue.main.async { [weak self] in self?.speech.stopSpeaking(at:.immediate) }
    }
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didStart utterance:AVSpeechUtterance) {NSLog("GRProbe synthesis started: callback does not prove audible playback")}
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance) {NSLog("GRProbe synthesis finished")}
}
