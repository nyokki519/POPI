import ReplayKit
import Vision
import AVFoundation
import ImageIO
final class SampleHandler:RPBroadcastSampleHandler {
    private var detector=CommentDetector()
    private var configuration=ReaderConfiguration()
    private var paused=true
    private var lastOCR=0.0
    private var failures=0
    private let speaker=PrivateSpeaker()
    override func broadcastStarted(withSetupInfo setupInfo:[String:NSObject]?) {
        configuration=ReaderConfiguration(setupInfo);detector.reset();paused=false;lastOCR=0;failures=0
        let rate=Float(configuration.rate)
        DispatchQueue.main.async { [weak self] in self?.startSpeaker(rate:rate) }
        NSLog("GravityReader started; images and recognized text are not stored or uploaded")
    }
    private func startSpeaker(rate:Float) {
        do {try speaker.start(rate:rate)} catch {finishBroadcastWithError(NSError(domain:"GravityReader",code:3,userInfo:[NSLocalizedDescriptionKey:"読み上げ用音声を開始できませんでした。GRAVITYの音声ルームを一度閉じて、画面配信を再開始してください。" ]))}
    }
    override func processSampleBuffer(_ sampleBuffer:CMSampleBuffer,with type:RPSampleBufferType) {
        guard type == .video,!paused else {return}
        let now=ProcessInfo.processInfo.systemUptime
        guard now-lastOCR>=0.75,let pixels=CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
        lastOCR=now
        autoreleasepool {
            let attached=CMGetAttachment(sampleBuffer,key:RPVideoSampleOrientationKey as CFString,attachmentModeOut:nil) as? NSNumber
            let orientation=attached.flatMap{CGImagePropertyOrientation(rawValue:$0.uint32Value)} ?? .up
            let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
            request.recognitionLanguages=["ja-JP","en-US"];request.usesLanguageCorrection=true
            request.regionOfInterest=CGRect(x:0,y:1-configuration.bottom,width:1,height:configuration.bottom-configuration.top)
            do {
                // ReplayKit buffers are valid only during this callback: synchronous OCR.
                try VNImageRequestHandler(cvPixelBuffer:pixels,orientation:orientation,options:[:]).perform([request])
                failures=0
                let lines=(request.results ?? []).compactMap { result -> OCRLine? in
                    guard let text=result.topCandidates(1).first else {return nil}
                    let b=result.boundingBox
                    return OCRLine(text:text.string,confidence:Double(text.confidence),x:b.minX,y:1-b.maxY,width:b.width,height:b.height)
                }
                let comments=detector.ingest(lines)
                if !comments.isEmpty {DispatchQueue.main.async { [weak self] in self?.speaker.enqueue(comments,time:now) }}
                NSLog("GravityReader OCR lines=%d new=%d latencyMs=%.0f",lines.count,comments.count,(ProcessInfo.processInfo.systemUptime-now)*1000)
            } catch {
                failures += 1
                if failures>=5 {paused=true;DispatchQueue.main.async { [weak self] in self?.speaker.stop() };finishBroadcastWithError(NSError(domain:"GravityReader",code:2,userInfo:[NSLocalizedDescriptionKey:"文字認識に連続して失敗しました。画面配信を再開始してください。"]))}
            }
        }
    }
    override func broadcastPaused() {paused=true;DispatchQueue.main.async { [weak self] in self?.speaker.stop() }}
    override func broadcastResumed() {paused=false;detector.reset();lastOCR=0;let rate=Float(configuration.rate);DispatchQueue.main.async { [weak self] in self?.startSpeaker(rate:rate) }}
    override func broadcastFinished() {paused=true;DispatchQueue.main.async { [weak self] in self?.speaker.stop() };NSLog("GravityReader finished")}
}
// All speaker state is confined to the main queue. Serial ReplayKit callbacks
// dispatch start/enqueue/stop in order; stopped sessions cannot keep queued speech.
private final class PrivateSpeaker:NSObject,AVSpeechSynthesizerDelegate {
    private let synth=AVSpeechSynthesizer()
    private var queue=FreshSpeechQueue(capacity:6,maxAge:8,maxCharacters:120)
    private var active=false
    private var rate:Float=0.5
    func start(rate:Float) throws {
        stop();self.rate=rate;synth.delegate=self
        try AVAudioSession.sharedInstance().setCategory(.playback,options:[.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true);active=true
    }
    func enqueue(_ comments:[String],time:Double) {
        guard active else {return}
        for text in comments {queue.enqueue(text,now:time)}
        speakNext()
    }
    private func speakNext() {
        guard active,!synth.isSpeaking,let text=queue.pop(now:ProcessInfo.processInfo.systemUptime) else {return}
        let utterance=AVSpeechUtterance(string:text);utterance.voice=AVSpeechSynthesisVoice(language:"ja-JP");utterance.rate=rate
        synth.speak(utterance)
    }
    func stop() {active=false;queue.clear();synth.stopSpeaking(at:.immediate);try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance) {DispatchQueue.main.async { [weak self] in self?.speakNext() }}
}
