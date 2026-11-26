# ゲームからの共有

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#share

<a id="share"></a>
## ゲームからの共有

ゲームから「いまの画面や結果を共有して」と頼めます。呼んだ時点では共有は開かず、GameRush の確認シートが出て、プレイヤーが送り先を押したときに開きます。シートを出している間、ゲームは一時停止します。

**ゲームに返るのは「開いた（`opened`）」か「やめた（`cancelled`）」だけです。どこへ送ったか、実際に投稿されたかは GameRush にも分からないので返りません。**

共有には GameRush がそのゲームのページの URL を付けます。ゲームから URL は指定できません。ゲームが指定できるのは、URL に添える起動パラメータだけです（下の「起動パラメータを添える」）。

```csharp
// Unity
if (await GRush.Share.IsAvailableAsync())
{
    var shared = await GRush.Share.ShareScreenAsync("ステージ3をクリア");
    if (shared.Ok && shared.Value == GRushShareStatus.Opened) ShowThanks();
}
```

```gdscript
# Godot
if await GRush.share.is_available():
    var shared: Dictionary = await GRush.share.share_screen("ステージ3をクリア")
    if shared["ok"] and shared["value"]["status"] == "opened":
        show_thanks()
```

```javascript
// JavaScript
if (await GRush.share.isAvailable()) {
  const shared = await GRush.share.share({ text: "ステージ3をクリア", image: "screen" });
  if (shared.ok && shared.value.status === "opened") showThanks();
}
```

| 呼び出し | Unity | Godot | JavaScript |
|---|---|---|---|
| 本文と画像 | `Share.ShareAsync(text, bytes)` | `share.share(text, image)` | `share.share({ text, image })` |
| 本文と画面のスクショ | `Share.ShareScreenAsync(text)` | `share.share_screen(text)` | `share.share({ text, image: "screen" })` |
| いま共有できるか | `Share.IsAvailableAsync()` | `share.is_available()` | `share.isAvailable()` |

共有できるかは失敗せず、`true` か `false` で返ります。共有ボタンを出す前に確かめてください。GameRush の外、古い GameRush、埋め込み表示では `false` です。

### 起動パラメータを添える

