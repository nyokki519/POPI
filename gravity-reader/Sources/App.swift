import AppKit
import AVFoundation
import CoreGraphics

@main @MainActor final class ReaderApp:NSObject,NSApplicationDelegate,NSWindowDelegate {
    private var window:NSWindow!
    private let capture=CaptureOCR()
    private let speech=SpeechOutput()
    private var detector=CommentDetector()
    private var queue=FreshSpeechQueue()
    private var region:CaptureRegion?
    private var outputs:[OutputDevice]=[]
    private var active=false
    private var preparing=false
    private var generation=0
    private var loop:Task<Void,Never>?
    private var heartbeat:Timer?
    private let startButton=NSButton(title:"開始",target:nil,action:nil)
    private let mode=NSSegmentedControl(labels:["PRIVATE","ROOM"],trackingMode:.selectOne,target:nil,action:nil)
    private let devices=NSPopUpButton(frame:.zero,pullsDown:false)
    private let voices=NSPopUpButton(frame:.zero,pullsDown:false)
    private let speed=NSSlider(value:0.5,minValue:0.3,maxValue:0.65,target:nil,action:nil)
    private let ignored=NSTextField(string:"")
    private let regionLabel=NSTextField(labelWithString:"コメント欄：未選択")
    private let status=NSTextField(wrappingLabelWithString:"iPhoneをMacに表示し、「コメント欄を選択」から始めてください。")
    private let modeHint=NSTextField(wrappingLabelWithString:"PRIVATE：選択したMacの音声出力で、自分だけがコメントを聞きます。")
    private let metrics=NSTextField(labelWithString:"待機 0件｜OCR 未開始")
    private let preview=NSTextView(frame:.zero)
    private var lastMilliseconds:Double=0

