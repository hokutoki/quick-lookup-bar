# 調べものバー (Quick Lookup Bar)

macOS用の調べものランチャーです。Shiftを2回押すと画面中央に入力欄が開き、打った言葉をすぐ各サービスに送れます。開くたびに「物書堂 辞書」が選ばれ、言葉を入力してEnterを押すと物書堂で検索します。

| キー | 送り先 |
| --- | --- |
| Shift+1 | 辞書 by 物書堂（全辞書・前方一致） |
| Shift+2 | ChatGPT（Web） |
| Shift+3 | Claude |
| Shift+4 | Grok |
| Shift+5 | Google |
| Shift+6 | ChatGPTアプリの「あなたのdot」 |
| Shift+7 | Grok Botアプリの入力欄 |
| Shift+8 | 音声入力（ChatGPTへ送信） |

Enterで送信、Escで閉じます。テンキーの数字にも対応しています。

入力欄は開くたびに空になります。コピーした内容は自動表示せず、必要なときに⌘Vで貼り付けます。クリップボード自体の内容は変更しません。

## ビルド

```sh
./build.sh
# 署名IDを指定する場合
SIGN_ID="Apple Development: ..." ./build.sh
```

初回はシステム設定の「アクセシビリティ」で 調べものバー.app を許可してください（Shiftの2回押しと他アプリへの入力に必要です）。音声入力にはマイクと音声認識の許可が必要です。
