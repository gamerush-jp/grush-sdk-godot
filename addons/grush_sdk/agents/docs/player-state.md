# 公開プレイヤー状態と相手探し

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#player-state

<a id="player-state"></a>
## 公開プレイヤー状態

他プレイヤーへ見せる進捗（称号・ひとことなど）の入れ物です。クラウドセーブとは別で、本人だけが読む非公開データはこの経路から一切読めません。

**ここに置いたものは他プレイヤーへ見えるユーザー生成コンテンツで、通報とモデレーションの対象になります。そのため payload に制約があります。**

| 制約 | 理由 |
|---|---|
| JSON オブジェクトに限る（裸の文字列・配列は不可） | 実質バイナリの詰め込み場所になる |
| 4KB 以下 | — |
| base64 のような読めない長い文字列を含まない（英数字と `+` `/` `-` `_` だけでできた 256 文字以上の文字列。末尾に `=` が 2 つまで付いたものも含む） | 通報されたとき人間が読めないとモデレーションが成立しない |

このほか、配列とオブジェクトの入れ子が 3000 段を超える payload と、キーか値に、対になっていないサロゲート（UTF-16 の文字列を文字の途中で切った切れ端）が届いた payload は受け付けません。GameRush が JSON として保存できないためです。切れ端が届くのは、JavaScript の文字列に入った切れ端と、Unity の payload に JSON のエスケープ（`\ud83d` など）で書いた切れ端です。Unity と Godot は、文字列にそのまま入った切れ端を U+FFFD に替えて送るので、その切れ端では断られず、切れ端だけが違うキーは同じキーになります。Godot の入れ子の上限は、3000 段より低くなります（[Godot 4](setup-godot.md#godot)）。

Unity の `payload` は、書き込みでは生の JSON 文字列で渡します。読み取りでは、応答の生 JSON である `GRushPlayerStatePage.RawJson` を自前のパーサへ渡し、`state.payload`（`GetMineAsync`・`SetMineAsync`）か `states[].payload`（`GetAsync`・`SampleAsync`）から読んでください（ランキングの `metadata` と同じです）。Godot は辞書、JavaScript はオブジェクトです。

```csharp
// Unity
await GRush.PlayerState.SetMineAsync("{\"title\":\"初心者\",\"level\":3}");
var mine = await GRush.PlayerState.GetMineAsync();
var others = await GRush.PlayerState.GetAsync(new[] { pseudoIdA, pseudoIdB });
```

```gdscript
# Godot
await GRush.player_state.set_mine({"title": "初心者", "level": 3})
var mine: Dictionary = await GRush.player_state.get_mine()
var others: Dictionary = await GRush.player_state.get_many([pseudo_id_a, pseudo_id_b])
```

```javascript
// JavaScript
await GRush.playerState.setMine({ title: "初心者", level: 3 });
const mine = await GRush.playerState.getMine();
const others = await GRush.playerState.get([pseudoIdA, pseudoIdB]);
```

Godot 側だけメソッド名が `get_many` なのは、`get` が Godot 側の `Object.get` と衝突してパースエラーになるためです。通信上のメソッド名は Unity と同じ `playerState.get` です。

`GetAsync` / `get_many` / `get` に渡せる疑似IDは、1 回 50 件までです。

**運営が伏せた状態は返りません。要求した疑似IDの数だけ返ってくる前提で書かないでください。エディタのモックでも `GRushMockPlayerStates.Define(id, json, hidden: true)` / `define(id, payload, true)` で同じ挙動を試せます。**

`SetMineAsync` / `set_mine` / `setMine` に `baseRevision` を渡すと楽観ロックになり、他所で更新されていれば `InvalidParams` で戻ります。省略すれば常に上書きします。

<a id="matchmaking"></a>
### 相手探し

非同期対戦の相手を探すために、同じゲームの他プレイヤーの公開状態をランダムに引けます。公開状態には相手探しに使う数値 `rating` を持たせられ、rating の範囲で絞れます。

```csharp
// Unity
await GRush.PlayerState.SetMineAsync("{\"deck\":\"fire\",\"level\":12}", -1, 1520);
var found = await GRush.PlayerState.SampleAsync(5, 1400, 1600);
if (found.Ok)
{
    foreach (var rival in found.Value.States) Debug.Log(rival.PseudoId + " " + rival.Rating);
}
```

```gdscript
# Godot
await GRush.player_state.set_mine({"deck": "fire", "level": 12}, null, {"rating": 1520})
var found: Dictionary = await GRush.player_state.sample({"count": 5, "min_rating": 1400, "max_rating": 1600})
if found["ok"]:
    for rival in found["value"]:
        print(rival["pseudo_id"], rival["rating"])
```

```javascript
// JavaScript
await GRush.playerState.setMine({ deck: "fire", level: 12 }, undefined, { rating: 1520 });
const found = await GRush.playerState.sample({ count: 5, minRating: 1400, maxRating: 1600 });
if (found.ok) for (const rival of found.value) console.log(rival.pseudoId, rival.rating);
```

| 呼び出し | Unity | Godot | JavaScript |
|---|---|---|---|
| 相手を引く | `PlayerState.SampleAsync(count, minRating, maxRating)` | `player_state.sample({ count, min_rating, max_rating })` | `playerState.sample({ count, minRating, maxRating })` |
| rating を書く | `PlayerState.SetMineAsync(json, baseRevision, rating)` | `player_state.set_mine(payload, base_revision, {"rating": r})` | `playerState.setMine(payload, baseRevision, { rating })` |

- 1 回に引けるのは 1〜20 件で、省略すると 10 件です。自分の状態と運営が伏せた状態と、どちらの向きでもブロック関係にある相手の状態は返りません。
- 相手探しは毎分 30 回まで（サインインしていれば 1 人ごと、ゲストは IP アドレスごと）で、超えると `RateLimited` です。
- 返るのは疑似ID・payload・rating などの状態だけで、名前とアイコンは返りません。
- rating の範囲は最小と最大を一緒に渡します。範囲を渡すと、rating を書いていない状態は返りません。
- rating は -1e9 より大きく 1e9 より小さい数値です。`null` を渡すと消え、渡さなければ今の値のまま payload だけを書き換えます。
- rating を書いていない状態の rating は、Unity では `HasRating` が `false`、Godot と JavaScript では `null` です。
- 相手探しは `protocolVersion` 7 以上の GameRush で使えます。それより古い GameRush では、相手探しは `Unsupported` になり、rating は送らずに payload だけを書きます。Unity は `GRush.IsMatchmakingAvailable` で確かめられます。
- `protocolVersion` が 7 以上でも、アプリの更新の間などは rating が書かれないことがあります。そのときも書き込みは成功し、payload は書かれます。rating が書けたかは、setMine が返す状態の rating で確かめてください。

<a id="player-state-report"></a>
### 通報

ゲームは通報の画面を描けません。`ReportAsync(pseudoId)` / `report(pseudo_id)` / `report(pseudoId)` を呼ぶと GameRush が確認を出し、プレイヤーが承諾したときだけ送られます。返るのは「送られたか」の真偽値です。ゲストは `SignInRequired` です。

確認には、GameRush が取り直した状態の中身と、持ち主の疑似IDの先頭 8 文字と更新日時が出ます。自分の状態と見つからない状態は、確認を出さずに `InvalidParams` です。確認を出してから送るまでに状態が書き換えられたときも `InvalidParams` です。受信箱や交換所の通報と違い、相手をブロックしません。

通報された状態は、運営がこのゲームに描かせて確かめます（[確認用の表示](player-state.md#player-state-preview)）。

<a id="player-state-preview"></a>
### 確認用の表示

**公開状態が通報されると、運営はその状態を、通報された時点の内容のままこのゲーム自身に描かせて確かめます。他プレイヤーの公開状態を画面に出すゲームは、確認用の表示で届く状態を受け取って描けるようにしてください。**

**他プレイヤーの公開状態を読むゲームは、確認用の表示の購読が必須です。2026-11-17 から、購読していないゲームが他プレイヤーの状態を読むと（`GetAsync` / `get_many` / `get` に他プレイヤーの疑似IDを渡す、相手探し）、`PreviewRequired` で失敗します。自分の状態の読み書きは、購読が無くても使えます。購読は他プレイヤーの状態を読む前に済ませ、読む間は外さないでください。**

```csharp
// Unity
void Start()
{
    GRush.PlayerState.PreviewReceived += page =>
    {
        // ほかのプレイヤーの状態を見せるのと同じ画面で描く。payload は RawJson の state.payload にある。
        ShowRival(page.States[0], page.RawJson);
    };
}
```

```gdscript
# Godot
func _ready() -> void:
    GRush.player_state.preview_received.connect(_on_preview)

func _on_preview(state: Dictionary) -> void:
    show_rival(state["payload"])  # ほかのプレイヤーの状態を見せるのと同じ画面で描く
```

```javascript
// JavaScript
GRush.playerState.onPreview((state) => {
  showRival(state.payload); // ほかのプレイヤーの状態を見せるのと同じ画面で描く
});
```

- 受け取った状態は、他プレイヤーの状態を見せるのと同じ画面・同じ形で描いてください。運営が見たいのは、他プレイヤーにどう見えるかです。
- 確認用の表示で開かれたときにだけ届き、普段のプレイでは届きません。
- 同じ状態は1回だけ届きます。購読より先に届いた状態は、購読したときに届きます。起動の直後に購読してください。
- 疑似IDは決まった値で、rating は届きません（Unity は `HasRating` が `false`、Godot と JavaScript は `null`）。
- 確認用の表示で使えるのは、表示言語と起動パラメータの読み取りだけです。ほかの呼び出し（プレイヤー情報・ランキング・公開状態の読み書き・受信箱・交換所・共有・マルチプレイなど）は `Unavailable` で失敗します。JavaScript のクラウドセーブはサインインしていないときと同じ扱いで、`fallback: "local"` 付きの読み書きは端末の保存を使います。起動の途中でこれらの結果を待って止まらないようにしてください。
- `protocolVersion` 10 以上の GameRush で、Unity `v1.12.0`・Godot `v1.10.0`・JavaScript `v0.12.0` 以降の SDK で使えます。Unity は `GRush.IsPlayerStatePreviewAvailable` で確かめられます。`PreviewRequired` を返すのは Unity `v1.15.0`・Godot `v1.12.0`・JavaScript `v0.14.0` 以降の SDK で、それより前の SDK では `Internal` になります。
- エディタのモックでは、Unity は `GRushMockPlayerStates.Preview(id, json)`、Godot は `GRushMockPlayerStates.preview(id, payload)`、JavaScript は `GRush.mock.previewPlayerState(id, payload)` で状態を届けて試せます。
