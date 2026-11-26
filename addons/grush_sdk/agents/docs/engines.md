# 対応エンジンと書き出し

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/engines#formats ・ https://gamerush.jp/engines#supported ・ https://gamerush.jp/engines#unity ・ https://gamerush.jp/engines#godot ・ https://gamerush.jp/engines#gdevelop ・ https://gamerush.jp/engines#phaser ・ https://gamerush.jp/engines#web ・ https://gamerush.jp/engines#network ・ https://gamerush.jp/engines#troubleshooting

GameRush へ掲載できるのは、Unity（WebGL）・Godot 4・GDevelop・Phaser で書き出したビルドと、`index.html` のある静的サイト（Web）です。Studio の画面から上げたビルドは、中身からどれで作ったかを判別し、そのエンジンに合わせて取り込みます。ほかの開発環境で作ったゲームも、ブラウザで動く `index.html` 一式を書き出せれば Web として上げられます。

<a id="formats"></a>
## 受け取れる形

Studio のアップロード画面で、ビルドを zip かフォルダで指定してください。zip の中身がひとつのフォルダに包まれている場合は、こちらでそのフォルダを剥がしてから探すので、包んだままで構いません。

HTML 1枚で動くゲームは、HTML ファイルを1つ選ぶかドロップするか、「HTML を貼り付け」に本文を貼って投稿できます。ファイルの名前によらず `index.html` として、Web（[Web](engines.md#web)）と同じに取り込みます。ほかのファイルを置けないので、外部のサイトのスクリプトを読み込む HTML は、送る前にお知らせして受け付けません。「HTML を貼り付け」には、ChatGPT や Claude などの AI チャットにゲームを作ってもらうためのプロンプトをコピーするボタンがあります。

エンジンはビルドの中身から自動で判別します。Unity は Build フォルダの4ファイル、Godot は同じ名前の .pck・.wasm・.js、GDevelop はいちばん上の `index.html`・`gd.js`・`runtimegame.js`・`data.js`、Phaser は JavaScript に含まれる Phaser 本体を手がかりにし、どれにも当たらなければ Web として取り込みます。

使えるファイルの種類は次のとおりです。末尾に `.gz` / `.br` を付けた圧縮形も、元の種類と同じ扱いです。

| 分類 | 拡張子 |
|---|---|
| HTML・スクリプト・データ | `.html` `.js` `.wasm` `.data` `.json` `.css` `.txt` `.csv` `.xml` `.yml` `.yaml` `.webmanifest` |
| 画像 | `.png` `.jpg` `.jpeg` `.gif` `.bmp` `.webp` `.svg` `.ico` `.ktx` `.ktx2` `.pvr` `.basis` |
| 音声・動画 | `.mp3` `.m4a` `.aac` `.ogg` `.wav` `.mp4` `.webm` |
| フォント | `.ttf` `.otf` `.woff` `.woff2` `.fnt` |
| エンジン・ツールの形式 | `.unityweb` `.pck` `.bytes` `.bundle` `.assetbundle` `.bin` `.dat` `.bank` `.ress` `.resource` `.atlas` `.skel` `.glsl` `.frag` `.vert` `.tmx` `.tsx` `.tmj` `.tsj` `.glb` `.ldtk` |

- 拡張子の無いファイル、`.mjs`、`.htm`・`.xhtml` のように HTML として開ける別の拡張子は受け付けません。HTML は `.html` にしてください。
- Unity と判別されたビルドでは、表に無い種類のファイルを取り込みのときに黙って除きます。ただし `StreamingAssets` の下にあるものは除かず、アップロードできません。
- Unity 以外では、表に無い種類のファイルが1つでもあるとアップロードできません。例外として、GDevelop・Phaser・Web と判別されたビルドのソースマップ（`.js.map` / `.css.map`）は取り込みのときに除きます。Godot と判別されたビルドでは除かないので、ソースマップを入れずに書き出してください。
- `__MACOSX` フォルダ・`.DS_Store`・`Thumbs.db` と、圧縮した HTML（`.html.gz` / `.html.br`）は自動で除きます。HTML は圧縮せずに入れてください。

API と、Unity `v1.14.0` より古い Unity Editor の GameRush メニューから上げたビルドは、この判別を通らず、送ったファイルをそのまま使います。Unity `v1.14.0` 以降の GameRush メニューは Unity のビルドだけを上げます。

<a id="supported"></a>
## 対応している開発環境

- Unity（WebGL ビルド。Enable Multithreading はオフ）
- Godot 4.3 以降（Web 書き出し。Thread Support はオフ）
- GDevelop 5（HTML5 書き出し）
- Phaser（Web ビルド）
- Web（`index.html` のある静的サイト。作ったツールは問いません）

ほかのツール（たとえば Scratch・Construct 3・RPGツクール MV/MZ・microStudio・Bitsy など）で書き出した HTML5 一式も、Web として取り込める場合があります。動作を確かめているのは、Scratch の作品を TurboWarp Packager で zip に書き出したものです。ほかのツールで書き出したものがそのまま動くとはお約束できません。また、含まれるファイルの種類によってはアップロードできない場合があります。

TurboWarp Packager では、出力形式に zip を選び、自動再生（autoplay）をオンにしてください。1枚の HTML にまとめる形式は確かめていません。フィードではゲームが開いたらそのまま始まるので、自動再生をオフにした書き出しは確かめていません。

Roblox や UEFN、ネイティブ専用のエンジンは、ブラウザで動く成果物を持ち出せないため掲載できません。

<a id="unity"></a>
## Unity

WebGL ビルドの出力フォルダを、そのまま zip にしてアップロードしてください。Studio の画面から上げると、`Build` フォルダの中身（loader / framework / wasm / data の4ファイル）から Unity と判別し、起動に必要な設定を組み立てます。Unity `v1.14.0` 以降の Unity Editor の GameRush メニューから上げたビルドでも、同じ設定を組み立てます。

Unity と判別されたビルドは、出力フォルダの `index.html` と `TemplateData` を使わずに、GameRush 側のプレイヤーで起動します。このプレイヤーはローディングバーを出し、起動に要るファイルを最優先で読み込み、ビルドに同梱された Service Worker を止めます。

圧縮せずに書き出したファイルを、こちらで圧縮するのは Studio の画面から上げたときだけです。Editor から上げるときは **Compression Format** を Brotli にして書き出してください。Unity `v1.14.0` 以降の Editor から上げた `.unityweb` のビルドだけは、確定のときに Brotli へ圧縮し直します。

**Enable Multithreading** はオフにしてください。マルチスレッドのビルドは `SharedArrayBuffer` を使うため、GameRush では起動しません。アップロードはできてしまうので、書き出す前に確かめてください。

書き出し設定でロード時間を詰めるこつは、**Compression Format** を Brotli にして **Decompression Fallback** を切ることです。ほかの設定と、おすすめ設定でまとめてビルドする方法は [ゲームの最適化ガイド](optimization.md) にあります。

<a id="godot"></a>
## Godot 4

- Web プリセットで書き出すと、`.html` / `.js` / `.wasm` / `.pck` / `.png` が出力されます。出力フォルダをそのまま zip にしてください。改名は要りません。
- Godot と判別されたビルドは、書き出した `.html` を使わずに、GameRush 側のプレイヤーで起動します。このプレイヤーはローディングバーを出し、起動に要るファイルを最優先で読み込みます。`.html` からは Godot の起動の設定だけを読みます。
- **Custom HTML Shell** と **Head Include** は使えません。どちらも書き出した `.html` の中身なので、GameRush のプレイヤーには載りません。既定の `.html` の `#status` などの要素に `JavaScriptBridge` から触るゲームも動きません。
- `.pck` / `.wasm` / `.js` の名前は大文字と小文字まで同じにしてください。`ServiceWorker` と、`__` で始まる名前と、`%` `?` `#` `:` を含む名前は使えません。
- GameRush で動くのは、Godot 4.3 以降で **Thread Support** を切って書き出したビルドだけです。スレッドありのビルドは `SharedArrayBuffer` を使うため、GameRush では起動しません。アップロードはできてしまうので、書き出す前に確かめてください。Godot 4.3 以降は Thread Support を切った書き出しが既定です。

<a id="gdevelop"></a>
## GDevelop

**File** メニューの **Export** から **Web** を選び、**Export as HTML5 Game** で出力フォルダに書き出してください。出力フォルダを、`index.html` がいちばん上にある状態のまま zip にしてアップロードします。

- GDevelop と判別されたビルドは、書き出した `index.html` を使わずに、GameRush 側のプレイヤーで起動します。このプレイヤーはローディングバーを出します。`index.html` からは読み込むスクリプトの一覧だけを読みます。
- 基準解像度は、プロジェクトの設定のゲームの解像度（幅と高さ）を使います。Studio で基準解像度を入れた場合は、入れた値を使います。
- **`index.html` を手で書き換えた内容は、GameRush のプレイヤーには載りません。`index.html` が外部のサイトのスクリプトを読み込んでいるときや、ビルドに無いファイルを読み込んでいるときは、GDevelop として取り込まず、Web として `index.html` をそのまま使います。**
- 3D のモデル（`.glb`）と LDtk のタイルマップ（`.ldtk`）も上げられます。ソースマップ（`.js.map`）は取り込みのときに除きます。

<a id="phaser"></a>
## Phaser

ビルドした出力フォルダを、`index.html` がいちばん上にある状態で zip にしてアップロードしてください。書き出した `index.html` はそのまま使います。

- **アセットの参照は相対パスにしてください。Vite なら `vite.config` の `base` を `"./"` に、webpack なら `output.publicPath` を `""` にします。**
- ゲームはビルドごとのサブディレクトリから配信されるため、`/assets/...` のようなルート絶対パスは別の場所を指してしまいます。`index.html` の `src` / `href` にルート絶対パスがあるとアップロードできません。JavaScript の中で組み立てるパスや CSS の `url()` は確かめないので、ビルド設定で相対パスにしてください。
- HTML ファイルは1つあたり 5MB までです。それを超える `.html` があるとアップロードできません。
- ソースマップ（`.js.map` / `.css.map`）は取り込みのときに除きます。読み込み量を減らすためで、ゲームの動作には影響しません。

Phaser と判別するのは、ビルドの JavaScript に Phaser 本体が見つかったときです。CDN から Phaser を読み込むビルドや、Phaser 本体を含む JavaScript を Brotli で事前圧縮した `.js.br` だけにしたビルドは、Phaser 本体が見つからないので Web として取り込みます。どちらでも `index.html` をそのまま使います。

GameRush の SDK は TypeScript の型つきで、Phaser のプロジェクトへ npm で入れて import できます（[TypeScript](setup-javascript.md#typescript)）。

<a id="web"></a>
## Web（その他のツール）

Unity・Godot・GDevelop・Phaser のどれとも判別されなかったビルドは、Web として取り込みます。`index.html` がいちばん上にある状態で zip にしてアップロードすると、`index.html` をそのまま使います。

- **アセットの参照は相対パスにしてください。`/assets/...` のようなルート絶対パスは、ビルドごとのサブディレクトリから配信するときに別の場所を指してしまうため、`index.html` の `src` / `href` にあるとアップロードできません。**
- HTML ファイルは1つあたり 5MB までです。それを超える `.html` があるとアップロードできません。
- 使えるファイルの種類（[受け取れる形](engines.md#formats)）・合計サイズ（100MB まで）・ファイル数（2000 まで）の条件は、ほかのエンジンと同じです。ソースマップ（`.js.map` / `.css.map`）は取り込みのときに除きます。
- GameRush のローディングバーは出ません。読み込み中の表示はゲームの側で用意してください。

<a id="network"></a>
## ゲームから通信できる先

ゲームは、ゲーム自身のオリジン（`{ゲームの ID}.g-rush.org`）のほかは、次の表の先とだけ通信できます。ほかの先への通信と読み込みは、ブラウザが止めます。他の利用者に見せる中身を GameRush の外に置かず、通報されたときに運営が確かめられるようにするためです（[ゲーム掲載ポリシー](https://gamerush.jp/import-policy)）。

| 用途 | 通信できる先 |
|---|---|
| 画像の読み込みと `fetch` | SDK がゲームへ渡すアバター画像の URL（`https://media.g-rush.org`、`https://lh3.googleusercontent.com/a/`、`https://lh3.googleusercontent.com/a-/`、`https://lh4.googleusercontent.com/a/`、`https://lh4.googleusercontent.com/a-/`、`https://lh5.googleusercontent.com/a/`、`https://lh5.googleusercontent.com/a-/`、`https://lh6.googleusercontent.com/a/`、`https://lh6.googleusercontent.com/a-/`、`https://cdn.discordapp.com/avatars/`、`https://cdn.discordapp.com/embed/avatars/`、`https://pbs.twimg.com/profile_images/`、`https://abs.twimg.com/sticky/default_profile_images/`、`https://profile.line-scdn.net`、`https://obs.line-scdn.net`） |
| スクリプトの読み込み | 公式の JavaScript SDK（`https://cdn.jsdelivr.net/gh/gamerush-jp/`、`https://cdn.jsdelivr.net/gh/gamerush-cc/`） |
| スタイルシートの読み込み | Google Fonts（`https://fonts.googleapis.com`） |
| フォントの読み込み | Google Fonts（`https://fonts.gstatic.com`） |

運営がゲームごとに個別に許可した先（取引先の API など）とも、画像の読み込みと `fetch`・WebSocket で通信できます。個別に許可した先は、そのゲームの紹介の「このゲームが通信する先」に載せます。

- 上の先と、運営がそのゲームに個別に許可した先のほかに、自分のサーバーや外部のサービス（広告・アクセス解析・データベース・ランキングのサービスなど）とは通信できません。`fetch`・`XMLHttpRequest`・WebSocket のどれでも同じです。
- 外部のサイトや CDN からスクリプト・画像・音声・フォントを読み込めません。ゲームに要るファイルはビルドに含めてください。
- セーブ・ランキング・利用者どうしのやりとり・マルチプレイは、GameRush の SDK の機能を使ってください（[SDK ガイド](../AGENTS.md)）。
- WebRTC などで利用者の端末どうしを直接つなぐことは、ブラウザでは止まりませんが、掲載できません。
- ゲームの中のリンク（`<a target="_blank">` と `window.open`）で開けるのは、次のサイトとそのサブドメインの https のページだけです: `x.com`・`twitter.com`・`bsky.app`・`youtube.com`・`youtu.be`・`tiktok.com`・`instagram.com`・`discord.com`・`discord.gg`・`nicovideo.jp`・`note.com`・`apps.apple.com`・`play.google.com`・`store.steampowered.com`・`itch.io`・`unityroom.com`・`freem.ne.jp`・`plicy.net`・`booth.pm`・`fanbox.cc`・`ci-en.net`・`dlsite.com`・`github.com`。運営がゲームごとに個別に許可したサイトも開けます（そのゲームの紹介の「このゲームが通信する先」に載せます）。Web では新しいタブで、アプリではアプリの中のブラウザで、LINE では外のブラウザで開きます。ほかのサイトへのリンクは開きません。リンクで開けても、そのサイトとは通信できません。
- リンクは、利用者がゲームを押したりキーを押したりした直後にだけ開きます。1回の操作で開くのは1つです。

<a id="troubleshooting"></a>
## うまくいかないとき

- Unity のビルドが Unity と判別されない（ローディングバーが出ない）場合は、zip の中に `Build` フォルダの4ファイル（`.loader.js` / `.framework.js` / `.wasm` / `.data`。`.loader.js` 以外は `.gz` / `.br` / `.unityweb` で圧縮したものでも構いません）が1つずつそろっているかを確認してください。
- Godot として弾かれる場合は、同じ名前の `.pck` / `.wasm` / `.js` がそろっているかと、名前に使えない文字が無いか（[Godot 4](engines.md#godot)）、Godot 4 の既定の HTML シェルで書き出した `.html` が一緒に入っているかを確認してください。書き出した `.html` のほかに入れた、5MB を超える `.html` もアップロードできません。
- GDevelop のビルドが GDevelop と判別されない（ローディングバーが出ない）場合は、zip のいちばん上に、書き出したままの `index.html`・`gd.js`・`runtimegame.js`・`data.js` がそろっているかと、`index.html` が外部のサイトのスクリプトを読み込んでいないかを確認してください。
- Phaser や Web として弾かれる場合は、`index.html` がいちばん上にあるか、`index.html` からのアセットの参照が相対パスになっているか、5MB を超える `.html` が無いかを確認してください。
- どのエンジンでも、表に無い種類のファイル（[受け取れる形](engines.md#formats)）が含まれているとき、合計が 100MB かファイル数が 2000 を超えるときはアップロードできません。
- HTML にパスワードの入力欄（`<input type="password">`）か、外のサイトへ自動で移る `<meta http-equiv="refresh">` があると、ビルドごと受け付けません。
- アップロードできたのに起動しない場合は、Unity の **Enable Multithreading** と Godot の **Thread Support** が切れているかを確認してください。
- 起動はするのに画像・音声・文字や通信を使う機能が出ない場合は、外部の先から読み込んでいないかを確認してください（[ゲームから通信できる先](engines.md#network)）。ブラウザの開発者ツールのコンソールに、止めた読み込みが `Content Security Policy` の違反として出ます。
- それでも解決しない場合は、使用した開発環境とバージョンを添えてお問い合わせください: info@gamerush.jp