    static func main() {
        let app=NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate=ReaderApp();app.delegate=delegate;app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        buildMenu();buildWindow();refreshDevices();populateVoices()
        mode.selectedSegment=0
        speed.doubleValue=UserDefaults.standard.double(forKey:"speechRate")
        if speed.doubleValue<0.3 {speed.doubleValue=0.5}
        ignored.stringValue=UserDefaults.standard.string(forKey:"ignoredPhrases") ?? ""
        speech.onComplete={ [weak self] error in
            guard let self=self else {return}
            if let error=error {self.stop(message:error)}
            else if self.active {self.drain()}
            else {self.status.stringValue="テスト音声の再生が終了しました。"}
        }
        heartbeat=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationWillTerminate(_ notification:Notification) {stop();heartbeat?.invalidate()}
    func windowShouldClose(_ sender:NSWindow)->Bool {NSApp.terminate(nil);return true}

    private func button(_ title:String,_ action:Selector)->NSButton {
        let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;return b
    }
    private func row(_ views:[NSView])->NSStackView {
        let s=NSStackView(views:views);s.orientation = .horizontal;s.alignment = .centerY;s.spacing=10
        return s
    }
    private func label(_ title:String)->NSTextField {
        let l=NSTextField(labelWithString:title);l.setContentHuggingPriority(.required,for:.horizontal);return l
    }
    private func buildMenu() {
        let menu=NSMenu();let item=NSMenuItem();menu.addItem(item)
        let appMenu=NSMenu();item.submenu=appMenu
        appMenu.addItem(withTitle:"終了",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let edit=NSMenuItem(title:"編集",action:nil,keyEquivalent:"");menu.addItem(edit);edit.submenu=NSMenu(title:"編集")
        edit.submenu?.addItem(withTitle:"コピー",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.submenu?.addItem(withTitle:"貼り付け",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edit.submenu?.addItem(withTitle:"すべて選択",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        NSApp.mainMenu=menu
    }
    private func buildWindow() {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:750),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="GRAVITY Comment Reader";window.minSize=NSSize(width:680,height:600);window.center();window.delegate=self
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12
        stack.translatesAutoresizingMaskIntoConstraints=false
        let outer=NSScrollView();outer.hasVerticalScroller=true;outer.autohidesScrollers=true
        outer.translatesAutoresizingMaskIntoConstraints=false
        let document=FlippedDocumentView(frame:NSRect(x:0,y:0,width:760,height:900))
        document.autoresizingMask=[.width];outer.documentView=document
        window.contentView!.addSubview(outer);document.addSubview(stack)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),outer.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),
            outer.topAnchor.constraint(equalTo:window.contentView!.topAnchor),outer.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-20),
            stack.topAnchor.constraint(equalTo:document.topAnchor,constant:20),stack.bottomAnchor.constraint(lessThanOrEqualTo:document.bottomAnchor,constant:-20)
        ])
        status.maximumNumberOfLines=4
        let title=label("GRAVITY コメント読み上げ");title.font=NSFont.systemFont(ofSize:24,weight:.bold)
        stack.addArrangedSubview(title)
        let info=NSTextField(wrappingLabelWithString:"iPhoneの画面をMacに表示し、コメント欄だけを指定します。起動時の履歴は読み上げず、新しい表示を確認してから発話します。")
        stack.addArrangedSubview(info)
        stack.addArrangedSubview(row([button("コメント欄を選択",#selector(selectRegion)),button("iPhoneの表示手順",#selector(showPhoneHelp)),regionLabel]))
        mode.target=self;mode.action=#selector(modeChanged)
        stack.addArrangedSubview(row([label("モード"),mode]))
        stack.addArrangedSubview(modeHint)
        devices.target=self;devices.action=#selector(settingsChanged)
        devices.widthAnchor.constraint(greaterThanOrEqualToConstant:320).isActive=true
        stack.addArrangedSubview(row([label("音声出力"),devices,button("出力を更新",#selector(refreshOutputAction))]))
        voices.target=self;voices.action=#selector(settingsChanged);voices.widthAnchor.constraint(greaterThanOrEqualToConstant:320).isActive=true
        stack.addArrangedSubview(row([label("日本語音声"),voices]))
        speed.target=self;speed.action=#selector(settingsChanged);speed.widthAnchor.constraint(equalToConstant:270).isActive=true
        stack.addArrangedSubview(row([label("読み上げ速度"),label("ゆっくり"),speed,label("速く")]))
        ignored.placeholderString="除外する語句をカンマ区切りで入力（任意）"
        ignored.widthAnchor.constraint(greaterThanOrEqualToConstant:470).isActive=true
        stack.addArrangedSubview(row([label("除外語句"),ignored]))
        startButton.target=self;startButton.action=#selector(toggleStart);startButton.bezelStyle = .rounded;startButton.keyEquivalent="\r"
        stack.addArrangedSubview(row([startButton,button("テスト読み上げ",#selector(testSpeech)),button("模擬コメントで試す",#selector(startDemo)),button("接続診断",#selector(diagnostics))]))
        status.font=NSFont.systemFont(ofSize:13);stack.addArrangedSubview(status)
        metrics.font=NSFont.monospacedSystemFont(ofSize:12,weight:.regular);stack.addArrangedSubview(metrics)
        stack.addArrangedSubview(label("OCRプレビュー（画像・コメントは外部へ送信せず、ディスクにも保存しません）"))
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        preview.isEditable=false;preview.isSelectable=true;preview.font=NSFont.monospacedSystemFont(ofSize:13,weight:.regular)
        preview.autoresizingMask=[.width];preview.isVerticallyResizable=true;preview.isHorizontallyResizable=false
        preview.textContainer?.widthTracksTextView=true;scroll.documentView=preview
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;scroll.heightAnchor.constraint(equalToConstant:180).isActive=true
        for field in [info,modeHint,status] {field.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
    }
    private func populateVoices() {
        voices.removeAllItems();voices.addItem(withTitle:"システムの日本語音声")
        for voice in AVSpeechSynthesisVoice.speechVoices().filter({$0.language.hasPrefix("ja")}) {
            voices.addItem(withTitle:voice.name);voices.lastItem?.representedObject=voice.identifier
        }
        if let saved=UserDefaults.standard.string(forKey:"voiceID"),let item=voices.itemArray.first(where:{$0.representedObject as? String==saved}) {voices.select(item)}
    }
    private func refreshDevices(prefer:AudioDeviceID?=nil) {
        let selected=prefer ?? devices.selectedItem.map{AudioDeviceID($0.tag)} ?? SpeechOutput.defaultDevice()
        outputs=SpeechOutput.devices();devices.removeAllItems()
        for device in outputs {devices.addItem(withTitle:device.name);devices.lastItem?.tag=Int(device.id)}
        if let item=devices.itemArray.first(where:{$0.tag==Int(selected)}) {devices.select(item)}
        else if let item=devices.itemArray.first(where:{$0.tag==Int(SpeechOutput.defaultDevice())}) {devices.select(item)}
    }
    @objc private func refreshOutputAction() {stop(message:"出力一覧を更新しました。音声出力を確認してから開始してください。");refreshDevices()}
    @objc private func settingsChanged() {
        stop(message:"音声設定を変更しました。「テスト読み上げ」で確認してから開始してください。")
        UserDefaults.standard.set(speed.doubleValue,forKey:"speechRate")
        UserDefaults.standard.set(voices.selectedItem?.representedObject as? String,forKey:"voiceID")
    }
    @objc private func modeChanged() {
        stop(message:"モードを変更し、読み上げを停止しました。出力先を確認してください。")
        refreshDevices(prefer:mode.selectedSegment==0 ? SpeechOutput.defaultDevice() : outputs.first(where:{$0.isVirtual})?.id)
        modeHint.stringValue=mode.selectedSegment==0
            ? "PRIVATE：選択したMacの音声出力で、自分だけがコメントを聞きます。"
            : "ROOM：選択した音声出力へ読み上げを送ります。iPhoneのマイクへの入力には別途接続が必要です。BlackHoleだけではiPhoneに届きません。"
    }
    @objc private func selectRegion() {
        stop(message:"コメント欄をドラッグして選択してください。")
        window.orderOut(nil)
        capture.selectRegion { [weak self] chosen in
            guard let self=self else {return}
            self.window.makeKeyAndOrderFront(nil)
            if let chosen=chosen {
                self.region=chosen;self.regionLabel.stringValue="範囲 \(Int(chosen.rect.width))×\(Int(chosen.rect.height))"
                self.status.stringValue="範囲を選択しました。iPhoneの画面をその位置に保ったまま開始してください。"
            } else {self.status.stringValue="範囲選択をキャンセルしました。"}
        }
    }
    private func configureSpeech() throws {
        guard let item=devices.selectedItem else {throw ReaderError.message("音声出力がありません。デバイスを接続して出力一覧を更新してください。")}
        try speech.configure(device:AudioDeviceID(item.tag),voice:voices.selectedItem?.representedObject as? String,rate:Float(speed.doubleValue))
    }
    @objc private func toggleStart() {if active || preparing {stop(message:"停止しました。保留コメントを破棄しました。")} else {begin(demo:false)}}
    @objc private func startDemo() {begin(demo:true)}
    private func begin(demo:Bool) {
        stop()
        if !demo && region==nil {status.stringValue="先に「コメント欄を選択」を押してください。";return}
        do {try configureSpeech()} catch {status.stringValue=error.localizedDescription;return}
        let ignore=ignored.stringValue.components(separatedBy:CharacterSet(charactersIn:",、\n"))
        detector=CommentDetector(ignoreWords:ignore)
        UserDefaults.standard.set(ignored.stringValue,forKey:"ignoredPhrases")
        preparing=true;let token=generation;updateControls()
        loop=Task { [weak self] in
            guard let self=self else {return}
            do {
                if !demo,let region=self.region {try await self.capture.prepare(region)}
                guard self.generation==token,!Task.isCancelled else {return}
                self.preparing=false;self.active=true;self.updateControls()
                self.status.stringValue=demo ? "模擬モード：テスト用コメントを読み上げます。実際の画面OCRは使用していません。" : "監視中：最初の画面を基準にして、新しいコメントを読み上げます。"
                var frameIndex=0;var errors=0
                while self.active && self.generation==token && !Task.isCancelled {
                    let before=ProcessInfo.processInfo.systemUptime
                    do {
                        let result:OCRFrame
                        if demo {
                            let snapshots=[["花子:こんにちは","太郎:こんばんは"],["花子:こんにちは","太郎:こんばんは","次郎:読み上げのテストです"],["太郎:こんばんは","次郎:読み上げのテストです","花子:日本語のコメントです"],["次郎:読み上げのテストです","花子:日本語のコメントです","太郎:同じ文章も追加できます"],["花子:日本語のコメントです","太郎:同じ文章も追加できます","太郎:同じ文章も追加できます"]]
                            let text=snapshots[min(frameIndex/4,snapshots.count-1)]
                            result=OCRFrame(lines:text.enumerated().map{OCRLine(text:$0.element,confidence:1,x:0,y:Double($0.offset)*0.15,width:1,height:0.08)},elapsedMilliseconds:0)
                        } else {result=try await self.capture.capture()}
                        guard self.generation==token,!Task.isCancelled else {return}
                        errors=0;self.lastMilliseconds=result.elapsedMilliseconds
                        self.preview.string=result.lines.sorted{$0.y<$1.y}.map{String(format:"%.0f%% ",$0.confidence*100)+$0.text}.joined(separator:"\n")
                        for text in self.detector.ingest(result.lines) {self.queue.enqueue(text,now:ProcessInfo.processInfo.systemUptime)}
                        self.drain();frameIndex += 1
                    } catch {
                        guard self.generation==token,!Task.isCancelled else {return}
                        errors += 1;self.status.stringValue="画面取得／OCRエラー（\(errors)/3）：\(error.localizedDescription)"
                        if errors>=3 {self.stop(message:"画面取得が続けて失敗したため停止しました。権限・iPhone画面・範囲を確認してください。\n\(error.localizedDescription)");return}
                    }
                    self.updateMetrics()
                    let wait=max(0.05,0.5-(ProcessInfo.processInfo.systemUptime-before))
                    try await Task.sleep(nanoseconds:UInt64(wait*1_000_000_000))
                }
            } catch {
                if self.generation==token {self.stop(message:error.localizedDescription)}
            }
        }
    }
    private func stop(message:String?=nil) {
        capture.cancelPreparation()
        generation += 1;loop?.cancel();loop=nil;active=false;preparing=false
        speech.stop();queue.clear();detector.reset();updateControls()
        if let message=message {status.stringValue=message};updateMetrics()
    }
    private func updateControls() {
        startButton.title=active ? "停止" : preparing ? "準備中…" : "開始"
        startButton.isEnabled = !preparing;ignored.isEnabled = !active && !preparing
    }
    private func drain() {
        guard active,!speech.busy,let text=queue.pop(now:ProcessInfo.processInfo.systemUptime) else {return}
        do {try speech.speak(text)} catch {stop(message:error.localizedDescription)}
    }
    private func tick() {
        if speech.busy || active {
            if !SpeechOutput.devices().contains(where:{$0.id==speech.deviceID}) {
                stop(message:"音声出力が切断されたため停止しました。再接続して出力一覧を更新してください。");return
            }
        }
        if active {drain()};updateMetrics()
    }
    private func updateMetrics() {
        metrics.stringValue="待機 \(queue.count)件｜破棄 \(queue.dropped)件｜OCR \(Int(lastMilliseconds))ms｜\(speech.busy ? "発話中" : "待機中")"
    }
    @objc private func testSpeech() {
        stop()
        do {try configureSpeech();try speech.speak("グラビティのコメント読み上げテストです。選択した出力先で聞こえるか確認してください。");status.stringValue="テスト音声を選択した出力先へ再生しています。"}
        catch {status.stringValue=error.localizedDescription}
    }
    @objc private func showPhoneHelp() {
        showAlert("iPhoneの画面をMacに表示する","1. iPhoneをUSBでMacに接続し、ロック解除・「信頼」を許可。\n2. MacでQuickTime Playerを開き、ファイル → 新規ムービー収録。\n3. 録画ボタン横のメニューからカメラにiPhoneを選択。録画開始は不要です。\n4. iPhoneでGRAVITYのコメント画面を開く。\n5. 本アプリの「コメント欄を選択」で文字の領域だけを指定。\n\nmacOSのiPhoneミラーリングでも画面を選べますが、Appleの制限によりiPhoneのマイクを使えないためPRIVATE向けです。ROOMでは別の画面表示経路を検証してください。ウィンドウを動かしたら範囲を選び直してください。")
    }
    @objc private func diagnostics() {
        let selected=outputs.first(where:{$0.id==AudioDeviceID(devices.selectedItem?.tag ?? 0)})
        let japanese=AVSpeechSynthesisVoice.speechVoices().filter{$0.language.hasPrefix("ja")}.count
        var report="画面収録許可：\(CGPreflightScreenCaptureAccess() ? "許可あり" : "未許可")\n選択範囲：\(region==nil ? "未選択" : "選択済み")\n日本語音声：\(japanese)種類\n音声出力：\(selected?.name ?? "未選択")\n出力デバイス数：\(SpeechOutput.devices().count)\n\n"
        if mode.selectedSegment==1 {
            report += "ROOMの接続確認\n1. 「テスト読み上げ」でMac側の選択した出力を確認。\n2. BlackHole等はMac内部の仮想出力です。iPhoneへのマイク入力を自動作成しません。\n3. iPhone対応のUSBオーディオ機器／ミキサー等でMacの音を入力できる経路が必要です。単にUSBでiPhone画面を映しても音はGRAVITYへ送られません。\n4. macOSの「iPhoneミラーリング」はiPhoneのマイクを利用できないため、ROOMには別の表示経路が必要です。\n5. GRAVITYで発言可能な状態・マイクONにし、別の参加者／端末で実際に聞こえるか確認。\n\n本アプリからiPhoneの入力やルーム接続の成否は検出できません。"
        } else {report += "PRIVATE：スピーカー／ヘッドホンを選び、テスト読み上げを実行してください。iPhoneのマイクへは自動送信しません。"}
        report += "\n\n画面取得・Mac音声・iPhone送信は実機確認が必要です。"
        showAlert("接続診断",report)
    }
    private func showAlert(_ title:String,_ message:String) {
        let alert=NSAlert();alert.messageText=title;alert.informativeText=message;alert.addButton(withTitle:"閉じる");alert.runModal()
    }
}

@MainActor private final class FlippedDocumentView:NSView {
    override var isFlipped:Bool {true}
}
