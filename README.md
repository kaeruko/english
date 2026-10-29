# English Replay

英語音声を端末内で文字起こしし、字幕の単語をタップするとその位置へ戻れるiOSアプリです。

## 必要環境

- Xcode 26以降
- iOS 26以降の実機
- Apple Developer Programの開発チーム
- 初回の英語音声モデル取得時のみインターネット接続

SpeechAnalyzerはシミュレーターや一部の端末で利用できない場合があるため、文字起こしは実機で確認してください。

## 実行

1. `EnglishReplay.xcodeproj`をXcodeで開きます。
2. `EnglishReplay`ターゲットのSigning & Capabilitiesで自分のTeamを選びます。
3. 必要ならBundle Identifierを固有の値へ変更します。
4. iOS 26以降のiPhoneを選び、実行します。
5. `+`からMP3を読み込み、`文字起こしを開始`を押します。
6. 初回は音声認識を許可し、英語モデルのダウンロード完了を待ちます。

## 主な操作

- 単語をタップ: その単語の0.4秒前から再生
- 時刻をタップ: 字幕ブロックの先頭から再生
- `もう一度`: 現在の字幕ブロックを再生し直す
- `前の文` / `次の文`: 字幕ブロック間を移動
- 右上の設定: タップ時の助走時間を0〜0.8秒で変更
- 字幕を手動スクロール: 自動追従を停止。`再生位置`で追従を再開

音声、字幕、再生位置は端末のApplication Support内だけに保存します。外部APIは使用しません。

## Windowsからの開発

`main`へのpushとPull Requestで、GitHub ActionsのmacOS 26環境がXcode 26を使って自動ビルドします。署名は行わず、まずコンパイルできることを確認するワークフローです。

- Actions: `.github/workflows/ios-build.yml`
- 成功時: iOS Simulator用の`.app`を7日間Artifactとして保存
- 失敗時: `xcodebuild.log`を7日間Artifactとして保存

実機配布とTestFlightには、Apple Developerの証明書、Provisioning Profile、App Store Connect上のアプリ登録が別途必要です。これらの秘密情報はGitへコミットしません。
