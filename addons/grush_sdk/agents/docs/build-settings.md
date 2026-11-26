# 推奨設定でビルドする

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#build

<a id="build"></a>
## 推奨設定でビルドする

Unity と Godot の SDK は、[ゲームの最適化ガイド](optimization.md) のおすすめ設定をまとめて適用し、そのまま GameRush に上げられる形でビルドできます。エディタの画面からでも、CLI（CI）からでも使えます。

**適用した設定は元に戻しません。Unity の Player Settings と Godot の `export_presets.cfg` に残る項目は、バージョン管理の差分で確かめられます。Unity の Build Settings 側の項目（Development Build など）は `Library/` に残るので、差分には出ません。**

| 終了コード | 意味 |
|---|---|
| 0 | ビルドできた（目安の 15MB を超えたときは警告だけ出す） |
| 1 | ビルド・書き出しに失敗した（Godot は Web の書き出しテンプレートが入っていないときもここ） |
| 2 | 引数・出力先・エンジンの環境が足りない（Unity の WebGL モジュールが無い、Godot が 4.3 より古い、Unity で GameRush のビルド以外のファイルがあるフォルダを出力先にした、Godot でプロジェクト直下や `addons/` を出力先にした、など） |
| 3 | 想定外の例外（Unity のみ） |
| 4 | できたビルドが GameRush のアップロード条件に合わない（Unity はファイルの種類・loader / framework / wasm / data のそろい方・2000 ファイル・100MB、Godot は 2000 ファイル・100MB を見る） |

<a id="build-unity"></a>
### Unity

- **GameRush > GameRush ウィンドウ** の「推奨設定でビルド」に、いまの設定とおすすめの値が並ぶ。ログインしていなくても使える
- **推奨設定を適用** で、変わる項目を確かめてから適用する。**推奨設定でビルド** は適用してから WebGL でビルドする
- ビルドが終わると、出力先がそのままアップロード欄に入る（[Unity Editor からアップロードする](editor-upload.md#editor-upload)）
- メニューの **GameRush > 推奨設定を適用** / **GameRush > 推奨設定でビルド** からも呼べる
- Build Settings で有効にしたシーンをビルドする。出力先の既定は `Build/GameRush` で、ビルドのたびに中身を作り直す（`Assets/` などプロジェクトの中の大事なフォルダは選べない）

```bash
Unity -batchmode -quit -projectPath . -buildTarget WebGL \
  -executeMethod GRushSdk.Editor.GRushBuild.BuildRecommended \
  -grushOutput Build/GameRush
```

ログは `[grush-build]` で始まり、変えた設定は `set <項目>: <前> -> <後>` の形で1行ずつ出ます。

<a id="build-godot"></a>
### Godot 4

- [grush-sdk-godot](https://github.com/gamerush-jp/grush-sdk-godot) の `addons/grush_sdk_build/` もプロジェクトの `addons/` へコピーし、**Project Settings > Plugins** で **GameRush SDK Build** を有効にする（`grush_sdk` とは別のプラグイン）
- **Project > Tools > GameRush: 書き出し設定を確認** で、いまの設定とおすすめの値を比べて適用できる
- **Project > Tools > GameRush: 推奨設定で書き出す** で、「GameRush Web」プリセットを作って書き出す。出力は `index.html` / `index.js` / `index.wasm` / `index.pck` の名前になるので、改名せずにそのまま上げられる
- Godot 4.3 以降と、Web の書き出しテンプレートが要る
- Export の画面を開いたままだと新しいプリセットが見えないので、開き直す

```bash
godot --headless --path . \
  --script res://addons/grush_sdk_build/grush_build_cli.gd \
  -- --output build/gamerush
```

`--no-mobile-textures` を付けるとスマホ向けのテクスチャ圧縮（ETC2 / ASTC）を入れません。`--preset-only` を付けるとプリセットを書くだけで書き出しはしません。
