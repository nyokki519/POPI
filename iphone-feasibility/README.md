# iPhone単体 GRAVITYコメント読み上げ：成立条件の調査

調査日：2026-10-10。**iPhoneで動作確認した結果ではない。** Linux環境で公式仕様を確認し、最小のネイティブ検証コードを用意した。追加でGitHub ActionsのmacOS環境からApple iOS SDKによる型検査・リンクを実行して成功した。署名済みIPAとiPhone実機での動作検証は未実施。

## 結論

|工程|資料から確認できること|未確認事項|
|---|---|---|
|画面配信開始|ReplayKitのRPSystemBroadcastPickerViewで利用者が配信拡張を選択できる|GRAVITY実画面がその端末／iOSで正常に取得されるか|
|映像取得|RPBroadcastSampleHandlerに映像・音声バッファが渡される|GRAVITYとの同時利用、保護された表示、長時間の安定性|
|文字認識|VisionのVNRecognizeTextRequestが画像から文字を認識する|GRAVITYの日本語コメント認識精度、拡張内のメモリ・速度|
|新規コメント検出|既存Swift検出器は30テストと模擬入力でPASS|実際のGRAVITYレイアウト・流速|
|自分が聞く読み上げ|AVSpeechSynthesizerと音声セッションは検証候補|配信拡張内での再生可否、バックグラウンド継続、GRAVITYとの音声競合|
|ROOMへ送信|ReplayKitが取得した音声を配信側で加工することと、他アプリのマイク入力に注入することは別の経路|GRAVITY側へ任意音声を直接入力できる公開手段は確認できない|

したがって **PRIVATEは実機実験に進む余地があるが、成立したとは言えない。iPhone単体でROOMへ自動送信できるという約束はできない。**

## なぜMac用アプリの単純な移植では済まないか

iPhoneでGRAVITYを前面に出すと、こちらの通常アプリは背景に回る。画面配信拡張と通常アプリは別プロセスであり、OCR結果を共有領域に置くだけで、停止／休止した通常アプリが自動的に起きて発話するとは限らない。Appleの一般的な拡張機能の制約を、画面配信拡張の固有の寿命へそのまま当てはめて断定はしない。一方、画面配信中というだけで任意の音声再生が許されるとも推定しない。

AVAudioSessionのmixWithOthersは、再生音を他の再生音と混ぜる指定である。GRAVITYのマイク入力へ音を渡す指定ではない。GRAVITYによる音声セッションの再設定、Bluetooth／イヤホン経路、マイクとの競合も実機で確認が必要。

## 用意した最小検証コード

`BroadcastProbe.swift`：Broadcast Upload Extensionのハンドラ。映像を750ms以上の間隔で日本語OCRにかけ、フレーム数・認識行数・処理時間のみを記録。15秒以上の間隔で固定のテスト文を発話する試験を行う。認識したコメントや画像は保存・アップロードしない。

AppleはCMSampleBufferがprocessSampleBufferの戻りまでのみ有効と明記しているため、OCRはコールバック内で同期処理する。非同期に元バッファを保持しない。将来高速化する際は独立したコピーとメモリ上限が必要。

このコードは**Apple iOS SDKで、`-application-extension`を指定した型検査とiOSシミュレーター向けライブラリのリンクにPASS**。同じCIでSwiftコアのテスト・模擬再生も成功した。ただし、実際の画面配信・読み上げを動作させた結果ではなく、完成アプリではない。

検証実行： https://github.com/nyokki519/POPI/actions/runs/38032710405
詳細： apple-sdk-validation.json

## 実機で必要な合否判定

1. iPhone向け署名済みテストアプリ＋配信拡張をMac/Xcodeでビルドし、iPhoneにインストールできること。
2. 利用者が画面配信を開始しGRAVITYへ戻った後、映像と日本語コメントの認識が続くこと。回転・背景移行・配信停止を含める。
3. 固定テスト文が実際に聞こえること。音声合成の開始／終了コールバックだけで合格にしない。GRAVITYの受聴とマイクON/OFF、イヤホン・Bluetoothを分けて確認。
4. コメントが来ない間隔を含む長時間の動作で、拡張終了・音声停止・無制限メモリ増大がないこと。
5. ROOMは別の参加者で受聴を確認。iPhone自身から音が出たことをROOM配信成功と扱わない。直接注入の経路が成立しなければ、その要件は不成立と報告する。

GitHub ActionsではApple SDKの検査まで進められたが、今ある環境ではiPhoneへのインストールと2以降の実機動作は実行できない。検証のためにAppleアカウント登録・課金・端末接続・配信開始を勝手に実行していない。背景維持目的の無音再生や、OS制限の回避に頼らない。

## 公式資料

- ReplayKitの配信ハンドラ： https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler
- バッファ処理・寿命： https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/processsamplebuffer(_:with:)
- 配信選択UI： https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview
- Vision文字認識： https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- 音声のmixWithOthers： https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers
- 背景モード： https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
- 一般的な拡張の通信・制約（ReplayKit固有制約と混同しない）： https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html
