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
    private let photograph=UIImageView()
    private let shade=CAGradientLayer()
    private let pink=UIColor(red:0.88,green:0.08,blue:0.42,alpha:1)
    private let ink=UIColor(red:0.19,green:0.06,blue:0.18,alpha:1)
    private var observers:[NSObjectProtocol]=[]
    override var preferredStatusBarStyle:UIStatusBarStyle {.lightContent}

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor=UIColor(red:0.10,green:0.025,blue:0.08,alpha:1)
        photograph.contentMode = .scaleAspectFill;photograph.clipsToBounds=true
        photograph.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(photograph)
        NSLayoutConstraint.activate([photograph.leadingAnchor.constraint(equalTo:view.leadingAnchor),photograph.trailingAnchor.constraint(equalTo:view.trailingAnchor),photograph.topAnchor.constraint(equalTo:view.topAnchor),photograph.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        loadPhoto()
        shade.colors=[UIColor.black.withAlphaComponent(0.08).cgColor,UIColor(red:0.12,green:0.015,blue:0.08,alpha:0.35).cgColor,UIColor.black.withAlphaComponent(0.8).cgColor]
        shade.locations=[0,0.35,1];photograph.layer.addSublayer(shade)
        let scroll=UIScrollView();scroll.translatesAutoresizingMaskIntoConstraints=false
        scroll.alwaysBounceVertical=true;scroll.showsVerticalScrollIndicator=false;view.addSubview(scroll)
        let content=UIStackView();content.axis = .vertical;content.spacing=18;content.translatesAutoresizingMaskIntoConstraints=false;scroll.addSubview(content)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor),scroll.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),scroll.bottomAnchor.constraint(equalTo:view.bottomAnchor),content.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:22),content.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-22),content.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:20),content.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-28),content.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-44)])

        let badge=label("花と、ことばと、あなたの声。",size:12,weight:.semibold,color:.white)
        badge.layer.shadowColor=UIColor.black.cgColor;badge.layer.shadowOpacity=0.5;badge.layer.shadowRadius=5
        let title=label("オカマ読み上げ\nスッキリアプリ",size:32,weight:.heavy,color:.white)
        title.accessibilityTraits.insert(.header);title.layer.shadowColor=UIColor.black.cgColor;title.layer.shadowOpacity=0.55;title.layer.shadowRadius=10;title.layer.shadowOffset=CGSize(width:0,height:2)
        let subtitle=label("ルームのコメントに、\n声の彩りを。",size:16,weight:.medium,color:UIColor.white.withAlphaComponent(0.95))
        let hero=UIStackView(arrangedSubviews:[badge,title,subtitle]);hero.axis = .vertical;hero.spacing=12
        hero.isLayoutMarginsRelativeArrangement=true;hero.layoutMargins=UIEdgeInsets(top:12,left:0,bottom:18,right:0)
        content.addArrangedSubview(hero)

        let status=label("自分だけに読み上げ",size:12,weight:.bold,color:pink)
        let heading=label("おしゃべりを、聞こう。",size:23,weight:.bold,color:ink)
        heading.accessibilityTraits.insert(.header)
        let description=label("吹き出し内の文字を優先して読みます。アイコンや名前の一致は不要です。",size:14,weight:.regular,color:ink.withAlphaComponent(0.78))
        let startTitle=label("画面配信をはじめる",size:17,weight:.bold,color:.white)
        let startHelp=label("右の配信ボタンをタップ",size:12,weight:.regular,color:UIColor.white.withAlphaComponent(0.88))
        let startLabels=UIStackView(arrangedSubviews:[startTitle,startHelp]);startLabels.axis = .vertical;startLabels.spacing=5
        let picker=RPSystemBroadcastPickerView(frame:CGRect(x:0,y:0,width:60,height:60))
        picker.preferredExtension=bundledUploadIdentifier(applicationURL:Bundle.main.bundleURL);picker.showsMicrophoneButton=false
        picker.backgroundColor = .white;picker.layer.cornerRadius=30;picker.translatesAutoresizingMaskIntoConstraints=false
        picker.widthAnchor.constraint(equalToConstant:60).isActive=true;picker.heightAnchor.constraint(equalToConstant:60).isActive=true
        let action=UIStackView(arrangedSubviews:[startLabels,picker]);action.axis = .horizontal;action.alignment = .center;action.spacing=10
        action.isLayoutMarginsRelativeArrangement=true;action.layoutMargins=UIEdgeInsets(top:14,left:16,bottom:14,right:14)
        action.backgroundColor=pink;action.layer.cornerRadius=23
        let main=UIStackView(arrangedSubviews:[status,heading,description,action]);main.axis = .vertical;main.spacing=14
        content.addArrangedSubview(card(main,color:UIColor.white.withAlphaComponent(0.97)))

        let diagnose=UIButton(type:.system);diagnose.setTitle("読まれないときの確認",for:.normal)
        diagnose.setTitleColor(.white,for:.normal);diagnose.titleLabel?.font = .boldSystemFont(ofSize:16)
        diagnose.addTarget(self,action:#selector(openDiagnostics),for:.touchUpInside)
        content.addArrangedSubview(diagnose)
        let steps=UIStackView();steps.axis = .vertical;steps.spacing=16
        steps.addArrangedSubview(label("かんたん、3ステップ",size:17,weight:.bold,color:ink))
        for (number,text) in [("01","配信先で「オカマ読み上げスッキリアプリ」を選ぶ"),("02","GRAVITYのルームを開く"),("03","新しく届いたコメントを聞く")] {
            let index=label(number,size:13,weight:.heavy,color:pink)
            index.widthAnchor.constraint(equalToConstant:26).isActive=true
            let row=UIStackView(arrangedSubviews:[index,label(text,size:13,weight:.medium,color:ink.withAlphaComponent(0.85))]);row.alignment = .top;row.spacing=12;steps.addArrangedSubview(row)
        }
        content.addArrangedSubview(card(steps,color:UIColor(red:1,green:0.94,blue:0.96,alpha:0.95)))
        let note=label("開始の声の後、吹き出しの文字を読みます。\n停止はiPhoneの画面配信表示から。",size:12,weight:.medium,color:UIColor.white.withAlphaComponent(0.94))
        content.addArrangedSubview(note)
        let privacy=label("画面・コメントの保存や送信はしません。\nイヤホン推奨。ルームへの音声送出は未対応です。\n装飾やテーマにより認識できない場合があります。",size:11,weight:.regular,color:UIColor.white.withAlphaComponent(0.80))
        content.addArrangedSubview(privacy)
        content.addArrangedSubview(label("軽量・吹き出し優先 ・ v0.8",size:10,weight:.semibold,color:UIColor.white.withAlphaComponent(0.60)))
        // No animated background. Release the decoded photograph while GRAVITY is
        // foreground; the broadcast extension never bundles or loads this asset.
        observers.append(NotificationCenter.default.addObserver(forName:UIApplication.didEnterBackgroundNotification,object:nil,queue:.main) { [weak self] _ in self?.photograph.image=nil })
        observers.append(NotificationCenter.default.addObserver(forName:UIApplication.willEnterForegroundNotification,object:nil,queue:.main) { [weak self] _ in self?.loadPhoto() })
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews();CATransaction.begin();CATransaction.setDisableActions(true);shade.frame=photograph.bounds;CATransaction.commit()
    }
    @objc private func openDiagnostics() {present(DiagnosticsViewController(),animated:true)}
    private func loadPhoto() {
        if let path=Bundle.main.path(forResource:"FloralBackground",ofType:"png") {photograph.image=UIImage(contentsOfFile:path)}
    }
    private func label(_ text:String,size:CGFloat,weight:UIFont.Weight,color:UIColor)->UILabel {
        let label=UILabel();label.text=text;label.numberOfLines=0;label.textColor=color
        label.font=UIFontMetrics(forTextStyle:.body).scaledFont(for:UIFont.systemFont(ofSize:size,weight:weight));label.adjustsFontForContentSizeCategory=true
        return label
    }
    private func card(_ content:UIView,color:UIColor)->UIView {
        let card=UIView();card.backgroundColor=color;card.layer.cornerRadius=28
        card.layer.shadowColor=UIColor.black.cgColor;card.layer.shadowOpacity=0.20;card.layer.shadowRadius=16;card.layer.shadowOffset=CGSize(width:0,height:8)
        content.translatesAutoresizingMaskIntoConstraints=false;card.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:card.leadingAnchor,constant:20),content.trailingAnchor.constraint(equalTo:card.trailingAnchor,constant:-20),content.topAnchor.constraint(equalTo:card.topAnchor,constant:22),content.bottomAnchor.constraint(equalTo:card.bottomAnchor,constant:-22)])
        return card
    }
    deinit {for observer in observers {NotificationCenter.default.removeObserver(observer)}}
}
