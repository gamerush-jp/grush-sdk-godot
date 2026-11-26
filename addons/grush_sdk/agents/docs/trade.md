# 交換所

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#trade

<a id="trade"></a>
## 交換所

プレイヤーがゲームのアイテムを出品し、同じゲームの別のプレイヤーが受けて交換できます。出品も受諾もゲストができます。

**GameRush はアイテムの正当性を確かめません。出品の中身はゲームの申告のままです。保証するのは、交換が片方だけ成立しないことと、終わった取引を取りこぼさないことだけです。課金アイテムには使わないでください。**

出すもの（offer）・欲しいもの（want）・受ける側が渡すもの（give）は、[受信箱](inbox.md#inbox) の payload と同じ形で、文章や画像は送れません。大きさは詰めた JSON で offer 2KB・want 1KB・give 2KB までです。プレイヤーどうしの文章や画像のやりとりには使わないでください。

```csharp
// Unity
// 出品: 出すアイテムをセーブで仮置きにし、operationId と一緒に保存してから呼ぶ。
var created = await GRush.Trade.CreateAsync(
    "{\"item\":\"sword\",\"count\":1}",
    "{\"item\":\"gem\",\"count\":3}",
    save.EscrowOperationId,
    new GRushTradeOptions { OfferKey = "sword", WantKey = "gem" }
);

// 受ける
var accepted = await GRush.Trade.AcceptAsync(tradeId, "{\"item\":\"gem\",\"count\":3}");
if (accepted.Ok && accepted.Value.Outcome == GRushTradeOutcome.Taken) ShowTaken();

// 受け取り: セーブに反映し、セーブを保存してから Ack する
var mine = await GRush.Trade.MineAsync();
if (mine.Ok)
{
    var done = new List<string>();
    foreach (var pending in mine.Value.Pending)
    {
        if (pending.Action == GRushTradeAction.Unknown) continue;
        if (!save.AppliedTrades.Contains(pending.Trade.Id))
        {
            ApplyTrade(save, pending);
            save.AppliedTrades.Add(pending.Trade.Id);
        }
        done.Add(pending.Trade.Id);
    }
    if (done.Count > 0 && SaveGame(save))
    {
        // ack に渡せるのは 1 回 50 件まで。
        for (var i = 0; i < done.Count; i += 50)
            await GRush.Trade.AckAsync(done.GetRange(i, Math.Min(50, done.Count - i)).ToArray());
    }
}
```

```gdscript
# Godot
var created: Dictionary = await GRush.trade.create(
    {"item": "sword", "count": 1}, {"item": "gem", "count": 3}, save["escrow_operation_id"],
    {"offer_key": "sword", "want_key": "gem"}
)
var accepted: Dictionary = await GRush.trade.accept(trade_id, {"item": "gem", "count": 3})

const KNOWN_ACTIONS := ["receiveGive", "returnOffer", "receiveOffer"]
var mine: Dictionary = await GRush.trade.mine()
if mine["ok"]:
    var done: Array = []
    for trade in mine["value"]["pending"]:
        if not KNOWN_ACTIONS.has(trade["action"]):
            continue
        if not save["applied_trades"].has(trade["id"]):
            apply_trade(save, trade)
            save["applied_trades"].append(trade["id"])
        done.append(trade["id"])
    if not done.is_empty() and save_game(save):
        # ack に渡せるのは 1 回 50 件まで。
        for i in range(0, done.size(), 50):
            await GRush.trade.ack(done.slice(i, i + 50))
```

```javascript
// JavaScript
const created = await GRush.trade.create({
  offer: { item: "sword", count: 1 },
  want: { item: "gem", count: 3 },
  offerKey: "sword",
  wantKey: "gem",
  operationId: save.escrow.operationId,
});

const accepted = await GRush.trade.accept(tradeId, { item: "gem", count: 3 });
if (accepted.ok && accepted.value.outcome === "taken") showTaken();

const KNOWN_ACTIONS = ["receiveGive", "returnOffer", "receiveOffer"];
const mine = await GRush.trade.mine();
if (mine.ok) {
  const done = mine.value.pending.filter((trade) => KNOWN_ACTIONS.includes(trade.action));
  for (const trade of done) {
    if (save.appliedTrades.includes(trade.id)) continue;
    applyTrade(save, trade);
    save.appliedTrades.push(trade.id);
  }
  const saved = await GRush.cloudSave.save(save);
  if (saved.ok) {
    // ack に渡せるのは 1 回 50 件まで。
    for (let i = 0; i < done.length; i += 50) {
      await GRush.trade.ack(done.slice(i, i + 50).map((trade) => trade.id));
    }
  }
}
```

| 呼び出し | Unity | Godot | JavaScript |
|---|---|---|---|
| 出品する | `Trade.CreateAsync(offer, want, operationId, options)` | `trade.create(offer, want, operation_id, options)` | `trade.create({ offer, want, operationId, … })` |
| 受付中の出品の一覧 | `Trade.ListAsync(offerKey, wantKey, limit, cursor)` | `trade.list({ offer_key, want_key, limit, cursor })` | `trade.list({ offerKey, wantKey, limit, cursor })` |
| 自分の出品と、終わった取引 | `Trade.MineAsync()` | `trade.mine()` | `trade.mine()` |
| 受ける | `Trade.AcceptAsync(tradeId, give)` | `trade.accept(trade_id, give)` | `trade.accept(tradeId, give)` |
| 取り下げる | `Trade.CancelAsync(tradeId)` | `trade.cancel(trade_id)` | `trade.cancel(tradeId)` |
| 受け取りを確かめる | `Trade.AckAsync(ids)` | `trade.ack(ids)` | `trade.ack(ids)` |
| 通報する | `Trade.ReportAsync(tradeId)` | `trade.report(trade_id)` | `trade.report(tradeId)` |

交換所は `protocolVersion` 7 以上の GameRush で使えます。それより古い GameRush では、どの呼び出しも `Unsupported` です。Unity は `GRush.IsTradeAvailable` で確かめられます。

### 取りこぼさない使い方

**通信が途中で切れても、アイテムが消えたり増えたりしないよう、次の順で使ってください。**

- 1. 出品の前に、出すアイテムを手元のセーブで仮置き（使えない状態）にします。
- 2. 出品の識別子 `operationId`（英数字と `.` `_` `:` `-` の 64 文字まで）をセーブに保存してから出品します。
- 3. 応答が失われたら、同じ `operationId` で出品を呼び直します。同じ `operationId` の再送には、中身によらず先に作った出品が返ります。
- 4. 自分の取引（Unity は `MineAsync`、Godot と JavaScript は `mine`）の、終わった取引（pending）をセーブに反映し、セーブを永続化してから、その取引 ID で受け取りを確かめます（ack）。永続化には、JavaScript は `GRush.cloudSave`、Unity と Godot はゲーム側の保存を使います。ack するまで、終わった取引は pending に残ります。ただし、終わってから 90 日を過ぎた取引は、ack していなくても消えます。
- 5. 反映済みの取引 ID をセーブに持ち、同じ取引を二度反映しないようにします。

| pending の action | 誰が | セーブへの反映 |
|---|---|---|
| `receiveGive` | 出品者 | 成立した。受けた側の give を足し、仮置きの offer を消す |
| `returnOffer` | 出品者 | 取り下げ・期限切れ・運営の非表示で終わった。仮置きの offer を手元へ戻す |
| `receiveOffer` | 受けた側 | 成立した。offer を足す |

知らない action は反映せず、ack もしないでください。1 回の呼び出しで返る pending は、終わった順に 100 件までです。それより多いときは、ack してから呼び直すと続きが返ります。ack に渡せる id は 1 回 1〜50 件で、超えると `InvalidParams` になり、1件も ack されません。多いときは 50 件ずつに分けて呼んでください。ゲストのときに出品・受諾した取引の pending は、同じゲストとして開いたときに返り、サインインしている間は返りません。

### 出品と受諾

- 出品は、誰でも受けられる公開の出品と、相手の疑似IDを指定する指名の出品の2種類です。
- `offerKey` / `wantKey` は一覧の絞り込みに使う識別子（英数字と `.` `_` `:` `-` の 32 文字まで）で、省略できます。
- 指名の出品の相手と期限は、Unity は `GRushTradeOptions` の `To` / `ExpiresInSec`、Godot は options の `to` / `expires_in_sec`、JavaScript は `to` / `expiresInSec` で渡します。
- 期限は 600〜604800 秒（10 分〜7 日）で、省略すると 3 日です。受付中の出品は 1 人 10 件までです。
- 受付中の出品が 10 件あるときの出品は `InvalidParams` です。待っても直らないので、取り下げるか、成立・期限切れを待ってから出品してください。
- 出品は 1 人毎日 30 件、成立させた受諾は毎時 30 件までで、超えると `RateLimited` です。時間が経てば回復します。待つ時間が分かるときは、JavaScript の結果に待ち時間 `retryAfterMs` が入ります。
- 一覧に出るのは、他人の公開の出品と自分宛ての指名の出品のうち、受付中のもの（新しい順、1 回 1〜50 件）です。
- give は当事者（出品者と受けた側）にだけ入り、ほかの人には null です。

| 受諾の結果（outcome） | 意味 |
|---|---|
| `matched` | 成立した。同じ取引への再送も matched |
| `taken` | 先に別のプレイヤーが受けた |
| `expired` | 期限が切れていた |
| `cancelled` | 出品者が取り下げた |
| `notFound` | 見えない出品（伏せられた・自分の・自分宛てでない指名の・ブロック関係にある相手の） |

受諾の結果はエラーではなく outcome で返ります。成立した取引は matched のときだけ一緒に返ります。2人が同時に受けても、成立するのは片方だけです。

### 通報

ゲームは通報の画面を描けません。通報を呼ぶと GameRush が確認を出し、プレイヤーが承諾したときだけ送られます。返るのは「送られたか」の真偽値です。ゲストは `SignInRequired` です。通報すると出品者をブロックし、その相手のメッセージと出品は見えなくなります。

確認には、GameRush が取り直した出品の中身と、出品者の疑似IDの先頭 8 文字と出品の日時が出ます。プレイヤーは画面の出品と見比べて通報します。自分の出品は通報できず、確認を出さずに `InvalidParams` です。