共有に起動パラメータを添えると、GameRush が付ける URL に `?gp.dungeon=3` のように載ります。受け取った人がその URL からゲームを開くと、ゲームは [起動パラメータ](launch-params.md#launch) の呼び出しで値を読めます。

```csharp
// Unity
var launchParams = new Dictionary<string, string> { { "dungeon", "3" } };
var shared = await GRush.Share.ShareScreenAsync("ダンジョン3に挑戦", launchParams);
if (!shared.Ok && shared.Code == GRushErrorCode.Unsupported)
{
    shared = await GRush.Share.ShareScreenAsync("ダンジョン3に挑戦");
}
```

```gdscript
# Godot
var shared: Dictionary = await GRush.share.share_screen("ダンジョン3に挑戦", {"dungeon": "3"})
if not shared["ok"] and shared["code"] == "unsupported":
    shared = await GRush.share.share_screen("ダンジョン3に挑戦")
```

```javascript
// JavaScript
let shared = await GRush.share.share({
  text: "ダンジョン3に挑戦",
  image: "screen",
  launchParams: { dungeon: "3" },
});
if (!shared.ok && shared.code === "unsupported") {
  shared = await GRush.share.share({ text: "ダンジョン3に挑戦", image: "screen" });
}
```

| 呼び出し | Unity | Godot | JavaScript |
|---|---|---|---|
| 本文と画像 | `Share.ShareAsync(text, bytes, launchParams)` | `share.share(text, image, launch_params)` | `share.share({ text, image, launchParams })` |
| 本文と画面のスクショ | `Share.ShareScreenAsync(text, launchParams)` | `share.share_screen(text, launch_params)` | `share.share({ text, image: "screen", launchParams })` |

- キーと値の制限は [起動パラメータ](launch-params.md#launch) と同じです。キーは英数字と `_` `-` で 1〜32 文字（`__proto__` は使えません）、値は英数字と `.` `_` `~` `:` `,` `-` で 0〜128 文字、8 個までです。
- URL から読むときと違い、1つでも合わない項目があると共有を開かずに `InvalidParams` を返します。合わない項目だけを落として共有することはしません。
- 空の起動パラメータは、渡さないときと同じです。
- 起動パラメータに対応する前の古い GameRush（`protocolVersion` 9 未満）では、共有を開かずに `Unsupported` を返します。起動パラメータを外して呼び直せば共有できます。

**共有した URL は誰にでも見え、そのまま転送されます。招待コードのような、プレイヤーを識別できる値を入れないでください。**

受け取る側のゲームは値を信用せず、確かめてから使ってください。共有した URL の起動パラメータは、受け取った人が書き換えられます。

### 画像の形

- Unity は画像ファイルのバイト列（`Texture2D.EncodeToPNG()` など）を渡します。
- Godot は `Image` を渡します。SDK が PNG にしてから渡します。
- JavaScript は `Blob`・`ArrayBuffer`・型付き配列・data URL・`HTMLCanvasElement`・`{ base64, mimeType }` を渡せます。
- どれも `"screen"`（Unity は `ShareScreenAsync`、Godot は `share_screen`）でゲームの画面のスクショを送れます。
- 受け付ける形式は PNG・JPEG・GIF・WebP です。SVG などほかの形式は `InvalidParams` になります。
- 4MB まで、縦横それぞれ 4096px まで、総画素数 16MP までです。GameRush が長辺 1600px の JPEG に作り直してから送ります（GIF は 1 コマ目、透過は黒）。

**何も指定しなければ、`"screen"` に写るのはゲームの canvas だけです。DOM で描いた文字や画像は `"screen"` に写りません。**

HTML の要素でスコアや名前を重ねているなら、[HTML の要素ごと撮る](pause-and-touch.md#screenshot-dom) の `dom` を使うか、canvas に描いた画像を自分で作って渡してください。`dom` を使わないゲームでは、最初に描画するより前の `"screen"` は `Unavailable` です。

`"screen"` は、Web でコメントに添付するスクショと同じ画像です（GameRush のアプリは、コメントのスクショだけを画面そのものから作ります）。canvas が複数あるときにどれが撮られるかと、`data-grush-capture` 属性で撮り方を指定する方法は、[スクショの撮られ方](pause-and-touch.md#screenshot) にあります。

画像が実際に送り先へ付くかは、プレイヤーの端末と送り先で決まります。

- 画像ファイルを付けられるスマホの端末共有と Android アプリでは、画像ファイルを付けます。
- LINE の送信先選択、画像ファイルを付けられないスマホの端末共有、PC の端末共有、コピー、X でポストでは、画像と本文を GameRush のサーバに置いてからゲームのページの URL を送ります。LINE には画像と「遊ぶ」ボタンの付いたメッセージで届き、コピーした URL と X に送った URL は、貼り付けた先や投稿のリンクのカードに画像が出ます。どれも押すとそのままゲームが始まります。画像を置けなかったときは本文と URL だけになります。
- 端末の共有シートが無いブラウザ（PC の Firefox や Linux など）では、本文と URL をクリップボードへコピーします。ブラウザでは、画像を添えて投稿したいプレイヤーがシートで画像を保存して、貼り付け先で添付できます。
- X から GameRush に来たプレイヤーには、X の投稿画面を開く「X でポスト」を最初に出し、端末の共有かコピーを 2 つ目に並べます。

置いた画像と本文は 90 日間、URL を知っている人なら誰でも見られます。ゲームが渡した本文がそのまま載るので、プレイヤーに見られて困る文字を入れないでください。載せる画像は長辺 1024px・1MB までの JPEG に作り直されます。

### 本文

| 本文の条件 | 結果 |
|---|---|
| 100 文字を超える | `InvalidParams` |
| URL を含む（`https://`・`www.`・`example.com` のような「英数字.英字2文字以上」） | `InvalidParams` |
| @メンションを含む（全角の `＠` も同じ） | `InvalidParams` |
| 制御文字・ゼロ幅スペースなどの見えない文字 | 取り除いて送る |
| 空行 | 取り除いて送る。改行は 2 つまでで、3 行目以降は空白でつなぐ |

**URL は形で判定するので、`Lv.MAX` のような英字どうしのドット表記も弾かれます（`v1.5` のように数字を挟むものは通ります）。ハッシュタグは使えます。**

### エラーコード

| 返るコード | いつ |
|---|---|
| `Unsupported` | GameRush の外で動かしたとき。共有に対応していない古い GameRush（`protocolVersion` 3 未満）。起動パラメータを添えた共有に対応していない古い GameRush（`protocolVersion` 9 未満） |
| `InvalidParams` | 本文か画像か起動パラメータが上の条件に合わない |
| `Unavailable` | いま共有できない（プレイヤーがフィードをめくるモードにいる・タブが裏にある・埋め込み表示・GameRush が共有を止めている・1 回の滞在で同じゲームから 5 回を超えた）。最初の描画より前の画面のスクショ |
| `RateLimited` | シートを出している間の 2 回目、5 秒以内の続けての呼び出し |

結果が返るまで、プレイヤーがシートで迷うあいだ待ちます。14 分でシートは閉じて `cancelled` が返ります。コピーになる環境では、コピーできた時点で `opened` が返ります。`opened` を報酬の条件にするなら、同じ報酬を何度も渡さないようゲーム側で数えてください。
