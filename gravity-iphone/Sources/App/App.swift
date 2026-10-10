import UIKit
import ReplayKit
@main final class AppDelegate:UIResponder,UIApplicationDelegate {
    var window:UIWindow?
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?)->Bool {
        let window=UIWindow(frame:UIScreen.main.bounds)
        window.rootViewController=ReaderViewController();window.makeKeyAndVisible();self.window=window
        return true
    }
}
final class ReaderViewController:UIViewController,RPBroadcastActivityViewControllerDelegate,RPBroadcastControllerDelegate {
    private let status=UILabel()
    private var broadcast:RPBroadcastController?
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor = .systemBackground
        let title=UILabel();title.text="GRAVITY コメント読み上げ";title.font = .preferredFont(forTextStyle:.title2);title.numberOfLines=0
        let guide=UILabel();guide.numberOfLines=0;guide.text="PRIVATE 実機検証版\n\n1. 下のボタンで配信設定を開きます。\n2. コメント範囲を設定して開始します。\n3. GRAVITYに戻り、新しいコメントを待ちます。\n\n最初に映った文字は読みません。画面は保存・送信しません。自分用の読み上げです。ROOMへの音声送出は未対応です。\n\nイヤホン推奨。iPhone上での読み上げ可否は実機確認が必要です。"
        status.numberOfLines=0;status.text="停止中"
        let start=UIButton(type:.system);start.setTitle("画面配信の設定・開始",for:.normal);start.addTarget(self,action:#selector(begin),for:.touchUpInside)
        let stop=UIButton(type:.system);stop.setTitle("読み上げを停止",for:.normal);stop.addTarget(self,action:#selector(end),for:.touchUpInside)
        let stack=UIStackView(arrangedSubviews:[title,guide,status,start,stop]);stack.axis = .vertical;stack.spacing=20;stack.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(stack);NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:24)])
    }
    @objc private func begin() {
        guard broadcast?.isBroadcasting != true else {status.text="配信中です。GRAVITYに戻ってください。";return}
        RPBroadcastActivityViewController.load(withPreferredExtension:"jp.nyokki519.GravityReader.Setup") { [weak self] controller,error in
            DispatchQueue.main.async {
                guard let self=self else {return}
                guard let controller=controller else {self.status.text=error?.localizedDescription ?? "設定を開けませんでした";return}
                controller.delegate=self;controller.modalPresentationStyle = .formSheet
                controller.popoverPresentationController?.sourceView=self.view
                self.present(controller,animated:true)
            }
        }
    }
    func broadcastActivityViewController(_ controller:RPBroadcastActivityViewController,didFinishWith broadcastController:RPBroadcastController?,error:Error?) {
        controller.dismiss(animated:true)
        guard let next=broadcastController else {status.text=error?.localizedDescription ?? "キャンセルしました";return}
        broadcast=next;next.delegate=self
        next.startBroadcast { [weak self] error in DispatchQueue.main.async {self?.status.text=error?.localizedDescription ?? "配信開始。GRAVITYに戻ってください。"} }
    }
    @objc private func end() {
        guard let broadcast=broadcast,broadcast.isBroadcasting else {status.text="停止中。システムの画面配信表示からも停止できます。";return}
        broadcast.finishBroadcast { [weak self] error in DispatchQueue.main.async {self?.status.text=error?.localizedDescription ?? "停止しました"} }
    }
    func broadcastController(_ broadcastController:RPBroadcastController,didFinishWithError error:Error?) {
        DispatchQueue.main.async { [weak self] in self?.status.text=error?.localizedDescription ?? "配信終了" }
    }
}
