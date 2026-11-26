# 一時停止・セーブ・タッチ操作・スクショ

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/developers/optimization#pause ・ https://gamerush.jp/developers/optimization#touch

<a id="pause"></a>
## 一時停止とセーブ

エンジンを問わず、どのゲームにも当てはまる約束です。

- プレイヤーが閲覧モードへ切り替えたときや、次のゲームへ送り始めたとき、GameRush はゲームを止めます。`requestAnimationFrame` とタイマー、音の再生を止め、再開すると続きから動かします。閲覧モードでも止めずに動かしてほしいゲームは、下の「閲覧中のプレビュー」に対応してください。
- 止めるとき、ゲームからは `visibilityState` が hidden に見え、`visibilitychange` が届きます。**セーブは hidden になったときに行ってください。**
- 画面から離れたゲームは、ページごと捨てます。戻ってきたときは最初から起動し直すので、続きから遊ばせたいゲームは hidden の時点でセーブしておいてください。
- メモリが足りずにページが終了したときは hidden が届きません。遊んでいる途中にも届く保存の合図は、[落ちる前に保存する](optimization.md#performance-save) を見てください。

<a id="pause-preview"></a>
### 閲覧中のプレビュー

HTML の `<head>` に `<meta name="grush-preview" content="on">` を置いたゲームは、閲覧モードの間も、止めずに音を消して動かすことがあります。閲覧モードのカードに、サムネの代わりに動いているゲームが映ります。プレイヤーはカードを操作できないので、操作しなくても自動で動くタイトルやデモを見せてください。

```html
<meta name="grush-preview" content="on">
<script>
  function applyPreview(active) {
    if (active) startDemo(); // 操作しなくても動くデモ。セーブしない
    else startGame(); // 本編
  }
  if (window.GRushPreview) {
    window.GRushPreview.onChange(applyPreview);
    applyPreview(window.GRushPreview.active);
  } else {
    startGame();
  }
</script>
```

- `window.GRushPreview.active` が `true` の間がプレビューです。変わるたびに `window.GRushPreview.onChange(handler)` の `handler` が `active` を受け取り、`window` に `grush:preview` イベント（`detail` は `{ active }`）が届きます。`onChange` の戻り値を呼ぶと受け取りをやめます。
- プレビューの間は、ゲームからは `visibilityState` が visible に見え、`requestAnimationFrame` とタイマーが進みます。音は、ゲームが鳴らしても出ません。
- **プレビューの間はセーブしないでください。** プレイヤーが遊んだ進行ではありません。
- プレビューはプレイに数えません。`GRushAnalytics` のイベントは記録されず（`false` が返ります）、スコアの送信・公開プレイヤー状態の通報・マルチプレイの入室は `unavailable` で断られ、受信箱と交換所の通報は確認を出さずに `reported: false` で返ります。コメントに添えるスクショにも、プレビューの画面は使われません。
- HTML の要素・CSS・SVG だけで描くゲームは、プレビューを始めてすぐにサムネが外れます。canvas に描くゲームは、最初に描いたときに外れます。
- プレイヤーがプレイを始めると `active` が `false` になります。そこで本編を始めてください。音はそのときから出ます。
- 閲覧モードの間でも、ほかのシートを開いたときやアプリが裏へ回ったときは、いつもどおり止めます。止めている間は `active` を変えません。
- `window.GRushPreview` が無いとき（GameRush の外で開いたときなど）と、`active` が `false` のときは、ふつうに遊べるようにしてください。

<a id="touch"></a>
## タッチ操作とスクショ

GameRush はエンジンを問わずどのゲームにも、スワイプで文字が選択されたり、画面が引っ張られて LINE のミニアプリが閉じかけたりしないための設定を自動で入れます。ゲームの側で次のことを守ると、確実に効きます。

- **スクロールさせたい部分は `overflow: auto` の要素にする。** スワイプで画面ごと動くことはなくなりますが、`overflow: auto` や `scroll` の要素の中だけは、その向きに指で普通にスクロールできます。入力欄の上も止めません。
- **`touchmove` を `stopPropagation` しない。** 止めると、GameRush の側で画面の引っ張りを止められなくなります。既定動作を止めたいときは `preventDefault` を使ってください。
- **文字を選ばせたいところだけ `user-select: text` と `-webkit-user-select: text` を書く。** GameRush の設定は要素の一つ一つに当たるので、選ばせたい要素とその子孫の両方（`.log, .log *` のように）に書いてください。詳細度は 0 なので、ゲームのスタイルが常に優先されます。入力欄はもとから選択できます。
- **スクショに映したいものは canvas に描く。** コメントに添付するスクショには、基準の canvas と、それに重なっている見えている canvas が映りますが、HTML の要素で出した文字や画像は映りません（映すには、下の「HTML の要素ごと撮る」の `dom` を使います。GameRush のアプリでコメントに添付するスクショには、何もしなくても映ります）。WebGL の canvas を重ねている場合は、基準の canvas と同じ処理の中で描いた canvas か、`preserveDrawingBuffer: true` で作った canvas だけが映ります。基準の canvas の選ばれ方と、見た目どおりに撮られないときの直し方は、下の「スクショの撮られ方」にあります。
- **別のオリジンの画像は、CORS を許可して読み込んでから canvas に描く。** 許可なしに描いた canvas はブラウザが読み出しを禁じるので、スクショに映りません。基準の canvas がそうなると、スクショを添付できなくなります。

<a id="screenshot"></a>
### スクショの撮られ方

コメントに添付するスクショと、[ゲームからの共有](share.md#share) の `"screen"` は、同じ画像です（GameRush のアプリのコメントのスクショは、下の「アプリでコメントに添付するスクショ」）。GameRush がプレイ中のゲームの canvas から、1 秒に 1〜4 回撮ります。撮るのは、`requestAnimationFrame` かタイマー（`setTimeout`・`setInterval`）のコールバックが済んだ直後と、WebGL の描画の直後です。2D の canvas だけのゲームが、どちらのコールバックも使わずに描くと、撮られません。ゲームを止めた後には撮らないので、コメントに添付されるのは止める直前の 1 枚です（`dom` を使うゲームは、下の「HTML の要素ごと撮る」のとおり、止めた後の画面です）。

- **映るのは canvas だけです。** HTML の要素で出した文字や画像は映りません。HTML の要素も映したいときは、下の `dom` を使ってください。GameRush のアプリでコメントに添付するスクショだけは、画面そのものから作ります（下の「アプリでコメントに添付するスクショ」）。
- **基準になるのは、見えている 2D か WebGL の canvas のうち、画面上でいちばん大きく映っているものです。** その半分以上の大きさで映っている canvas がほかにあれば、その中で画素数（`width` × `height`）がいちばん多いものを選びます。`display: none` の画面の中にある canvas、透明にした canvas、画面の外へ出した canvas は選びません。スクショに映る範囲と縦横比は、基準の canvas で決まります（幅 1080px、総画素数 120 万までに縮めます）。
- **基準に重なっている見えている canvas を、画面上の位置と大きさに合わせて重ねます。** 重ねる順は、canvas 自身の `z-index` の小さい順で、同じなら HTML に書いた順です。
- **重ねる順に、親の要素の重なり順は入りません。** canvas の手前にある HTML の要素は映らず、CSS の `mask`・`clip-path`・半透明の `opacity` も反映しません。画面では吹き出しの奥にある立ち絵が、スクショでは手前に出ることがあります。

**見た目どおりに撮られないときは、`data-grush-capture` 属性で撮り方を指定してください。値は小文字の `only`・`ignore`・`dom` です。`only` と `ignore` は canvas に、`dom` は canvas を包む要素に付けます。ゲームの途中で付け外しできます。**

| 値 | 撮り方 |
|---|---|
| `data-grush-capture="only"` | この canvas だけを撮ります。ほかの canvas を重ねません。`display: none` などで表示していなくても撮りますが、HTML の中に置いてください（`document.createElement` で作っただけの canvas は撮りません） |
| `data-grush-capture="ignore"` | この canvas を基準にも、重ねる canvas にもしません |
| `data-grush-capture="dom"` | `<body>` か、ゲームの画面を包む要素に付けます。コメントに添付するスクショと共有の `"screen"` を、その要素が画面に占める範囲の HTML ごと撮ります |

```html
<!-- 画面全体を自分で描いた canvas。表示しなくても、これだけがスクショになる -->
<canvas id="shot" width="720" height="1280" data-grush-capture="only" hidden></canvas>

<!-- 吹き出しの奥にある立ち絵。スクショには重ねない -->
<canvas id="portrait" width="256" height="384" data-grush-capture="ignore"></canvas>
```

- 画面全体を 1 枚の canvas に描いているなら、その canvas に `only` を付けると、その canvas の中身がそのままスクショになります。
- HTML の要素で画面を作っているゲームは、`<body>` に `dom` を付けてください（次の節）。スクショにしたい絵を自分で canvas に描けるなら、その canvas に `only` を付ける方法もあります。プレイ中に撮るので、その canvas はプレイ中に描き直し続ける必要があります。
- 立ち絵や演出の canvas が、スクショで手前に出て困るときは、その canvas に `ignore` を付けてください。
- `only` を付ける canvas は 1 枚にしてください。複数に付けると、画面上でいちばん大きく映っているものを撮り、どれも表示していなければ最初に `getContext` を呼んだものを撮ります。

<a id="screenshot-dom"></a>
### HTML の要素ごと撮る

`data-grush-capture="dom"` を付けた要素があると、コメントに添付するスクショと共有の `"screen"` は、canvas の合成ではなく、HTML の要素を含む画面から作ります。撮るのは、プレイヤーがコメントのシートを開いたときと、ゲームが共有を呼んだときの 1 回だけです。コメントでは、止めた後の画面が映ります。プレイ中に増える処理は、WebGL の canvas を別の canvas に重ねているゲームで、WebGL の canvas の写しを 1 秒に 1〜4 回取ることだけです。

```html
<!-- HTML の要素で作った画面を、見た目のまま撮る -->
<body data-grush-capture="dom">
  <div id="message">HTML で出した吹き出し</div>
  <canvas id="portrait" width="256" height="384"></canvas>
</body>
```

- **映る範囲は、属性を付けた要素が画面に占める矩形です。** `<html>` か `<body>` に付けると、画面の全体になります。付ける要素は 1 つにしてください。
- **CSS の重なり順・`mask`・`opacity`・`transform` は、画面のとおりに映ります。** CSS のアニメーションとトランジションは、撮った瞬間の見た目で止めて撮ります。入力欄には、入力されている値が映ります（パスワードの欄に入力した値は映りません）。
- **canvas は、撮った瞬間の中身が映ります。** WebGL の canvas は、GameRush が最後に撮ったときの絵（最大で 1 秒前）が映ります。`ignore` を付けた canvas は、中身を映しません。
- **画像・スタイルシート・フォントは、ビルドに含めたファイルと `blob:` の URL から読んだものだけが映ります。** Google Fonts のフォントで出した文字は、代わりのフォントで映ります。別のサイトから読んだ画像（プレイヤーのアバターなど）は、映らないことがあります。
- **映らないもの:** 要素の中のスクロール位置（先頭の位置で映ります。ページ全体のスクロールは映ります）、`:hover` と `:focus` の見た目、shadow DOM の中身、`<iframe>` の中身、`showModal()` で開いた `<dialog>` の位置と背景、popover、JavaScript の `FontFace` で足したフォント。
- **`<!DOCTYPE html>` で始まる文書にしてください。** 無い文書（互換モード）は、高さの決まり方が変わり、画面と違うレイアウトで映ることがあります。
- **作れなかったときは、canvas だけのスクショに戻ります。** 要素が 2 万個を超える画面や、2.5 秒で作り終わらない画面です。作り終わるまで（ふつうは 0.5 秒以内）は、コメントのシートに canvas だけの画像が出ます。
- コメントのシートで選べる直前の数秒のコマは、`dom` を付けても canvas だけの画像です。そのコマの撮り方は、`only` と `ignore` で指定できます。

<a id="screenshot-app"></a>
### アプリでコメントに添付するスクショ

GameRush の iOS・Android のアプリでは、コメントに添付するスクショを、ゲームを止める直前の画面そのものから作ります。HTML の要素で出した文字や画像も、属性を付けなくても、画面のとおりの重なり順で映ります。Web と LINE では、上の撮られ方で作ります。アプリでも、共有の `"screen"` と、コメントのシートで選べる直前の数秒のコマは、上の撮られ方で作ります。

- **canvas だけで描いているゲームは、Web と同じ画像になります。** canvas のほかに、文字・画像（`<img>`・`<svg>`・`<video>`）・操作部品（`<button>`・`<input>` など）が画面に出ているときに、画面から作ります。背景色や背景画像だけの要素と、疑似要素（`::before`・`::after`）で出した文字は数えません。それらで出した UI も映したいときは、`dom` を付けてください。
- **映る範囲は、基準の canvas が画面に占める範囲です。** 基準の canvas の外にも文字・画像・操作部品が出ているときと、canvas が無いゲームでは、ゲームの画面の全体になります。
- **`dom` を付けた要素があれば、その要素が画面に占める範囲が映ります。** 範囲を決めたいときに使ってください。
- **`only` を付けた canvas があれば、その canvas が画面に占める範囲が映ります。** その canvas を表示していないときは、Web と同じく、canvas の中身がそのままスクショになります。
- **`ignore` を付けた canvas が画面に出ているときも、画面から作ります。** その canvas も映ります。画面のとおりの重なり順で映るので、手前に出ることはありません。
- 画面から作れなかったとき（Android 7 以前の端末など）は、Web と同じ画像になります。
