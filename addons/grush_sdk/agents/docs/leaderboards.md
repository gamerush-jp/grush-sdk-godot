# ランキング

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#leaderboards

<a id="leaderboards"></a>
## ランキング

**ランキングの定義は作者が宣言するもので、ゲームからは作れません。**

ゲームからできるのは、宣言済みの枠へ投稿することと読むことだけです。宣言は Studio の画面、ビルドに同梱する `grush.json`（下の「grush.json で宣言する」）、API（[API トークン](api-tokens.md#api-tokens)）のどれでもできます。

**スコアはゲームからの自己申告値で、GameRush は値を検証していません。**

応答の `Verified` / `verified` は常に `false` です。これをゲーム内で表示する義務はありません — 使いたいときのために値を渡しているだけで、GameRush 側の画面では GameRush が自分で明示します。

entry の名前とアイコン（Unity は `DisplayName` / `AvatarUrl`、Godot は `display_name` / `avatar_url`、JavaScript は `displayName` / `avatarUrl`）は、その相手がサインイン済みで、GameRush の設定「ゲームで名前とアイコンを表示する」をオフにしていないときに入ります。この設定は既定でオンで、全ゲームに共通です。ゲストと、設定をオフにした相手は `null` です。

名前を出すためにゲームから許可を求める必要はありません。`RequestProfileAsync` / `request_profile` / `requestProfile` はダイアログを出さず、自分の表示名を返します。ゲストなら `SignInRequired`、設定がオフなら `ConsentDeclined` です。`RevokeProfileAsync` / `revoke_profile` / `revokeProfile` は設定を変えず、いまのプレイヤー情報を返すだけです。

```csharp
// Unity
var boards = await GRush.Leaderboards.ListAsync();
var posted = await GRush.Leaderboards.SubmitAsync("high_score", 12000);
var page = await GRush.Leaderboards.TopAsync("high_score", 20);
var near = await GRush.Leaderboards.AroundMeAsync("high_score", 5);
foreach (var entry in page.Value.Entries)
{
    var label = entry.IsGuest ? "ゲスト" : (entry.DisplayName ?? "匿名");
}
```

```gdscript
# Godot
var boards: Dictionary = await GRush.leaderboards.list()
var posted: Dictionary = await GRush.leaderboards.submit("high_score", 12000)
var page: Dictionary = await GRush.leaderboards.top("high_score", {"limit": 20})
var near: Dictionary = await GRush.leaderboards.around_me("high_score", {"range": 5})
```

```javascript
// JavaScript
const boards = await GRush.leaderboards.list();
const posted = await GRush.leaderboards.submit("high_score", 12000, { operationId: runId });
const page = await GRush.leaderboards.top("high_score", { limit: 20 });
const near = await GRush.leaderboards.aroundMe("high_score", { range: 5 });
```

| 投稿が弾かれる条件 | HTTP | 返る GRushErrorCode |
|---|---|---|
| 宣言されていない `key` / 停止中の枠 | 404 | `InvalidParams` |
| 作者が宣言した値域の外 | 400 | `InvalidParams` |
| 値域を宣言していない枠 | 400 | `InvalidParams` |
| `valueType` に合わない値（`int` と `duration_ms` の枠に小数、`duration_ms` の枠に負の値） | 400 | `InvalidParams` |
| 保存したときに 1KB を超える `metadata` | 400 | `InvalidParams` |
| キーか値に、対になっていないサロゲート（UTF-16 の文字列を文字の途中で切った切れ端）が届いた `metadata`（下の段落） | 400 | `InvalidParams` |
| 配列とオブジェクトの入れ子が 3000 段を超える `metadata` | 400 | `InvalidParams` |
| 対になっていないサロゲートが届いた `operationId`（下の段落） | 400 | `InvalidParams` |
| 有効プレイ 10 秒未満のセッション | 400 | `InvalidParams` |
| session が見つからない / 別ゲーム・別プレイヤーの `session`（同じプレイの間は再送しても通らない。下の段落） | 403 | `Unavailable` |
| 投稿上限（1 つの session で 60 件、1 人毎分 12 件） | 429 | `RateLimited` |
| ホストに再生中のセッションが無い（投稿がサーバへ届かない） | — | `Unavailable` |

対になっていないサロゲートが GameRush へ届くのは、JavaScript の文字列に入った切れ端と、Unity の `metadataJson` に JSON のエスケープ（`\ud83d` など）で書いた切れ端です。Unity と Godot は、文字列にそのまま入った切れ端を U+FFFD に替えて送るので、その切れ端では弾かれません。そのため切れ端だけが違う `metadata` のキーは同じキーになり、切れ端だけが違う `operationId` は同じ値になって、同じ投稿の再送として扱われます。Godot の `metadata` の入れ子の上限は、3000 段より低くなります（[Godot 4](setup-godot.md#godot)）。

集約が `best` の枠で、自己ベストを超えない値域内の値を `metadata` なしで投稿したときは、何も保存しないので、有効プレイ・session・投稿上限の条件では弾かれません。成功として今の値と順位が返り、`Updated` / `updated` は `false` です。投稿上限にも数えません。自分のエントリが作者に非表示にされているときは、この扱いになりません。

**session が拒否された投稿は、GameRush の側の一時的な失敗と同じ `Unavailable` で返ります。ゲームから session を取り直すことはできず、同じプレイの間に再送しても通りません。`Unavailable` の投稿を再送するときは、回数を区切ってください。更新前の GameRush のモバイルアプリでは、session が拒否された投稿は `ConsentDeclined` で返るので、投稿の `ConsentDeclined` も同じように扱ってください。これを除くと、ランキングで `ConsentDeclined` が返るのは `FriendsAsync` / `friends` だけです。**

`session` はゲームが指定できません。信頼済みの親 UI が live なセッションを付け、そのセッションがこのゲーム・この相手のものかをサーバが検証します。

`AroundMeAsync` / `around_me` / `aroundMe` は、自分がまだ載っていないときに空の一覧を返します。先頭を返すとゲーム側が「自分は1位」と誤読するためです。

上位の件数（`limit`）は省略すると 20 件で、最大 100 件です。自分の周りの前後の件数（`range`）は省略すると 5 件で、最大 25 件です。最大を超えた値は、最大に切り詰めて返します。

毎分の投稿上限は時間が経てば回復し、JavaScript の結果には待ち時間 `retryAfterMs` が入ります。session あたりの投稿上限は、その session の間は回復しません。

`FriendsAsync` / `friends` は相互フォローに絞った一覧ですが、ゲームごとのフレンド同意がまだ無いため、現在は常に `ConsentDeclined` を返します。

投稿に添える `metadata` は 1KB までです。大きさは JSON の文字数ではなく GameRush が保存したときの大きさで測り、数値の多い JSON は文字数より大きく数えられます。余裕を持たせてください。エディタのモックはこの上限を確かめません。エントリの `metadata` は、Godot は辞書、JavaScript は値のまま返しますが、Unity は返しません。`metadata` が要る Unity のゲームは、応答の生 JSON である `GRushLeaderboardPage.RawJson` を自前のパーサへ渡してください。

### grush.json で宣言する

ビルドのいちばん上（`index.html` と同じ階層）に `grush.json` を置くと、そのビルドが最新になったときに中のランキングの定義が反映されます。Studio からアップロードするだけで定義でき、API トークンは要りません。公開中のゲームでは、新しいビルドは審査で承認されてから配信されるので、定義もそのビルドが承認されて配信される時点で反映されます。それまでは、配信中のビルドの定義がそのまま使われます。

```json
{
  "leaderboards": [
    {
      "key": "high_score",
      "title": "ハイスコア",
      "sort": "desc",
      "valueType": "int",
      "aggregation": "best",
      "period": "all_time",
      "minValue": 0,
      "maxValue": 1000000
    },
    {
      "key": "weekly_time",
      "title": "今週のタイムアタック",
      "sort": "asc",
      "valueType": "duration_ms",
      "aggregation": "best",
      "period": "weekly",
      "minValue": 0,
      "maxValue": 3600000,
      "enabled": true
    }
  ]
}
```

| 項目 | 必須 | 値 |
|---|---|---|
| `key` | 必須 | 英数字と `. _ : -` で 1〜64 文字。`.` と `..` だけのキーは使えない。ゲームから投稿するときの識別子 |
| `title` | 必須 | 1〜60 文字。改行と制御文字は空白にして保存します |
| `sort` | 必須 | `desc`（大きいほど上位）か `asc`（小さいほど上位） |
| `valueType` | 必須 | `int` / `float` / `duration_ms` |
| `aggregation` | 必須 | `best` / `last` / `sum` |
| `period` | 必須 | `all_time` / `daily` / `weekly` / `monthly` |
| `minValue` / `maxValue` | 任意 | 数値。両方そろえて書き、`minValue` を小さくします。省くと値域なしで、その枠は投稿を受けません |
| `enabled` | 任意 | 省くと `true`。`false` で停止します |

最上位に書けるのは `leaderboards` と `$schema` だけです。知らない項目・重複した `key`・21 個以上の定義・64KB を超えるファイルは、綴りの誤りを見逃さないよう拒みます。Studio はアップロードの前に同じ規則で確かめます。

反映は `key` ごとで、同じ内容なら何も書きません。`grush.json` に書かなかった `key` の枠は、消えも止まりもしません。止めるときは `"enabled": false` と書きます。消すときは、Studio の画面か API で行ってください。`grush.json` に書いた `key` の枠の `title`・値域・`enabled` は、Studio の画面や API で変えても、`grush.json` を含むビルドを次に上げたときにファイルの値へ戻ります。

**スコアが投稿された枠の `sort`・`valueType`・`aggregation`・`period` を変える宣言と、すでにある枠と合わせて 1 ゲーム 20 個を超える宣言は、ビルドごと失敗になります。変えたいときは新しい `key` で宣言してください。**

`grush.json` はほかのファイルと同じく配信されるので、ゲームから読んでも構いません。gzip で事前圧縮したものは読めますが、brotli で圧縮したものは受け付けません。API トークンで `grush.json` を含むビルドを上げるときは、`builds:write` に加えて `leaderboards:write` が要ります。

| エンジン | 置く場所 | ビルドの最上位へ届く方法 |
|---|---|---|
| Unity | プロジェクトの直下（`Assets/` の隣）の `grush.json` | WebGL でビルドすると、SDK が出力先の最上位へ写します。ファイルが無いのに出力先に `grush.json` が残っていれば、消さずに警告を出します。`Assets/` や `StreamingAssets/` に置いても最上位には出ません |
| Godot | `res://grush.json` | Web で書き出すと、SDK の書き出しプラグインが `index.html` の隣へ写します。ファイルが無いのに書き出し先に `grush.json` が残っていれば、消さずに警告を出します。`.pck` の中のファイルは読みません |
| JavaScript | `index.html` の隣の `grush.json` | そのままアップロードします |

エディタとローカルのモックも同じ `grush.json` を読み、最初のランキングの呼び出しの前にその枠を宣言します。JavaScript 版が読むのはローカルサーバから開いたときだけで、3 秒以内に読めなければ読まなかったものとして扱います。`file://` では `GRush.mock.loadLeaderboards(manifest)` に中身を渡してください。中身を渡すときは Unity が `GRushMockLeaderboards.LoadManifest(json)`、Godot が `GRushMockLeaderboards.load_manifest(json_text)` で、どれも読むのはアップロードと同じ規則です。

モックは書式の誤りをアップロードと同じ文言で警告し、その中身を使いません。中身を渡したときの誤りは、`LoadManifest` / `load_manifest` / `loadLeaderboards` が `InvalidParams` で返します。`enabled: false` の枠は一覧に出ず、投稿と取得は宣言していない `key` と同じ失敗（`InvalidParams`）です。`grush.json` で `minValue` / `maxValue` を書かなかった枠は、GameRush と同じく投稿を受けません。`period` が `daily` / `weekly` / `monthly` の枠は GameRush と同じ期間キー（UTC）を返し、期間が変わると空からやり直します。ファイルを自動で読むときは、同じ `key` を `Define` / `define` / `defineLeaderboard` で宣言してあればそちらを使います。`LoadManifest` / `load_manifest` / `loadLeaderboards` に渡した定義は、それらの宣言を置き換えます。

### 集約が sum のランキングを再送するときは識別子を渡す

Unity の `SubmitAsync(key, value, metadataJson, operationId)` と Godot の `submit(key, value, metadata, operation_id)` の第4引数、JavaScript の `submit(key, value, { metadata, operationId })` の `operationId` は、同じ投稿の再送を弾くための識別子です。

**加算は冪等ではありません。**

投稿がサーバに届いて保存された後で応答だけが失われた場合、そのまま送り直すと二重に足され、集約後の値からは元へ戻せません。再送するなら同じ `operationId` を渡してください。`best` と `last` は同じ値を再適用しても結果が変わらないので、省略して構いません。
