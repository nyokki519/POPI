import UIKit
import PhotosUI
import CoreImage
import AVFoundation

/// Selected photos stay on-device and are never written to disk or logs.
final class DiagnosticsViewController:UIViewController,PHPickerViewControllerDelegate {
    private let status=UILabel()
    private let preview=UIImageView()
    private let body=UITextView()
    private let speech=AVSpeechSynthesizer()
    private let worker=DispatchQueue(label:"GravityReader.photo-check",qos:.userInitiated)
    private var generation=SessionGeneration()
    private var text=""
    private var backgroundObserver:NSObjectProtocol?
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor = .systemBackground
        let stack=UIStackView();stack.axis = .vertical;stack.spacing=12
        stack.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:18),stack.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-18),stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:12),stack.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-12)])
        backgroundObserver=NotificationCenter.default.addObserver(forName:UIApplication.didEnterBackgroundNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self=self else {return}
            _ = self.generation.next();self.stopSpeech();self.preview.image=nil;self.body.text="";self.text=""
            self.status.text="バックグラウンド移行時に確認画像を解放しました。再確認する場合は画像を選び直してください。"
        }
        let title=UILabel();title.text="読み取りの確認";title.font = .boldSystemFont(ofSize:22)
        status.numberOfLines=0;status.font = .systemFont(ofSize:14)
        status.text="ルームのスクリーンショットを選ぶと、配信と同じ処理で本文を確認します。画像は保存・送信しません。配信は停止してからお試しください。"
        preview.contentMode = .scaleAspectFit;preview.heightAnchor.constraint(equalToConstant:180).isActive=true
        body.isEditable=false;body.font = .systemFont(ofSize:16);body.backgroundColor = .secondarySystemBackground
        body.accessibilityLabel="認識したコメント本文"
        stack.addArrangedSubview(title);stack.addArrangedSubview(status)
        stack.addArrangedSubview(button("スクリーンショットを選ぶ",#selector(selectPhoto)))
        stack.addArrangedSubview(preview);stack.addArrangedSubview(body)
        stack.addArrangedSubview(button("音声だけテスト",#selector(testAudio)))
        stack.addArrangedSubview(button("認識した本文を試し読み",#selector(readBody)))
        stack.addArrangedSubview(button("閉じる",#selector(close)))
    }
    private func button(_ title:String,_ action:Selector)->UIButton {
        let b=UIButton(type:.system);b.setTitle(title,for:.normal);b.titleLabel?.font = .boldSystemFont(ofSize:16)
        b.addTarget(self,action:action,for:.touchUpInside);return b
    }
    @objc private func selectPhoto() {
        stopSpeech();_ = generation.next()
        var configuration=PHPickerConfiguration();configuration.filter = .images;configuration.selectionLimit=1
        let picker=PHPickerViewController(configuration:configuration);picker.delegate=self;present(picker,animated:true)
    }
    func picker(_ picker:PHPickerViewController,didFinishPicking results:[PHPickerResult]) {
        picker.dismiss(animated:true)
        guard let provider=results.first?.itemProvider,provider.canLoadObject(ofClass:UIImage.self) else {return}
        let token=generation.next();status.text="画像を読み取り中…";text="";body.text="";preview.image=nil
        provider.loadObject(ofClass:UIImage.self) { [weak self] object,error in
            guard let image=object as? UIImage,error==nil else {
                DispatchQueue.main.async { [weak self] in
                    guard let self=self,self.generation.isCurrent(token) else {return}
                    self.status.text="画像を開けませんでした。別の画像でお試しください。"
                };return
            }
            self?.analyze(image,token:token)
        }
    }
    private func analyze(_ image:UIImage,token:Int) {
        worker.async { [weak self] in
            autoreleasepool {
                do {
                    // Rendering applies UIImage orientation and bounds photo memory.
                    let scale=min(1,1800/max(image.size.width,image.size.height))
                    let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
                    let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
                    let photo=UIGraphicsImageRenderer(size:size,format:format).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }
                    guard let cg=photo.cgImage else {throw NSError(domain:"GravityReader",code:1)}
                    let processor=ChatFrameProcessor();let source=CIImage(cgImage:cg)
                    var result=try processor.process(source,orientation:.up)
                    for _ in 0..<5 where result.messages==nil {result=try processor.process(source,orientation:.up)}
                    let rows=result.messages ?? []
                    let recognized=rows.map{$0.text}.joined(separator:"\n\n")
                    // Mark recognized body bounds; unrecognized candidates remain unmarked.
                    let annotated=UIGraphicsImageRenderer(size:size,format:format).image { context in
                        photo.draw(at:.zero);context.cgContext.setStrokeColor(UIColor.systemGreen.cgColor);context.cgContext.setLineWidth(3)
                        for row in rows {
                            context.cgContext.stroke(CGRect(x:row.x*size.width,y:row.y*size.height,width:row.width*size.width,height:row.height*size.height))
                        }
                    }
                    let candidates=result.bubbles
                    DispatchQueue.main.async { [weak self] in
                        guard let self=self,self.generation.isCurrent(token),self.viewIfLoaded?.window != nil else {return}
                        self.preview.image=annotated;self.body.text=recognized;self.text=recognized
                        if candidates==0 {self.status.text="本文枠を検出できませんでした。アイコンや吹き出しの見た目による検出失敗です。"}
                        else if rows.isEmpty {self.status.text="本文枠は\(candidates)件検出しましたが、文字を認識できませんでした。"}
                        else {self.status.text="本文枠\(candidates)件／文字認識\(rows.count)件。緑枠が認識した本文です。試し読みで音声も確認できます。"}
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        guard let self=self,self.generation.isCurrent(token) else {return}
                        self.status.text="文字認識に失敗しました。画像を選び直してください。"
                    }
                }
            }
        }
    }
    @objc private func testAudio() {speak("読み上げの音声テストです。")}
    @objc private func readBody() {
        guard !text.isEmpty else {status.text="先に画像を選び、認識結果を確認してください。";return}
        speak(String(text.prefix(1000)))
    }
    private func speak(_ value:String) {
        do {
            speech.stopSpeaking(at:.immediate)
            try AVAudioSession.sharedInstance().setCategory(.playback,options:[.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let utterance=AVSpeechUtterance(string:value);utterance.voice=AVSpeechSynthesisVoice(language:"ja-JP")
            speech.speak(utterance)
            status.text="試し読みを開始しました。実際に音が聞こえるか確認してください。"
        } catch {status.text="音声を開始できませんでした。ルームと画面配信を停止してから再試行してください。"}
    }
    private func stopSpeech() {speech.stopSpeaking(at:.immediate);try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
    @objc private func close() {_ = generation.next();stopSpeech();dismiss(animated:true)}
    deinit {if let observer=backgroundObserver {NotificationCenter.default.removeObserver(observer)}}
    override func viewDidDisappear(_ animated:Bool) {
        super.viewDidDisappear(animated)
        if presentingViewController==nil {_ = generation.next();stopSpeech();preview.image=nil;body.text="";text=""}
    }
}
