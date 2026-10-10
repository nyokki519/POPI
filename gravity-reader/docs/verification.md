# 検証結果 — 2026-10-10

## 実装したもの

Native AppKit UI、コメント範囲選択、ScreenCaptureKit撮影、Vision日本語OCR、CoreAudio出力列挙・選択、AVSpeechSynthesizerのPCM音声をAVAudioEngineに渡す経路、PRIVATE/ROOM、音声・速度設定、発話キュー、停止・再選択・切断監視、模擬入力、接続診断、Mac上のビルドランチャー。

## この環境で実行して確認

- 実行環境：Linux x86_64、公式Swift6.0.3、Swift5言語モード。
- コメント検出・発話キュー・世代番号ゲート：30/30 PASS。スタブからの失敗を確認して実装。高速入力・未確定行・密な行順について追加の失敗→成功を確認。
- 模擬OCR行24フレームを、製品と同じ検出器・キューに流し、新規4件（同文2件を含む）の順序・件数が期待と一致。
- Mac固有Swiftコード：Swiftパーサーによる構文検査PASS。**Mac SDKによる型検査／リンクではない。**
- ランチャー／ビルド／テストシェル：bash構文検査PASS。Linuxでは終了69でMac専用処理を拒否することも確認。
- 独立コードレビューで検出した画面準備の世代競合、バッファ完了フラグの遅延参照、未確定コメントの消失、稼働中オーディオ出力変更を修正。
- 原文・画像のファイル書き出し／送信処理は実装していない。Mac設定保存とビルドログのみ。

実行ログ：reports/core-and-replay.txt。模擬コアの所要時間を実際のOCR・TTS遅延と混同しない。

## Mac／iPhone実機確認待ち

- Macでのコンパイル・リンク。初回ランチャーがコアテストと日本語画像OCR／CoreAudio列挙を自動実行する。
- macOS画面収録権限のダイアログ・許可・再起動、マルチモニター／Retinaの選択座標。
- GRAVITY実画面のOCR精度、投稿者名・折り返し・画面移動・スクロール速度。
- 日本語音声PCM生成と、連続発話・即時停止・声変更・デバイス切断時の再生。
- 物理／仮想出力選択、PRIVATEとROOM切替、実機での遅延測定。
- iPhoneへのマイク入力と、GRAVITYの参加者に音が届くこと。アプリだけでは自動確認不可。
- Apple Silicon／Intelの双方の実ビルドと、ダウンロード後の初回OS許可。

Mac固有機能の実装はあるが、これらの動作確認をLinuxコアのテスト合格で代用していない。

## 接続方式の資料

Apple iPhone Mirroring： https://support.apple.com/en-us/120421
Apple本文： “Access to the iPhone camera and mic is not available in iPhone Mirroring”. ROOMでは別の画面表示方式と音声入力経路の実機検証が必要。
QuickTime： https://support.apple.com/guide/quicktime-player/record-a-movie-qtp356b55534/mac
