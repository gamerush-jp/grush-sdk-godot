# 受信箱

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#inbox

<a id="inbox"></a>
## 受信箱

同じゲームのプレイヤーの疑似ID宛てに、小さい構造化メッセージを送れます。非同期対戦の結果の通知などに使います。ゲストも送受信できます。

**payload で文章や画像は送れません。プレイヤーどうしの文章や画像のやりとりには使わないでください。**

| payload の形 | 上限 |
|---|---|
| JSON のオブジェクト（Unity は JSON の文字列、Godot は辞書、JavaScript はオブジェクト） | 詰めた JSON で 1KB |
| 文字列の値とキーは英数字と `_` `.` `:` `-` だけ（空白・日本語・ほかの記号は不可） | 32 文字 |
| ほかは数値・真偽値・null と、それらの配列とオブジェクト | 値は合計 64 個 |
| 入れ子 | 最上位を 1 段目として 4 段 |

識別子（アイテムの ID・ステージの番号・スコアなど）は運べても、文章は運べない形です。合わない payload は `InvalidParams` になります。`kind` も英数字と `_` `.` `:` `-` の 32 文字までです。

```csharp
// Unity
await GRush.Inbox.SendAsync(rivalPseudoId, "battleResult", "{\"stage\":3,\"win\":true}");
var inbox = await GRush.Inbox.ListAsync(true);
if (inbox.Ok)
{
    foreach (var message in inbox.Value.Messages)
    {
        var result = JsonUtility.FromJson<BattleResult>(message.PayloadJson);
    }
}
```

```gdscript
# Godot
await GRush.inbox.send(rival_pseudo_id, "battleResult", {"stage": 3, "win": true})
var inbox: Dictionary = await GRush.inbox.list({"unread_only": true})
if inbox["ok"]:
    for message in inbox["value"]["messages"]:
        print(message["from"], message["kind"], message["payload"])
```

```javascript
// JavaScript
await GRush.inbox.send(rivalPseudoId, "battleResult", { stage: 3, win: true });
const inbox = await GRush.inbox.list({ unreadOnly: true });
if (inbox.ok) {
  const messages = inbox.value.messages;
  for (const message of messages) console.log(message.from, message.kind, message.payload);
  if (messages.length) await GRush.inbox.markRead(messages.map((message) => message.id));
}
```

| 呼び出し | Unity | Godot | JavaScript |
|---|---|---|---|
| 送る | `Inbox.SendAsync(to, kind, json)` | `inbox.send(to, kind, payload)` | `inbox.send(to, kind, payload)` |
| 一覧 | `Inbox.ListAsync(unreadOnly, limit, cursor)` | `inbox.list({ unread_only, limit, cursor })` | `inbox.list({ unreadOnly, limit, cursor })` |
| 既読にする | `Inbox.MarkReadAsync(ids)` | `inbox.mark_read(ids)` | `inbox.markRead(ids)` |
| 消す | `Inbox.RemoveAsync(ids)` | `inbox.remove(ids)` | `inbox.remove(ids)` |
| 通報する | `Inbox.ReportAsync(messageId)` | `inbox.report(message_id)` | `inbox.report(messageId)` |

- 一覧は新しい順で、1 回 1〜50 件（省略すると 20 件）です。続きは、返った次のカーソルを渡して読みます。未読の数は絞り込みによらず返ります。
- メッセージには、送り手の疑似ID・`kind`・payload・届いた日時・既読にした日時（未読なら null）が入ります。Unity の payload は JSON の文字列（`PayloadJson`）で、`JsonUtility.FromJson` などでゲームの型に読めます。
- 既読と削除は 1 回 1〜50 件で、更新した件数が返ります。空の一覧を渡すと `InvalidParams` なので、件数を確かめてから呼んでください。
- 自分宛てには送れません。同じゲームの疑似IDでない宛先は `InvalidParams` です。
- 送りすぎ（1 人毎時 60 件・毎日 300 件、同じ宛先へは毎時 10 件まで）は `RateLimited` で、時間が経てば回復します。待つ時間が分かるときは、JavaScript の結果に待ち時間 `retryAfterMs` が入ります。
- メッセージは届いてから 30 日で消えます。宛先ごとに 100 件、同じ送り手からは 20 件まで持ち、超えると古いものから消えます。このときも送信は成功します。
- 受信箱は `protocolVersion` 7 以上の GameRush で使えます。それより古い GameRush では、どの呼び出しも `Unsupported` です。Unity は `GRush.IsInboxAvailable` で確かめられます。

### 通報

ゲームは通報の画面を描けません。通報を呼ぶと GameRush が確認を出し、プレイヤーが承諾したときだけ送られます。返るのは「送られたか」の真偽値です。ゲストは `SignInRequired` です。

通報すると送り手をブロックします。その相手からのメッセージと、その相手の出品は見えなくなります。確認には、GameRush が取り直したメッセージの中身と、送り手の疑似IDの先頭 8 文字と受け取った日時が出ます。
