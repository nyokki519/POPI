import UIKit
import ReplayKit
final class SetupViewController:UIViewController {
    private let top=UISlider(),bottom=UISlider(),rate=UISlider()
    private let values=UILabel()
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor = .systemBackground
        top.minimumValue=0;top.maximumValue=0.8;top.value=0.45
        bottom.minimumValue=0.1;bottom.maximumValue=1;bottom.value=0.9
        rate.minimumValue=0.35;rate.maximumValue=0.6;rate.value=0.5
        let text=UILabel();text.numberOfLines=0;text.text="コメント範囲の設定\n\n画面の上端を0%、下端を100%として、GRAVITYのコメント欄を指定してください。開始後にGRAVITYへ戻ります。最初の画面は読み上げません。"
        values.numberOfLines=0
        let start=UIButton(type:.system);start.setTitle("この設定で開始",for:.normal);start.addTarget(self,action:#selector(begin),for:.touchUpInside)
        let cancel=UIButton(type:.system);cancel.setTitle("キャンセル",for:.normal);cancel.addTarget(self,action:#selector(cancelSetup),for:.touchUpInside)
        var views:[UIView]=[text,values]
        for (name,slider) in [("コメント欄の上端",top),("コメント欄の下端",bottom),("読み上げ速度",rate)] {
            let label=UILabel();label.text=name;views += [label,slider];slider.addTarget(self,action:#selector(update),for:.valueChanged)
        }
        views += [start,cancel]
        let stack=UIStackView(arrangedSubviews:views);stack.axis = .vertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(stack);NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:20)])
        update()
    }
    @objc private func update() {
        let c=config();values.text=String(format:"範囲 %.0f〜%.0f%% / 速度 %.2f",c.top*100,c.bottom*100,c.rate)
    }
    private func config()->ReaderConfiguration {ReaderConfiguration(["top":NSNumber(value:top.value),"bottom":NSNumber(value:bottom.value),"rate":NSNumber(value:rate.value)])}
    @objc private func begin() {
        let c=config()
        extensionContext?.completeRequest(withBroadcast:URL(string:"https://localhost/gravity-private")!,setupInfo:["top":NSNumber(value:c.top),"bottom":NSNumber(value:c.bottom),"rate":NSNumber(value:c.rate)])
    }
    @objc private func cancelSetup() {extensionContext?.cancelRequest(withError:NSError(domain:"GravityReader",code:1,userInfo:[NSLocalizedDescriptionKey:"設定をキャンセルしました"]))}
}
