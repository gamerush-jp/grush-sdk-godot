# GameRush SDK for Godot 4

GameRush の GameAPI を Godot 4 から呼ぶアドオン。ビルドの書き出し方は [対応エンジンと書き出しガイド](https://gamerush.jp/engines)。使い方の正（ランキング・公開プレイヤー状態・投稿が弾かれる条件とエラーコード・API トークン）は [SDK ガイド](https://gamerush.jp/sdk)。

## 導入

[リリース](https://github.com/gamerush-jp/grush-sdk-godot/releases)から版（例: `v1.10.0`）を選んで取得し、`addons/grush_sdk/` をプロジェクトの `addons/` へコピーし、`Project > Project Settings > Plugins` で **GameRush SDK** を有効にする。有効化すると autoload シングルトン `GRush` が自動で登録される。

書き出しは Web。それ以外のプラットフォームでは自動的にモックへ落ちる。

## 使い方

```gdscript
var self_result: Dictionary = await GRush.player.get_self()
if self_result["ok"]:
    print(self_result["value"]["pseudo_id"])

var joined: Dictionary = await GRush.net.join("duel")
if joined["ok"]:
    var room: GRushRoom = joined["value"]
    room.message_received.connect(func(message: Dictionary) -> void: print(message["from"]))
    room.error_received.connect(func(error: Dictionary) -> void: push_warning(error["code"]))
    room.send(payload, GRush.CHANNEL_UNRELIABLE, GRush.EVERYONE)
```

部屋が1通を捨てると `error_received` が `{"code": String, "message": String}` で届く。`code` は `"messageTooLarge"`・`"rateLimited"`・`"badFrame"` で、ほかの値が届くこともある。部屋はつながったままで、続けて送れる。部屋が閉じるときは `closed` だけが届く。

すべての API は `{"ok": bool, "value": Variant, "code": String, "message": String}` を返し、例外を投げない（アナリティクスは `bool` を返す。下記）。GameRush の外で動かした場合は `ok` が `false`、`code` が `"unsupported"` になるだけで、ゲームは止まらない。

### 相手探し

```gdscript
await GRush.player_state.set_mine({"deck": "fire", "level": 12}, null, {"rating": 1520})
var found: Dictionary = await GRush.player_state.sample({"count": 5, "min_rating": 1400, "max_rating": 1600})
if found["ok"]:
    for rival in found["value"]:
        print(rival["pseudo_id"], rival["rating"], rival["payload"])
```

`sample` は同じゲームの他プレイヤーの公開状態をランダムに返す（`count` は 1〜20、既定 10）。自分と運営が伏せた状態は返らず、名前も返らない。`min_rating` と `max_rating` は一緒に渡し、範囲を渡すと `rating` の無い状態は返らない。`set_mine` の第3引数の `rating` は -1e9 より大きく 1e9 より小さい数値で、`null` で消し、渡さなければ今の値のまま。書かれていない `rating` は `null`。古い GameRush（`protocolVersion` 7 未満）では `sample` が `unsupported`、`set_mine` は `rating` を送らずに payload だけを書く。

### 公開プレイヤー状態の確認用の表示

```gdscript
func _ready() -> void:
    GRush.player_state.preview_received.connect(_on_preview)


func _on_preview(state: Dictionary) -> void:
    show_rival_card(state["payload"])
```

GameRush の確認用の表示で、公開プレイヤー状態がほかのプレイヤーにどう見えるかを描くよう頼まれたときに、`preview_received` が発火する。`state` は `get_mine` の値と同じ形（`pseudo_id`・`payload`・`revision`・`rating`・`updated_at`）。受け取ったら、ほかのプレイヤーの状態を見せるのと同じ画面で `payload` を描く。`pseudo_id` は本物の疑似 ID ではない決まった値で、`rating` は `null`。同じ状態は1回だけ届き、接続より先に届いた状態は接続した後に届く。JS の呼び出しの中ではなく `call_deferred` で後から配る。他プレイヤーの状態を見せるゲームは接続しておく。確認用の表示の外では発火しない。古い GameRush（`protocol_version` 10 未満）と GameRush の外でも発火せず、ほかの機能はそのまま使える。`GRush.use_backend` でバックエンドを差し替えても `GRush.player_state` は同じインスタンスのままで、接続は新しいバックエンドから受け続ける。

### 受信箱

```gdscript
await GRush.inbox.send(rival_pseudo_id, "battleResult", {"stage": 3, "win": true})
var inbox: Dictionary = await GRush.inbox.list({"unread_only": true})
if inbox["ok"]:
    for message in inbox["value"]["messages"]:
        print(message["from"], message["kind"], message["payload"])
```

同じゲームの疑似 ID 宛てに、小さい構造化メッセージ（非同期対戦の結果の通知など）を送る。ゲストも送受信できる。**payload で文章や画像は送れない。** payload は辞書で、文字列の値とキーは識別子（`^[A-Za-z0-9_.:-]{1,32}$`）だけ、ほかは数値・真偽値・null。入れ子は最上位を 1 段目として 4 段まで、値は合計 64 個まで、JSON にして 1KB まで。`kind` は `^[A-Za-z0-9._:-]{1,32}$`。合わなければ `invalidParams`。利用者どうしの文章や画像のやりとりには使わない。

`list` の value は `{"messages", "unread_count", "next_cursor"}` で、新しい順（`limit` は 1〜50、既定 20）。続きは `next_cursor` を `cursor` に渡す。`mark_read` / `remove` は 1 回 50 件まで。同じゲームの疑似 ID でない宛先は `invalidParams`、送りすぎ（毎時・毎日の上限）は `rateLimited` で、時間が経てば回復する。`report(message_id)` は GameRush が確認を出し、承諾されたら `true`。通報すると送り手をブロックし、その相手のメッセージと出品は見えなくなる。ゲストは `signInRequired`。古い GameRush（`protocolVersion` 7 未満）ではどれも `unsupported`。

### 交換所

```gdscript
# 1. 出すアイテムをセーブで仮置きにし、2. operation_id と一緒に保存してから出品する。
var created: Dictionary = await GRush.trade.create(
    {"item": "sword", "count": 1}, {"item": "gem", "count": 3}, save["escrow_operation_id"],
    {"offer_key": "sword", "want_key": "gem"}
)

# 4. 終わった取引をセーブへ反映し、保存してから ack する。5. 取引 ID で二度反映しない。
var mine: Dictionary = await GRush.trade.mine()
```

プレイヤーがアイテムを出品し、同じゲームの別のプレイヤーが `accept(trade_id, give)` で受ける。ゲストも出品・受諾できる。GameRush はアイテムの正当性を確かめず、交換が片方だけ成立しないことと、終わった取引を取りこぼさないことだけを保証する。

取りこぼさないために、次の順で使う。

1. 出品の前に、出すアイテムを手元のセーブで仮置き（使えない状態）にする
2. `operation_id`（`^[A-Za-z0-9._:-]{1,64}$`）をセーブに保存してから `create` する
3. 応答が失われたら、同じ `operation_id` で呼び直す。同じ `operation_id` の再送は、中身によらず先に作った出品を返す
4. `mine()` の `pending` をセーブに反映し、セーブを永続化してから `ack` する（`ack` に渡せる id は 1 回 50 件まで）
5. 反映済みの取引 ID をセーブに持ち、同じ取引を二度反映しない

`pending` の `action` は `receiveGive`（出品者が `give` を受け取る）・`returnOffer`（出品者が `offer` を戻す。取り下げ・期限切れ・運営の非表示）・`receiveOffer`（受けた側が `offer` を受け取る）。知らない値は反映せず、ack もしない。

受付中の出品が 10 件あるときの `create` は `invalidParams` で、待っても直らない（取り下げるか、成立・期限切れを待つ）。毎日 30 件の出品と毎時 30 件の受諾の上限は `rateLimited` で、時間が経てば回復する。

**offer・want・give で文章や画像は送れない。** 形は受信箱の payload と同じで、大きさは JSON にして offer 2KB・want 1KB・give 2KB まで。利用者どうしの文章や画像のやりとりには使わない。

`accept` は先に取られた・期限切れ・取り下げ・見えない出品をエラーにせず、`outcome`（`matched` / `taken` / `expired` / `cancelled` / `notFound`）で返す。`trade` は `matched` のときだけ入る。同じ取引への再送は `matched`。`create` の options の `to` に疑似 ID を渡すと指名の出品になり、`expires_in_sec` は 600〜604800（既定 3 日）。受付中の出品は 1 人 10 件まで。`list` は他人の公開の出品と自分宛ての指名の出品のうち、受付中のもの（新しい順）。`report(trade_id)` は GameRush が確認を出し、承諾されたら `true`。通報すると出品者をブロックする。古い GameRush（`protocolVersion` 7 未満）ではどれも `unsupported`。

### 共有

```gdscript
if await GRush.share.is_available():
    var shared: Dictionary = await GRush.share.share_screen("ステージ3をクリア")
```

GameRush の確認シートが出て、プレイヤーが送り先を押したときに共有が開く。`value` は `{"status": "opened"}` か `{"status": "cancelled"}` だけ。`share` の画像は PNG にして base64 で渡す。`share_screen` はゲームの canvas のスクショを送る。自前の画像を送るなら `share(text, image)`（`Image`）。共有は 5 秒に 1 回までなので、1 回のボタン操作で呼ぶのはどちらか一方にする。共有したことを条件に報酬を出さない。本文は 100 文字までで、URL と @メンションを含むと `invalidParams`。古い GameRush（`protocol_version` 3 未満）では `unsupported`。

#### 起動パラメータを添える

```gdscript
var shared: Dictionary = await GRush.share.share_screen("ステージ3に挑戦", {"stage": "3"})
if not shared["ok"] and shared["code"] == "unsupported":
    shared = await GRush.share.share_screen("ステージ3に挑戦")
```

`share(text, image, launch_params)` と `share_screen(text, launch_params)` は、共有リンクに `?gp.stage=3` のように起動パラメータを載せる。リンクを開いた人のゲームでは `GRush.launch` に渡る（下の「起動パラメータ」）。キーと値は String で、制限は「起動パラメータ」と同じ。1つでも合わなければ共有を開かずに `invalidParams`。空の Dictionary は渡さないときと同じ。古い GameRush（`protocol_version` 9 未満）では、共有を開かずに `unsupported` を返すので、起動パラメータを外して呼び直せば共有できる。**リンクは誰にでも見え、そのまま転送される。** プレイヤーを識別できる値（招待コードなど）を入れない。受け取る側のゲームは値を信用せず、確かめてから使う。

### 表示言語

```gdscript
GRush.locale.changed.connect(func(next: Dictionary) -> void: print(next["locale"]))
var fetched: Dictionary = await GRush.locale.fetch()
if fetched["ok"]:
    print(fetched["value"]["locale"])
```

GameRush 本体の表示言語を読む。`value` は `{"locale": "ja-JP", "source": "user", "languages": PackedStringArray}`。`source` は `"user"`（プレイヤーが選んだ）・`"system"`（アプリの端末設定）・`"device"`（ブラウザの言語）で、今後増えても動くように書く。`GRush.locale.current()` は取得済みなら同じ Dictionary、まだなら `null` を返す。表示言語が決まったとき・変わったときに `changed` が発火する（JS の呼び出しの中ではなく `call_deferred` で後から配るので、取得の途中の変更を取りこぼさないよう `fetch` より先に接続する）。古い GameRush（`protocol_version` 4 未満）では `fetch` が `unsupported`、`current` が `null`。`source` は必ず入り、GameRush が渡さなければ `"device"`。`languages` は空にならず、GameRush が空の一覧を渡せば `[locale]`。`GRush.use_backend` でバックエンドを差し替えても `GRush.locale` は同じインスタンスのままで、`changed` への接続は新しいバックエンドの通知を受け続ける。

### 起動パラメータ

```gdscript
var launched: Dictionary = await GRush.launch.fetch()
if launched["ok"]:
    var item: String = launched["value"]["params"].get("item", "")
    if item != "" and owns_item(item):
        open_item(item)
```

GameRush の URL に `gp.` を付けて載せたキーと値を読む。ゲームのページの URL が `/g/<コード>?gp.item=sword&gp.stage=3` なら `value` は `{"params": {"item": "sword", "stage": "3"}}`（キーも値も `String`）。シェアしたリンクから特定のアイテムやステージへ飛ばすのに使う。

**値を信用しない。** リンクは誰でも作れる。アイテムが存在するか・プレイヤーが持っているか・ステージが解放済みかをゲームの側で確かめ、確かめられなければ無視する。

キーは英数字と `_-` で 32 文字まで（`__proto__` は使えない）、値は英数字と `._~:,-` で 128 文字まで（空も可）、8 個まで。形の合わない項目と、2回書かれたキーは GameRush が落とし、8 個を超えたら全部落とす。渡るのは、プレイヤーが最初に開いたスライドのゲームだけで、別のゲームへスワイプして戻ったときは `params` が空。フィードではページを読み直すと空になるが、単体表示や埋め込みでは読み直すと同じ値がまた渡ることがあるので、何度渡っても困らないように書く。`fetch` は GameRush から届くまで待ち、`GRush.launch.current()` は届く前なら `null`。古い GameRush（`protocol_version` 8 未満）と GameRush の外では `fetch` が `unsupported`、`current` が `null`。GameRush のアプリ側が古くて答えられないときは、`unsupported` ではなく空の `params` が返る。

### アナリティクス

```gdscript
GRush.analytics.log_onboarding_step(1, "tutorial_start")
GRush.analytics.log_funnel_step("shop", "visit-1", 2, "item_selected", {"tab": "weapons"})
GRush.analytics.log_custom_event("boss_defeated", 1, {"stage": "3"})
GRush.analytics.log_economy_event(
	GRush.AnalyticsApi.FLOW_SINK, "coin", 50, 120, GRush.AnalyticsApi.TRANSACTION_SHOP, "sword"
)
```

作者のアナリティクスへ、オンボーディングとファネルのステップ・カスタムイベント・通貨の入手と消費を送る。

- **ほかの API と違い、どれも同期で `bool` を返す。** `await` せずにどこからでも呼べる。`true` は GameRush へ渡したことで、保存されたことではない
- 形が不正なとき（下の制限）は `false`。古い GameRush（`protocol_version` 6 未満）と GameRush の外では `false`。`GRush.analytics.is_available()` は GameRush の中で送れるかを返す（エディタと Web 以外の書き出しではモックが `true` を返す）
- `step` は 1〜100。`value` は省略で 1、絶対値 1e9 まで。`amount` は正の値で 1e12 まで、`ending_balance`（その後の残高）は絶対値 1e15 まで
- `flow_type` は `"source"`（入手）か `"sink"`（消費）。`transaction_type` の標準の値は `TRANSACTION_*` の定数（`TimedReward`・`Onboarding`・`Shop`・`Gameplay`・`ContextualPurchase`）で、ほかの値も受ける
- イベント名・ファネル名・`funnel_session_id` は英数字と `._:-` で 64 文字まで、通貨と `transaction_type` は 32 文字まで。`funnel_session_id`・`step_name`・`item_sku` は空文字で省略できる
- `step_name`・`item_sku`・`fields` の値は1行のテキストに直してから受ける。改行・制御文字・双方向の上書きと isolate は空白に直し、前後の空白を落としてから 40 文字まで数える。直した結果が空（空白や見えない文字だけ）の `step_name` と `item_sku` は省略と同じに扱い、`fields` の値は拒む。`fields` は String から String への Dictionary で3つまで（値が StringName などの String 以外なら拒む）、キーは英数字と `_` で 32 文字まで
- オンボーディングとファネルの同じステップは、1セッションで最初の1回だけが残る。セッションはページを読み直しても続く。同じファネルを何度も通るなら、通るたびに別の `funnel_session_id` を渡す
- 名前・値・`fields` に、プレイヤーを識別できる情報を入れない
- GameRush の中でも、ゲームが前面に出るまでの分は溜めてから送る。溜められるのは 30 件までで、超えた分は `false`
- `true` を返しても、次の分は保存されない
  - 前面に出た後に GameRush 本体が掛ける上限を超えた分。本体は 500ms に1件、まとめて最大 30 件まで受け、送る前の列は合計 200 件まで
  - セッションあたりの保存の上限を超えた分。オンボーディングを含むファネルのステップ 200 件・カスタムイベント 500 件・エコノミー 500 件
  - 送れなかった分（送り直さない）

## エディタでの動作確認

Web 書き出し以外では `grush_backend_mock.gd` が使われる。`GRushMock` の static 変数で挙動を切り替える。

```gdscript
GRushMock.signed_in = true
GRushMock.display_name = "Editor Player"
GRushMock.grant_profile_consent = false
GRushMock.unreliable_drop_rate = 0.1
GRushMock.share_status = "cancelled"

var opponent := GRush.mock_add_peer("Sparring Partner")
opponent.received.connect(func(message: Dictionary) -> void: opponent.send(reply))
```

`GRush.mock_add_peer` で作った相手は同じプロセス内の2人目の peer として部屋に入り、送受信が実際に往復する。

`GRush.mock_raise_room_error(code, message)` は、自分がいる部屋に `error_received` を届ける（次のフレーム以降に届き、部屋は閉じない）。部屋にいなければ `false` を返す。

表示言語のモックは `GRushMock.locale`（例 `"en-US"`、`source` は `"user"`）を返し、空なら `OS.get_locale()` を BCP47 に直して `source: "device"` で返す。モックは `changed` を発火しない。

確認用の表示のモックは `GRushMockPlayerStates.preview(pseudo_id, payload, revision = 1, rating = null)` で起こす。渡した値を持つ状態が後のフレームで `preview_received` に届き、`updated_at` は呼んだ時刻。GameRush が渡す `pseudo_id` は決まった値で `rating` は `null` なので、描き分けを試すときだけ変える。呼ぶたびに1回だけ届き、接続が無いうちに呼んだ分は、最後に呼んだ分だけが接続した後に届く。`pseudo_id` が空、`revision` が負、`rating` が有限の数値でも `null` でもないときは何もしない。`GRushMockPlayerStates.reset()` で、まだ届いていない分を捨てる。

```gdscript
GRushMockPlayerStates.preview("mock-rival-1", {"deck": "fire", "level": 12})
```

起動パラメータのモックは `GRushMock.launch_params`（既定 `{}`。例 `GRushMock.launch_params = {"item": "sword"}`）をそのまま返す。GameRush の制限では確かめない。

共有のモックは確認シートを出さず、`GRushMock.share_status`（既定 `"opened"`）を返す。`GRushMock.share_available = false` で共有できない環境を試せる。起動パラメータは GameRush と同じ制限で確かめ、合わなければ `invalidParams`。本文と画像の検査はしない。

アナリティクスのモックは、GameRush と同じ検査をして、通ったイベントを1件ずつ出力し、直近の 200 件を `GRushMock.analytics_events`（GameRush へ渡すのと同じ形の Dictionary の配列）に持つ。弾いたイベントは、GameRush と同じく理由ごとに1回だけ警告する。前面に出るまでの 30 件の溜め・本体の上限・同じステップを最初の1回だけ残す扱い・セッションあたりの上限は再現しないので、モックでは `true` の分がすべて記録に残る。どこへも送らない。モックが名乗る `protocol_version` は 10。モックを使うのは Web 以外の書き出しとエディタだけで、Web の書き出しを GameRush の外で開いたときは、どの呼び出しも `false` になる。

相手探し・受信箱・交換所のモックは、`GRushMock.RIVALS` の 3 人の相手を持つ。相手はそれぞれ rating 付きの公開プレイヤー状態を持ち、届いたメッセージを同じ kind と payload で送り返す。はじめと `GRushMockInbox.reset()` / `GRushMockTrades.reset()` の後は、最初の相手からのメッセージ1通と、相手の受付中の出品を2件持つ。payload・offer・want・give の形、`operation_id` での冪等、受付中の出品の上限、受諾の `outcome`、`pending` と ack は GameRush と同じ規則で動く（バイト数は Godot の `JSON.stringify` で数えるので、`3.0` のような小数点の付く数値を GameRush より多く数えることがある）。通報を承諾すると（`GRushMock.confirm_inbox_report` / `confirm_trade_report`、既定 `true`）相手をブロックし、その相手のメッセージと出品は見えなくなる。プレイヤー状態の通報は伏せていない状態にだけ届き、確認の答えを `GRushMock.confirm_player_state_report`（既定 `true`）で決める。

```gdscript
GRushMockInbox.receive(GRushMock.RIVALS[0], "battleResult", {"stage": 3, "win": false})
var listing = GRushMockTrades.offer(GRushMock.RIVALS[1], {"item": "bow"}, {"item": "gem"}, {"to_self": true})
GRushMockTrades.accept(my_trade_id, {"item": "gem"})  # 相手が受けて、自分の pending に receiveGive が載る
GRushMockTrades.expire(listing["id"])
GRushMockPlayerStates.define("custom-rival", {"level": 3}, false, 1300)
```

**`unreliable_drop_rate` は既定 0 だが、出荷前に必ず 0 より大きくして試すこと。** WebSocket 中継では `unreliable` も落ちずに届くため、パケットが落ちる前提で書けているかを確認できる場所はエディタのモックだけになる。

### grush.json をモックで使う

ランキングの定義は、プロジェクトの直下の `res://grush.json` に書ける。書式は [SDK ガイドのランキング](https://gamerush.jp/sdk#leaderboards)。

- モックは、最初のランキングの呼び出しの前にこのファイルを読み、その枠を宣言する。ファイルが無ければ何もしない。書式の誤りはアップロードと同じ文言で警告し、その中身は使わない
- Web で書き出すと、このファイルが `index.html` の隣へ写る（アドオンの書き出しプラグインが写す。エクスポートダイアログ・`--export-release`・下の GameRush SDK Build のどれでも写る）。ファイルが無いのに書き出し先に `grush.json` が残っていれば、消さずに警告を出す（残ったままアップロードすると、その中身で定義を書き換える）。GameRush はアップロードされたビルドの最上位の `grush.json` だけを読む
- ファイルを自動で読むときは、`GRushMockLeaderboards.define` で同じ key を宣言してあればそちらを使う。`GRushMockLeaderboards.load_manifest(json_text)` に渡した定義は、`define` の宣言を置き換える。`load_manifest` を呼ぶと、ファイルは自動では読まない。`load_manifest` は誤りを `invalidParams` で返す
- `enabled: false` の枠は一覧に出ず、投稿と取得は宣言していない key と同じく `invalidParams` になる。grush.json で `minValue` / `maxValue` を書かなかった枠は、GameRush と同じく投稿を受けない
- `period` が `daily` / `weekly` / `monthly` の枠は、GameRush と同じ期間キー（UTC）を返し、期間が変わると空からやり直す
- `GRushMockLeaderboards.reset()` の後は、次のランキングの呼び出しでファイルを読み直す

## GameRush 向けの書き出し（任意）

`addons/grush_sdk_build/` は、GameRush 向けの推奨設定で Web 書き出しをするための別アドオン。使う場合は `addons/` へコピーし、`Project > Project Settings > Plugins` で **GameRush SDK Build** を **GameRush SDK とは別に**有効にする。Godot 4.3 以降と、Web 用の書き出しテンプレート（`Editor > Manage Export Templates`）が必要。

`export_presets.cfg` に **「GameRush Web」** という名前のプリセットを作り、既にあれば推奨値へ書き戻す（ほかのプリセットには触れない）。スレッドは無効（GameRush の配信は COOP/COEP ヘッダを送らない）、スマホ向けテクスチャ圧縮（ETC2/ASTC）は既定で有効、`addons/grush_sdk_build/*` は書き出しから除外される。書き出し先がプロジェクト内なら、その親フォルダ（既定では `build/`）に `.gdignore` を置いて取り込み対象から外す（親フォルダにほかのファイルがあるときは置かずに警告する）。プロジェクト直下のフォルダには書き出せない。

エディタでは `Project > Tools` の2項目から使う。

| メニュー | 内容 |
|---|---|
| `GameRush: 書き出し設定を確認` | 「GameRush Web」の現在値と推奨値を並べて表示し、「推奨を適用」でプリセットだけを書き換える |
| `GameRush: 推奨設定で書き出す` | 書き出し先を選び、プリセットを推奨値にしてから書き出し、サイズと警告を表示する |

エクスポートダイアログを開いたまま使った場合は、閉じて開き直すと新しいプリセットが見える（エディタはプリセットをメモリに持っている）。書き出し中はエディタが固まったように見える。

コマンドラインからも同じことができる（CI 向け）。

```sh
godot --headless --path . --script res://addons/grush_sdk_build/grush_build_cli.gd -- --output build/gamerush
```

`--no-mobile-textures` でスマホ向けテクスチャ圧縮を外し、`--preset-only` でプリセットだけ書いて書き出しを省く。出力は `[grush-build] ` で始まる行で、変更した設定は `set <key>: <旧> -> <新>` と出る。

| 終了コード | 意味 |
|---|---|
| 0 | 成功（目安の 15MB を超えたときは警告だけ出る。30MB 以上は危険） |
| 1 | 書き出し失敗（多くは書き出しテンプレートの未インストール） |
| 2 | 引数・Godot のバージョン・書き出し先（プロジェクト直下、`addons/`、`.godot/`）が不正 |
| 4 | GameRush のアップロード上限（2000 ファイル / 50MB）を超えた |

## サンプル

`samples/` の `.gd` を、空のシーンのルート `Control` ノードへ付けるだけで動く（シーンファイルは持たない）。

| サンプル | 内容 |
|---|---|
| `samples/score_attack/score_attack.gd` | 疑似IDの取得と表示名の同意要求 |
| `samples/duel/duel.gd` | 2人対戦。エディタではモックの対戦相手が動く |
