# GameRush 向けのゲームを作るときの決まり

> AI エージェント向けの文書です。GameRush の Godot 4 SDK（{{GRUSH_SDK_VERSION}}）に同梱された写しで、中身は GameRush の開発者向け文書（https://gamerush.jp/developers）と同じです。手で直さないでください。入れ直すには、Godot のメニューの `Project > Tools > GameRush: AI エージェント向けの文書を入れる` を実行する。

GameRush（https://gamerush.jp）は、ブラウザで動くゲームを縦のフィードで次々に遊ぶサービスです。ゲームは作者が上げたビルドから配信します。

## 必ず守ること

1. ビルドの合計は 50MB まで、ファイル数は 2000 までです。HTML は1ファイル 5MB までです。
2. 上げられるファイルの拡張子は次だけです（後ろに `.br` / `.gz` が付いた名前は、その前の拡張子で決まります）: `.html` `.js` `.wasm` `.data` `.json` `.png` `.jpg` `.jpeg` `.gif` `.bmp` `.css` `.unityweb` `.pck` `.ico` `.svg` `.webp` `.mp3` `.m4a` `.aac` `.ogg` `.wav` `.mp4` `.txt` `.csv` `.xml` `.yml` `.yaml` `.ttf` `.woff` `.woff2` `.webmanifest` `.bytes` `.bundle` `.assetbundle` `.bin` `.dat` `.bank` `.ress` `.resource` `.fnt` `.atlas` `.skel` `.glsl` `.frag` `.vert` `.tmx` `.tsx` `.tmj` `.tsj` `.otf` `.webm` `.ktx` `.pvr` `.ktx2` `.basis` `.glb` `.ldtk`。Studio の画面で上げて Unity と判別されたビルドでは、表に無いファイルを黙って除きます（`StreamingAssets` の下を除く）。
3. HTML は圧縮せずに入れます。圧縮した HTML（`.html.gz` / `.html.br`）は、Studio の画面と JavaScript SDK の `grush upload` では黙って除かれ、HTTP API ではビルドごと受け付けません。
4. Studio の画面で上げたビルドは中身からエンジンを判別し、Unity・Godot・GDevelop と判別されたものは、書き出した HTML の代わりに GameRush 側のプレイヤーで起動します。Phaser と Web（その他のツール）は最上位の `index.html` をそのまま使います。HTTP API と JavaScript SDK の `grush upload` で上げたビルドは判別を通らず、送ったファイルをそのまま使い、最上位の `index.html` が入口です（[engines.md](docs/engines.md#formats)）。
5. HTML にパスワードの入力欄（`<input type="password">`）や、外のサイトへ自動で移る `<meta http-equiv="refresh">` があると、ビルドごと受け付けません。
6. ランキングの枠は作者が宣言し、ゲームからは作れません。宣言はビルドの最上位の `grush.json`・Studio の画面・HTTP API のどれでもできます。宣言していない key への投稿は `invalidParams` です（[leaderboards.md](docs/leaderboards.md)）。
7. ゲームは GameRush 本体と別のオリジン（`{ゲームの ID}.g-rush.org`）の、sandbox 付きの iframe の中で動きます。ページ全体の移動（`window.top` の書き換え）はできず、`alert` / `confirm` / `prompt` は出ません。
8. ゲームが通信できるのは、ゲーム自身のオリジンと、[engines.md](docs/engines.md#network) の表の先だけです。自分のサーバー・外部のサービス・CDN とは `fetch` / `XMLHttpRequest` / WebSocket のどれでも通信できず、外部のスクリプト・画像・音声・フォントも読めません。要るファイルはビルドに含め、セーブ・ランキング・マルチプレイは SDK の機能を使います。
9. アプリ版の GameRush でも、ゲームに端末のネイティブ API は渡りません。Web 標準の API と SDK の機能だけを使います。
10. SDK の呼び出しは例外を投げず、結果の `ok` と `code` を返します（アナリティクスだけは真偽値）。必ず `ok` を確かめてから `value` を使います。GameRush の外で動かすと `unsupported` が返ります（[sdk-basics.md](docs/sdk-basics.md)）。
11. SDK の呼び出しには回数の上限があります。毎フレーム呼ばず、結果を手元に持って使い回します。
12. 次のゲームへ送られると、ゲームは止まって `visibilitychange`（`hidden`）が届き、まもなく閉じられます。セーブはこのときに送ります（[pause-and-touch.md](docs/pause-and-touch.md)）。

## Godot 4 で気をつけること

- Godot 4.3 以降で Web に書き出す。**Thread Support** はオフ（スレッドありのビルドは GameRush で起動しない）。`.pck` / `.wasm` / `.js` は大文字と小文字まで同じ名前にする。
- Studio の画面から上げたビルドは Godot と判別され、書き出した `.html` を使わずに GameRush 側のプレイヤーで起動する。そのため **Custom HTML Shell** と **Head Include** は使えない。HTTP API で上げたビルドは判別を通らず、送ったファイルをそのまま使う（[engines.md](docs/engines.md#formats)）。
- 別アドオン `addons/grush_sdk_build/` を有効にすると、推奨設定で書き出せる（[build-settings.md](docs/build-settings.md)）。
- API は autoload の `GRush` から呼び、`await` した Dictionary の `ok` / `value` / `code` を見る。

## 文書の地図

| ファイル | 読むとき |
|---|---|
| [sdk-basics.md](docs/sdk-basics.md) | SDK を初めて呼ぶとき。結果の `ok` と `code`・エラーコード・呼び出しの回数の上限・一時停止 |
| [setup-unity.md](docs/setup-unity.md) | Unity の SDK を入れるとき・C# の型を調べるとき |
| [setup-godot.md](docs/setup-godot.md) | Godot の SDK を入れるとき・GDScript の戻り値の形を調べるとき |
| [setup-javascript.md](docs/setup-javascript.md) | 素の `index.html` のゲームに SDK を入れるとき・クラウドセーブを使うとき |
| [engines.md](docs/engines.md) | ビルドを書き出す・zip にするとき。受け取れるファイル・上限・通信できる先・弾かれたときの確認 |
| [optimization.md](docs/optimization.md) | ロードが遅い・重い・スマホで落ちるとき。エンジンごとのおすすめのビルド設定 |
| [pause-and-touch.md](docs/pause-and-touch.md) | フィードで止められたときの振る舞い・セーブの時機・タッチ操作・スクショの撮られ方を決めるとき |
| [leaderboards.md](docs/leaderboards.md) | スコアを送る・ランキングを出すとき。`grush.json` での宣言 |
| [player-state.md](docs/player-state.md) | ほかのプレイヤーに見せる状態（クラウドに置く公開のセーブ）・相手探し・通報を使うとき |
| [multiplayer.md](docs/multiplayer.md) | 部屋に入って対戦・協力するとき・フレンドを部屋へ招くとき |
| [inbox.md](docs/inbox.md) | プレイヤーどうしでメッセージや贈り物を送るとき |
| [trade.md](docs/trade.md) | プレイヤーどうしでアイテムを交換するとき |
| [analytics.md](docs/analytics.md) | ゲームの中の進み具合や離脱をイベントで送るとき |
| [share.md](docs/share.md) | スクショや画像を添えて共有するとき・共有リンクに起動パラメータを載せるとき |
| [locale.md](docs/locale.md) | ゲームの文言をプレイヤーの言語に合わせるとき |
| [launch-params.md](docs/launch-params.md) | 共有リンクや招待から開かれたときに渡る値を読むとき |
| [creator.md](docs/creator.md) | 遊んでいるのがゲームの作者本人かで振る舞いを変えるとき |
| [shop.md](docs/shop.md) | ゲーム内アイテムを売る・購入を受け取るとき |
| [testing.md](docs/testing.md) | GameRush の外（エディタ・手元のサーバ）で SDK の呼び出しを試すとき。モックの振る舞い |
| [build-settings.md](docs/build-settings.md) | Unity・Godot の SDK のメニューやコマンドラインで、推奨設定のビルドを作るとき |
| [editor-upload.md](docs/editor-upload.md) | Unity のメニューからログインしてビルドを上げるとき |
| [api-tokens.md](docs/api-tokens.md) | CI や自分のツールから HTTP API を呼ぶためのトークンを発行・取得するとき |
| [http-api.md](docs/http-api.md) | 作者の手元や CI から HTTP API を呼ぶとき。認証・エラーの形 |
| [http-api-games.md](docs/http-api-games.md) | ゲームの作成・設定変更・多言語の訳・公開設定・サムネイルを API で行うとき |
| [http-api-builds.md](docs/http-api-builds.md) | ビルドを API で上げるとき（ファイルの一覧・送信・完了） |
| [http-api-leaderboards-analytics.md](docs/http-api-leaderboards-analytics.md) | ランキングの定義を API で宣言するとき・アナリティクスの数字を API で読むとき |
| [http-api-shop.md](docs/http-api-shop.md) | 販売するアイテムの商品を API で登録・変更するとき |

載せられるゲームと審査の考え方は、ゲーム掲載ポリシー（https://gamerush.jp/import-policy）にあります。
