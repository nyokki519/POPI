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
final class ReaderViewController:UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor = .systemBackground
        let title=UILabel();title.text="GRAVITY コメント読み上げ";title.font = .preferredFont(forTextStyle:.title2);title.numberOfLines=0
        let guide=UILabel();guide.numberOfLines=0;guide.text="PRIVATE 実機検証版\n\n1. 下の画面配信ボタンを押します。\n2. Gravity Reader PRIVATEを選び、配信を開始します。マイクはオフにしてください。\n3. GRAVITYに戻り、新しいコメントを待ちます。\n4. 停止するときは、iPhone上部の画面配信表示を押してください。\n\n読取範囲は画面の上から45〜90%に固定しています。最初に映った文字は読みません。画面は保存・送信しません。\n\n自分用の読み上げです。ROOMへの音声送出は未対応です。イヤホン推奨。GRAVITY画面での動作と音声は実機確認が必要です。"
        let picker=RPSystemBroadcastPickerView(frame:CGRect(x:0,y:0,width:60,height:60));picker.preferredExtension=(Bundle.main.bundleIdentifier ?? "jp.nyokki519.GravityReader")+".Upload";picker.showsMicrophoneButton=false
        picker.translatesAutoresizingMaskIntoConstraints=false;picker.heightAnchor.constraint(equalToConstant:60).isActive=true
        let scroll=UIScrollView();scroll.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(scroll)
        let stack=UIStackView(arrangedSubviews:[title,guide,picker]);stack.axis = .vertical;stack.spacing=24;stack.translatesAutoresizingMaskIntoConstraints=false;scroll.addSubview(stack)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor),scroll.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),scroll.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor),stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:24),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-24),stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-48)])
    }
}
