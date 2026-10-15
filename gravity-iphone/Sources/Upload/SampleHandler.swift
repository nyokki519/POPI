import ReplayKit
import Vision
import AVFoundation
import ImageIO
import CoreImage
final class SampleHandler:RPBroadcastSampleHandler {
    private var detector=CommentDetector(filterSystemLabels:false)
    private let processor=ChatFrameProcessor()
    private var budget=RecognitionBudget()
    private var configuration=ReaderConfiguration()
    private var paused=true
    private var failures=0
    private var lastDiagnostic=0.0
    private let speaker=PrivateSpeaker()
    override func broadcastStarted(withSetupInfo setupInfo:[String:NSObject]?) {
        configuration=ReaderConfiguration(setupInfo);detector.reset();processor.reset();budget=RecognitionBudget();paused=false;failures=0
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
        let thermal=ProcessInfo.processInfo.thermalState.rawValue
        guard budget.shouldProcess(now:now,thermal:thermal),let pixels=CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
        autoreleasepool {
            defer {budget.record(duration:ProcessInfo.processInfo.systemUptime-now)}
            let attached=CMGetAttachment(sampleBuffer,key:RPVideoSampleOrientationKey as CFString,attachmentModeOut:nil) as? NSNumber
            let orientation=attached.flatMap{CGImagePropertyOrientation(rawValue:$0.uint32Value)} ?? .up
            do {
                let result=try processor.process(CIImage(cvPixelBuffer:pixels),orientation:orientation)
                failures=0
                if let lines=result.messages {
                    let comments=detector.ingest(lines)
                    if !comments.isEmpty {DispatchQueue.main.async { [weak self] in self?.speaker.enqueue(comments,time:result.capturedAt) }}
                }
                // Periodic zero counts distinguish missed shapes from failed OCR.
                // No screenshot, username, or recognized text is logged.
                if now-lastDiagnostic>=10 {
                    lastDiagnostic=now
                    NSLog("GravityReader bubbles=%d OCR=%d rows=%d pending=%d latencyMs=%.0f",result.bubbles,result.recognitions,result.messages?.count ?? 0,result.messages==nil ? 1:0,(ProcessInfo.processInfo.systemUptime-now)*1000)
                }
            } catch {
                failures += 1
                if failures>=5 {paused=true;DispatchQueue.main.async { [weak self] in self?.speaker.stop() };finishBroadcastWithError(NSError(domain:"GravityReader",code:2,userInfo:[NSLocalizedDescriptionKey:"文字認識に連続して失敗しました。画面配信を再開始してください。"]))}
            }
        }
    }
    override func broadcastPaused() {paused=true;DispatchQueue.main.async { [weak self] in self?.speaker.stop() }}
    override func broadcastResumed() {paused=false;detector.reset();processor.reset();budget=RecognitionBudget();let rate=Float(configuration.rate);DispatchQueue.main.async { [weak self] in self?.startSpeaker(rate:rate) }}
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
