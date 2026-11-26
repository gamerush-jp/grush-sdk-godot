# ロード時間と処理負荷

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/developers/optimization#checklist ・ https://gamerush.jp/developers/optimization#platform ・ https://gamerush.jp/developers/optimization#load-time ・ https://gamerush.jp/developers/optimization#performance ・ https://gamerush.jp/developers/optimization#unity ・ https://gamerush.jp/developers/optimization#godot ・ https://gamerush.jp/developers/optimization#web

ロード時間を縮め、スマホで軽く動かすための設定とコツをまとめたページです。Unity と Godot のおすすめのビルド設定と、エンジンを問わず守ってほしい一時停止・セーブ・タッチ操作の約束も載せています。

<a id="checklist"></a>
## まず見るところ

GameRush のプレイヤーは、フィードを流しながらスマホでゲームを次々に開きます。読み込みが長いゲームは遊ばれる前に飛ばされ、重いゲームは端末が熱くなったりページごと落ちたりします。次の項目から順に見てください。

- Unity は **Compression Format を Brotli**、**Decompression Fallback を切る**
- Unity は **Managed Stripping Level を Medium 以上**、**Strip Engine Code を有効**、**IL2CPP Code Generation を Faster (smaller) builds**
- Unity は **Enable Multithreading を切る**。Godot は 4.3 以降で **Thread Support を切る**（スレッドありのビルドは GameRush で起動しない）
- 合計のビルドサイズは **15MB 以下** を目安にする。**30MB 以上は危険**（上限は 100MB）
- テクスチャと音声を圧縮し、使っていないアセットとパッケージを消す
- 最初のシーンは小さく作り、残りは後から読み込む
- ファイル数を少なくし、1ファイルは **25MB 未満** にする（[先読みに載せる](optimization.md#load-time-prefetch)）
- ゲームが止められたとき（`visibilityState` が hidden になったとき）にセーブする（[一時停止とセーブ](pause-and-touch.md#pause)）
- スマホでは描画解像度とエフェクトを絞る

Unity と Godot の設定は SDK からまとめて適用してビルドできます（[推奨設定でビルドする](build-settings.md#build)）。

<a id="platform"></a>
## GameRush が自動でやること

配信側で縮められる部分は GameRush が受け持ちます。作者が設定する必要はありません。

- **圧縮して配信する。** Studio の画面から上げたビルドは、圧縮せずに上げたファイルも、起動に要るもの（`wasm` / `data` / `js` など）をこちらで圧縮して配信します。Unity Editor や API から上げたファイルは上げた形のまま配信するので、Brotli で書き出してください。Unity `v1.14.0` 以降の Editor から上げた `.unityweb` のビルドだけは、確定のときに Brotli へ圧縮し直します。
- **次に流れるゲームを先に読んでおく。** エンジンを問わず、いま遊んでいるゲームの裏で、次のゲームのファイルを端末に取っておきます。間に合えば、開いたときにはダウンロードがほぼ終わっています。先読みされない条件は [先読みに載せる](optimization.md#load-time-prefetch) にあります。
- **Unity の起動を急がせる。** Studio の画面と Unity `v1.14.0` 以降の Unity Editor の GameRush メニューから上げた Unity のビルドは、GameRush のプレイヤーで起動します。プレイヤーは `wasm` と `data` のダウンロードを最優先で並行して始め、ローディングバーを出し、ビルドに同梱された Service Worker を止めます。
- **エッジにキャッシュする。** ビルドは書き換わらない URL で配信され、各地のエッジに置かれます。

**ビルドそのものの重さ（`wasm` と `data` の大きさ、圧縮の設定、起動時にやる処理）は、配信側では削れません。ここから先は作者側の設定で決まります。**

<a id="load-time"></a>
## ロード時間を縮める

先読みが間に合っているとき、ロード時間はほぼ「`wasm` のコンパイル + 起動処理」の時間です。どちらも端末の CPU で決まり、ビルドが大きいほど長くなります。つまり体感を決めるのは主にビルドの大きさです。

| 合計のビルドサイズ | 体感 |
|---|---|
| 〜15MB | 目安。快適に遊べる |
| 15〜30MB | 先読みが間に合わなかったとき、モバイル回線で待ちが目立ち始める |
| 30MB 以上 | 危険。飛ばされやすく、スマホでは読み込み中にページが落ちることもある |
| 100MB | アップロードの上限（超えると受け付けない） |

<a id="load-time-data"></a>
### データを小さくする

- **テクスチャ**: 表示サイズより大きい画像を持ち込まない（スマホなら 1024px〜2048px が上限の目安）。圧縮フォーマットを使い、非圧縮のテクスチャを残さない。
- **音声**: BGM は長いので圧縮率を上げる（Unity は Vorbis の Quality を下げる、Godot は Ogg Vorbis を使う）。短い効果音は小さく保つ。
- **使っていないもの**: 試しに入れたパッケージやアセットは書き出し前に消す。Unity は Build Report や Editor.log の Build Report 節で、何が大きいかを確かめられる。
- **最初のシーン**: 最初のシーンが参照するアセットは、起動時に必ず読まれるデータ（Unity の `.data`、Godot の `.pck`）に入る。タイトル画面だけで起動し、残りは Addressables や後からの読み込みに回すと、起動が軽くなる。

<a id="load-time-prefetch"></a>
### 先読みに載せる

先読みが間に合えば、ダウンロードの待ちはほぼ消えます。次の条件に当たると先読みされず、遊び始めてからネットワークで読み込みます。

- ファイルの一覧（ファイルごとのパスと大きさ）が 4096 バイトを超える作品は、先読みしません。一覧は1ファイルあたり 50〜60 バイトほどなので、目安は 70〜80 ファイルまでです。パスが長いほど少なくなります。
- iPhone と iPad では、25MB を超えるファイルは先読みしません。
- iPhone・iPad と、回線が遅いときやデータセーバーがオンのときは、先読みするのは次の1件だけです。

**ファイル数を少なくし、1ファイルは 25MB 未満にしてください。画像はスプライトシートにまとめると数が減ります。**

<a id="load-time-ready"></a>
### ロード画面を早く外す

GameRush は、ゲームが最初の1枚を描いた時点でロード画面を外します。数えるのは WebGL の描画と、DOM に載っていて大きさのある 2D の canvas への描画です。canvas を使わず DOM だけで描くゲームや、画面に載せていない canvas にだけ描くゲームはこれを検出できないので、起動し終えたら次の1行を呼んでください。

```javascript
parent.postMessage({ type: "grush:ready" }, "*");
```

描画を検出できず合図も来ないと、ロード画面はページの `load` の5秒後か、読み込みを始めてから15秒のどちらか早いほうまで外れません。Studio の画面から上げて Unity と判別されたビルドは、GameRush のプレイヤーがこの合図を自動で送ります。

<a id="performance"></a>
## 処理負荷を下げる

スマホのブラウザは、同じ端末のネイティブアプリより使える CPU・GPU・メモリがずっと少なく、フィードの画面と同じタブの中で動きます。重いゲームはフレームが落ちるだけでなく、端末が熱くなって性能がさらに下がったり、メモリが足りずにページごと再読み込みされたりします。

<a id="performance-frame"></a>
### フレームレートと解像度

- Unity の WebGL は `Application.targetFrameRate` が既定の `-1` のとき、ブラウザの描画タイミング（requestAnimationFrame）に合わせて動く。ふつうはこのままにして、重い端末でだけ 30 に下げる。
- Godot は `Engine.max_fps` で上限を決められる。既定の 0 は上限なしで、ブラウザの描画タイミングに合わせて動く。熱や電池が気になるスマホでだけ 30 にする。
- 高解像度の画面で等倍に描くと、ピクセル数は 3〜4 倍になる。GPU が重いゲームは描画解像度を下げるのがいちばん効く。
- フルスクリーンのポストエフェクト（ブルーム・被写界深度・SSAO など）と、リアルタイムの影は、スマホでは真っ先に削る候補。

```csharp
void Awake()
{
    if (Application.isMobilePlatform)
    {
        Application.targetFrameRate = 30;
    }
}
```

```gdscript
func _ready() -> void:
    if OS.has_feature("web_android") or OS.has_feature("web_ios"):
        Engine.max_fps = 30
```

<a id="performance-cpu"></a>
### CPU とメモリ

- **毎フレームの割り当てを減らす。** Unity の WebGL はガベージコレクションがフレームの合間にまとめて走るので、`Update` で `new` や文字列の連結を繰り返すと、定期的にカクつく。弾や敵はオブジェクトプールで使い回す。
- **スレッドに頼らない。** GameRush ではマルチスレッドの書き出しが動かないので、重い計算は複数フレームに分けるか、事前に済ませておく。
- **メモリを使い切らない。** iPhone の Safari は1つのタブが使えるメモリに上限があり、超えるとページごと再読み込みされる。大きなテクスチャや音声を一度に全部読み込まず、使い終わったシーンのアセットは解放する。
- **物理とパーティクルの数を絞る。** 同時に動かすオブジェクトの数が、そのまま CPU の負荷になる。

<a id="performance-save"></a>
### 落ちる前に保存する

メモリが上限を超えると、ページは知らせなしに終了し、`visibilitychange` も `pagehide` も届きません。GameRush は、前面で遊んでいる間の 60 秒ごとと、メモリの見積もりの段階が上がったときに、ゲームへ保存の合図を送ります。合図を受けたら、進行をクラウドセーブか端末に保存してください。

- `window.GRushAutoSave.onRequest(handler)` で合図を受ける。`handler` は `{ reason }` を受け取り、`reason` は `"interval"`（60 秒ごと）か `"memory"`（メモリの段階が上がった）。戻り値を呼ぶと受け取りをやめる。`window` の `grush:save-request` イベントでも同じ合図を受けられる。
- `window.GRushMemory.estimate()` は、WebGL のテクスチャ・バッファ・レンダーバッファと canvas の描画領域から見積もったバイト数（`bytes`）と、段階（`level`。`"normal"`・`"high"`・`"critical"`）を返す。目安で、実際の使用量から上にも下にもずれる。画像のデコード領域と JS・wasm のヒープは数えない。
- `window.GRushMemory.onLevelChange(handler)` で段階の変化を受ける。`"critical"` になったら、使っていないテクスチャや canvas を捨ててメモリを減らす。
- Unity と Godot の SDK には、これらを呼ぶ関数が無い。jslib や JavaScriptBridge から `window` の API を呼ぶ。

```javascript
// GameRush の中だけにある。外で動かしたときに落ちないよう、有無を確かめてから使う。
if (window.GRushAutoSave) {
  window.GRushAutoSave.onRequest(({ reason }) => {
    saveProgress(); // reason は "interval" か "memory"
  });
}
if (window.GRushMemory) {
  window.GRushMemory.onLevelChange(({ level, bytes }) => {
    if (level === "critical") releaseUnusedTextures();
  });
}
```

<a id="performance-measure"></a>
### 測る

Studio のアナリティクスには、実際のプレイヤーの端末で測ったロード時間（平均・95%の読み込みが収まる時間・途中離脱率）とフレームレート、ゲームが使うメモリの見積もり（`GRushMemory.estimate()` と同じ見積もりの、プレイごとの最大値。記録するのは、止めていない・初回描画の後・表示中の間の確認の値だけ）が出ます。API からも取れます（[アナリティクス](http-api-leaderboards-analytics.md#analytics)）。設定を変えたら、次のビルドで数字がどう動いたかを見てください。

手元で確かめるときは、パソコンのブラウザではなく実際のスマホで、できれば数年前の機種で開いてください。パソコンで快適なゲームがスマホで重いのはよくあることです。

<a id="unity"></a>
## Unity のおすすめ設定

**Player Settings > WebGL** で設定します。SDK の **GameRush > 推奨設定でビルド** を使うと、下の表をまとめて適用してビルドできます（[推奨設定でビルドする](build-settings.md#build)）。

| 設定 | おすすめ | 理由 |
|---|---|---|
| Publishing Settings > Compression Format | Brotli | いちばん小さくなる。GameRush は正しいヘッダーを付けて配信する |
| Publishing Settings > Decompression Fallback | オフ | オンにすると、ダウンロードとコンパイルが並行しなくなる |
| Publishing Settings > Data Caching | オフ | GameRush が自分で先読みとキャッシュをするので二重になる |
| Other Settings > Managed Stripping Level | Medium（High でも可） | 使っていないコードを削って wasm を小さくする |
| Other Settings > Strip Engine Code | オン | 使っていないエンジンの機能を削る |
| Other Settings > IL2CPP Code Generation | Faster (smaller) builds | 実行速度よりサイズを優先する |
| Other Settings > C++ Compiler Configuration | Release | デバッグ用の情報を載せない |
| Build Settings > Code Optimization（2022 以降） | Disk Size（Unity 6 は Disk Size with LTO） | wasm が小さくなる |
| Publishing Settings > Enable Exceptions | Explicitly Thrown Exceptions Only | 例外の検査を減らして小さく速くする。None にするとエラーの原因が追えなくなる |
| Other Settings > Graphics APIs | WebGL 2 だけ | WebGL 1 向けの分を持たない |
| Publishing Settings > Enable Multithreading | オフ | GameRush の配信ではスレッドが動かず、オンのビルドは起動しない |
| Build Settings > Development Build | オフ | 開発用ビルドは大きく遅い |

Managed Stripping Level を High にすると、リフレクションで呼んでいるコードまで削られて動かなくなることがあります。そのときは Medium に戻すか、`link.xml` で残す型を指定してください。

レンダーパイプラインは Built-in か URP を使ってください。HDRP は WebGL に対応していません。

<a id="godot"></a>
## Godot のおすすめ設定

Godot 4.3 以降の **Project > Export** の Web プリセットで設定します。SDK の **GameRush SDK Build** プラグインを使うと、下の設定の「GameRush Web」プリセットを作って書き出せます（[推奨設定でビルドする](build-settings.md#build)）。

| 設定 | おすすめ | 理由 |
|---|---|---|
| Variant > Thread Support | オフ | GameRush の配信ではスレッドが動かず、オンのビルドは起動しない |
| Variant > Extensions Support | オフ | GDExtension を使わないなら要らない |
| VRAM Texture Compression > For Mobile | オン | スマホの GPU が読める形式（ETC2 / ASTC）のテクスチャを入れる |
| VRAM Texture Compression > For Desktop | オン | パソコンのブラウザで遊ぶ人向け |
| Progressive Web App > Enabled | オフ | Studio は PWA の部品を捨て、GameRush のプレイヤーは Service Worker を登録しないので使われない |
| Export Path | 任意の名前 | Studio は書き出した名前のまま受け取る。`ServiceWorker` と `__` で始まる名前は使えない |

- レンダラーは **Compatibility** を使ってください。Web への書き出しで動くのは Compatibility だけです。
- For Mobile をオンにするには、Project Settings の **Rendering > Textures > VRAM Compression > Import ETC2 ASTC** もオンにします。テクスチャの取り込み直しが走り、`.pck` は大きくなります。2D で Lossless のテクスチャしか使っていないなら影響はほとんどありません。
- `.pck` は起動時に丸ごと読まれます。使わないリソースは Export の Resources タブで除外してください。
- Godot 4.5.1 で音を鳴らし続けると、iOS の Safari でページが落ちるという報告があります。公開前に iPhone の実機で通して遊んでください。

<a id="web"></a>
## Phaser と Web（その他のツール）

- アセットの参照は相対パスにする（Vite なら `base: "./"`）。
- 本番用にビルドして minify する。ソースマップは上げない。
- 画像はスプライトシートにまとめ、`webp` を使う。音声は `ogg` / `m4a` にする。
- 起動に要らないアセットは、タイトル画面を出してから読み込む。
- GameRush のローディングバーは出ないので、読み込み中の表示はゲームの側で用意する。

書き出しの手順とアップロードで弾かれる条件は [対応エンジンと書き出しガイド](engines.md#web) にあります。
