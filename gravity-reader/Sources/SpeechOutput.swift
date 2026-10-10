import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

struct OutputDevice {
    let id:AudioDeviceID
    let name:String
    let uid:String
    var isVirtual:Bool {
        let lower=name.lowercased()
        return ["blackhole","loopback","soundflower","virtual"].contains(where:lower.contains)
    }
}

@MainActor final class SpeechOutput {
    private let synthesizer=AVSpeechSynthesizer()
    private let engine=AVAudioEngine()
    private let player=AVAudioPlayerNode()
    private var connectedFormat:AVAudioFormat?
    private var generation=0
    private var pendingBuffers=0
    private var synthesisFinished=false
    private var firstBuffer=false
    private(set) var busy=false
    private(set) var deviceID:AudioDeviceID=0
    var voiceID:String?
    var rate:Float=0.5
    var onComplete:((String?)->Void)?

    init() {engine.attach(player)}

    nonisolated static func devices()->[OutputDevice] {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwareProperty_Devices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var bytes:UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&bytes)==noErr,bytes>0 else {return []}
        var ids=[AudioDeviceID](repeating:0,count:Int(bytes)/MemoryLayout<AudioDeviceID>.size)
        let status=ids.withUnsafeMutableBytes { raw in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&bytes,raw.baseAddress!)
        }
        guard status==noErr else {return []}
        return ids.compactMap { id in
            var streams=AudioObjectPropertyAddress(mSelector:kAudioDeviceProperty_Streams,mScope:kAudioDevicePropertyScopeOutput,mElement:kAudioObjectPropertyElementMain)
            var size:UInt32=0
            guard AudioObjectGetPropertyDataSize(id,&streams,0,nil,&size)==noErr,size>0 else {return nil}
            return OutputDevice(id:id,name:stringProperty(id,kAudioObjectPropertyName) ?? "Audio \(id)",uid:stringProperty(id,kAudioDevicePropertyDeviceUID) ?? String(id))
        }.sorted{$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
    }
    nonisolated private static func stringProperty(_ id:AudioDeviceID,_ selector:AudioObjectPropertySelector)->String? {
        var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var value:CFString?;var size=UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id,&address,0,nil,&size,&value)==noErr else {return nil}
        return value.map{$0 as String}
    }
    nonisolated static func defaultDevice()->AudioDeviceID {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwareProperty_DefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var id:AudioDeviceID=0;var size=UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&id)
        return id
    }
    func configure(device:AudioDeviceID,voice:String?,rate:Float) throws {
        stop()
        guard Self.devices().contains(where:{$0.id==device}) else {
            throw ReaderError.message("選択した音声出力が見つかりません。接続してから「出力を更新」を押してください。")
        }
        deviceID=device;voiceID=voice;self.rate=min(0.65,max(0.3,rate))
    }
    func stop() {
        generation += 1
        synthesizer.stopSpeaking(at:.immediate);player.stop();engine.stop()
        busy=false;pendingBuffers=0;synthesisFinished=false;firstBuffer=false
    }
    private func connect(_ format:AVAudioFormat) throws {
        // Device configuration must happen while the output unit is stopped.
        player.stop();engine.stop()
        if connectedFormat != format {
            engine.stop();engine.disconnectNodeOutput(player)
            engine.connect(player,to:engine.mainMixerNode,format:format);connectedFormat=format
        }
        guard let unit=engine.outputNode.audioUnit else {throw ReaderError.message("音声出力を初期化できませんでした。")}
        var id=deviceID
        let result=AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&id,UInt32(MemoryLayout<AudioDeviceID>.size))
        guard result==noErr else {throw ReaderError.message("このデバイスに音声を出力できません（\(result)）。別の出力を選んでください。")}
        engine.prepare();try engine.start()
    }
    func speak(_ text:String) throws {
        guard !busy else {throw ReaderError.message("読み上げ中です。")}
        guard Self.devices().contains(where:{$0.id==deviceID}) else {throw ReaderError.message("音声出力が切断されました。")}
        let voice=voiceID.flatMap{AVSpeechSynthesisVoice(identifier:$0)} ?? AVSpeechSynthesisVoice(language:"ja-JP")
        guard let voice=voice else {throw ReaderError.message("日本語音声が利用できません。Macの読み上げ音声を追加してください。")}
        generation += 1;let token=generation
        busy=true;pendingBuffers=0;synthesisFinished=false;firstBuffer=false
        let utterance=AVSpeechUtterance(string:text);utterance.voice=voice;utterance.rate=rate;utterance.volume=0.85
        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcm=buffer as? AVAudioPCMBuffer else {return}
            let isFinal=pcm.frameLength==0
            let copy=Self.copyPCM(pcm)
            DispatchQueue.main.async {
                guard let self=self,self.generation==token,self.busy else {return}
                if isFinal {
                    self.synthesisFinished=true;self.completeIfReady(token:token);return
                }
                guard let copy=copy else {self.fail("読み上げ音声のバッファを作成できませんでした。");return}
                do {
                    if !self.firstBuffer {try self.connect(copy.format);self.firstBuffer=true}
                    self.pendingBuffers += 1
                    self.player.scheduleBuffer(copy,completionCallbackType:.dataPlayedBack) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self=self,self.generation==token,self.busy else {return}
                            self.pendingBuffers -= 1;self.completeIfReady(token:token)
                        }
                    }
                    if !self.player.isPlaying {self.player.play()}
                } catch {self.fail(error.localizedDescription)}
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+12) { [weak self] in
            guard let self=self,self.generation==token,self.busy,!self.firstBuffer else {return}
            self.fail("音声合成が開始できませんでした。日本語音声と出力デバイスを確認してください。")
        }
    }
    private func completeIfReady(token:Int) {
        guard generation==token,synthesisFinished,pendingBuffers==0 else {return}
        busy=false;onComplete?(firstBuffer ? nil : "音声合成が空の結果を返しました。")
    }
    private func fail(_ message:String) {stop();onComplete?(message)}
    nonisolated private static func copyPCM(_ source:AVAudioPCMBuffer)->AVAudioPCMBuffer? {
        guard source.frameLength>0,let result=AVAudioPCMBuffer(pcmFormat:source.format,frameCapacity:source.frameLength) else {return nil}
        result.frameLength=source.frameLength
        let src=UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let dst=UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
        guard src.count==dst.count else {return nil}
        for i in 0..<src.count {
            guard let a=src[i].mData,let b=dst[i].mData else {return nil}
            memcpy(b,a,Int(src[i].mDataByteSize));dst[i].mDataByteSize=src[i].mDataByteSize
        }
        return result
    }
}
