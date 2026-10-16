# WindowsからiPhoneへ入れる方法

MacやXcodeを使わずに導入するための **署名前IPA** を用意します。WindowsでiOSアプリをコンパイルするのではなく、Apple SDKを使うクラウドビルドで作ったIPAを、WindowsのAltServer / iPhoneのAltStore Classicで自分のApple Accountに署名して導入する方法です。

**Windowsでの実際のインストールは未検証です。** IPAのビルド・構造検査と、利用者のWindows・Apple Accountでの署名／実機動作は別の工程です。App Store配布版や、署名なしで全端末へ入るものではありません。

## 用意するもの

- Windows 10以降のPC、iPhone、USBケーブル、Apple Account。
- AltServer for Windows と AltStore Classic：公式 https://altstore.io/ 。AltStore PALとは別です。
- AltServer公式手順に対応するiTunesとiCloud。Microsoft Store版ではなくApple配布版が必要になることがあるため、導入時に公式Windowsガイドを確認してください。
- 公式Windowsガイド：https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows

公式ページの本文は今回の環境では取得制限があり、最新の手順全文は確認できていません。以下はAltStore Classicの通常の流れです。表示が異なる場合は公式ガイドを優先します。

## 初回

1. WindowsにAltServerと必要なAppleドライバーを入れ、iPhoneをUSB接続します。iPhoneをロック解除し「このコンピュータを信頼」を選びます。
2. AltServerを起動し、通知領域のアイコン → Install AltStore → 接続したiPhoneを選びます。Apple Accountで認証します。パスワードはこのチャットや本アプリには入力しません。
3. iPhoneの設定 → 一般 → VPNとデバイス管理で自分の開発者を信頼します。必要なら設定 → プライバシーとセキュリティ → デベロッパモードを有効にして再起動・確認します。
4. 次のIPAをiPhoneでダウンロードします。
   https://github.com/nyokki519/POPI/blob/main/gravity-iphone/dist/Okama-Sukkiri-iPhone-unsigned.ipa
   GitHubの「Download raw file」から保存してください。ZIPのソースコードではなく、拡張子 `.ipa` のファイルです。
5. Windows側のAltServerを動かした状態で、iPhoneのAltStore Classic → My Apps → ＋からIPAを選択します。アプリ拡張の扱いを聞かれたら **Uploadを含む拡張を保持** してください。削除すると画面配信のコメント認識が使えません。
6. 「オカマ読み上げスッキリアプリ」を開き、まず「読まれないときの確認」→「音声だけテスト」で出力を確認します。

## 更新と注意点

- 無料Apple Accountの署名は通常7日で期限が切れます。期限前にAltServerへ接続してAltStoreでRefreshします。更新時は新しいIPAを同じ手順で選びます。
- 無料署名には有効なアプリ数・App ID登録数の制限があります。配信拡張もApp IDを使用するため、AltStoreの表示を確認してください。
- 別のiPhoneでは、その端末にもAltStoreの導入と署名が必要です。
- Windowsのファイアウォールや同一ネットワークの制限でAltServerに接続できない場合は、まずUSB接続で確認します。
- 「整合性を確認できません」は、未署名IPAを直接開いても解消しません。AltStoreでの署名が必要です。拡張を保持しても失敗する場合はエラー全文で切り分けます。
- この手順でのGRAVITY同時使用、最新iOS全版、すべてのWindows構成への対応は未検証です。有料登録や課金は行っていません。
