# リアルタイムマルチプレイ

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#multiplayer

<a id="multiplayer"></a>
## リアルタイムマルチプレイ

- 直結できる相手とは WebRTC でつなぎ、直結できない相手とは GameRush の中継（WebSocket）を通します。どちらになるかは相手ごとに決まり、部屋にいる間にも切り替わります。
- `channel` と宛先は必須の概念です。WebRTC でつないだ相手への `unreliable` は、落ちることも、並びが替わることもあります。中継を通る相手には落ちずに順序どおりに届きますが、どちらを通るかはゲームから選べません。落ちて並び替わる前提で書いてください。
- `transport` は、部屋の全員と直結しているときだけ `webrtc` で、それ以外は `ws` です。切り替わると `transportchange`（Unity は `TransportChanged`、Godot は `transport_changed`）が届きます。通知なので、受けなくても壊れません。
- **メッセージは 8KB 上限です。WebRTC のデータチャネルの実用上限に合わせた値です。**
- 部屋に入れるのは、定員を選ばなければ 8 人までです。`join` は、同じ `mode` と定員と形の、空きのある部屋を古い順に選び、無ければ新しい部屋を作ります。人数が揃うのは待ちません。
- 部屋の定員と形は `join` で選べます。JavaScript は `GRush.net.join({ mode: "arena", maxPeers: 12, topology: "hub" })`、Unity は `GRush.Net.JoinAsync(new GRushJoinOptions { Mode = "arena", MaxPeers = 12, Topology = GRushTopology.Hub })`、Godot は `GRush.net.join_with({"mode": "arena", "max_peers": 12, "topology": "hub"})` です。定員 `maxPeers` は 1〜100 の整数で、省略すると 8 です（Unity の 0 は未指定）。形 `topology` は、全員が全員へ送る `mesh`（定員 16 まで）と、ホストへ集める `hub` で、省略すると `mesh` です。入った部屋の定員と形は、JavaScript は `room.maxPeers`・`room.topology`、Unity は `MaxPeers`・`Topology`、Godot は `max_peers`・`topology` で読めます。
- ホストの選び方も `join` で選べます。JavaScript は `hostSelection: "auto"`、Unity は `HostSelection = GRushHostSelection.Auto`、Godot は `"host_selection": "auto"` を渡すと、GameRush が端末の性能と部屋までの遅延からホストを選びます。選ぶための点数が届くのは入室から 2 秒ほどの間で、その間にホストが替わることがあるので、対戦を始める前に `host` を受け止めてください。`hub` の部屋は、渡さなくてもこの選び方をします。渡さない `mesh` の部屋では、最初に入った参加者がホストになります。どの部屋でも、ホストが抜けたときなどにホストは替わり、`host`（Unity は `HostChanged`、Godot は `host_changed`）が届きます。
- 定員・形・ホストの選び方のどれかを渡した `join` は、`protocolVersion` 11 未満の GameRush では部屋へ入らずに `Unsupported` を返します。Unity は `GRush.IsRoomConfigAvailable` で前もって確かめられます。
- 定員と形を知らない古い版のアプリでは、定員と形が無視され、既定の部屋（8 人の `mesh`）へ入ります。定員を無視した `join` は目安の人数を既定の定員 8 で確かめるので、目安に 9 以上を渡すと `InvalidParams` で失敗します。目安が 8 以下なら失敗しないので、入った部屋の実際の定員と形は、`join` の結果の部屋で確かめてください。`protocolVersion` 11 未満の GameRush と、定員と形を伝えない部屋では、8 と `mesh` です。`roomCode` で指定した部屋が違う定員か形で既にあるときは、`InvalidParams` で失敗します（部屋は `roomMismatch` で断ります）。
- 定員・形・ホストの選び方を渡せるのは、Unity `v1.16.0`・Godot `v1.13.0`・JavaScript `v0.15.0` 以降の SDK です。
- 直結（WebRTC）を使うのは、定員 8 人以下の `mesh` の部屋だけです。定員 9 人以上の部屋と `hub` の部屋は、人数によらず GameRush の中継を通り、`transport` はいつも `ws` です。
- `hub` の部屋では、ホスト以外が送れるのはホスト宛てと全員宛て（ホストにだけ届きます）だけです。ほかの宛先へは送られず、`error`（`code` は `targetNotAllowed`）が届きます。ホストには、ほかの参加者の送信が 50ms ごとにまとめて届き、送り手ごとの順は保たれます。ホストは結果を全員へ配ってください。
- `hub` のホストは、ほかの参加者の送信を受けている間、少なくとも 2 秒ごとに送ってください。ホストから 2 秒届かないと、部屋はホストが止まったとみなして、別の参加者をホストにします。ホストは、タブを隠したり、別のゲームへ移ったりしても替わります。ホストになってから 30 秒を過ぎると、端末の性能と遅延から作った点数がホストより十分高い参加者へ替わることもあります。替わると `host` が届くので、新しいホストは、全員が持っている最新の状態（前のホストが最後に配った状態）から続けてください。そのためにホストは、続けるのに要る状態を全員へ配っておきます。
- `mode` は英数字と `.` `_` `:` `-` の 1〜32 文字で、省略すると `default` です。`roomCode` を渡すと、同じ `mode` の中のその部屋へ入ります。同じ `roomCode` でも `mode` が違えば別の部屋です。`roomCode` は英数字の 4〜12 文字で、大文字と小文字を区別しません。
- `join` には部屋の目安の人数を渡せます。JavaScript は `GRush.net.join({ mode: "world", targetRoomSize: 4 })`、Unity は `GRush.Net.JoinAsync("world", 4)`、Godot は `GRush.net.join("world", "", 4)` です。目安は 1〜定員の整数で、Unity と、Godot の `join` の 0 は未指定です。
- 目安を渡すと、同じ `mode` と定員と形の部屋を新しいものから 8 部屋まで見て、目安に届いていない部屋のうち最も人数の少ない部屋へ入ります。人のいる部屋があれば、無人の部屋より先に選びます。見た部屋がどれも目安以上なら新しい部屋ができます。部屋の数が上限に達して新しい部屋を作れないときは、見た部屋のうち定員に満たない最も人数の少ない部屋へ入ります。見た部屋がどれも定員まで埋まっていれば、その先の部屋を新しいものから 8 部屋ずつ見て、空きのある部屋へ入ります。人数に入るのは部屋への接続を済ませた人だけなので、`join` が同時に重なると目安を超えて定員まで入ることがあります。部屋にいる人を別の部屋へ移すことはないので、人が抜けると部屋ごとの人数はばらつきます。`roomCode` で部屋を指定したときは、目安を使わずにその部屋へ入ります。
- 目安を渡せるのは Unity `v1.13.0`・Godot `v1.11.0`・JavaScript `v0.13.0` 以降の SDK です。目安を知らない古い GameRush では目安が無視され、渡さないときと同じ選び方で部屋へ入ります。無視されたことはゲームからは分かりません。
- 送信は、定員 8 人以下の `mesh` の部屋では毎秒 30 通、続けてなら 60 通までです。定員 9 人以上の `mesh` の部屋と、`hub` の部屋のホスト以外は毎秒 20 通、続けてなら 40 通までです。`hub` のホストは毎秒 20 + 5 ×（人数 − 1）通（200 通まで）、続けてならその2倍までです。全員宛ての1通も 1 通と数えます。超えた分は捨てられ、捨てられたことが届かないこともあるので、送る数はゲームの側で抑えてください。
- 部屋は作られてから 30 分で閉じ、`close`（`reason` は `roomExpired`）が届きます。続けるときは `join` し直してください。
- `join` は 1 人毎分 10 回まで、同じ IP アドレスからは毎分 60 回までです。超えると `RateLimited` です。
- `join` が部屋を取れずに失敗すると、`mode`・`roomCode`・目安の人数・定員・形が上の規則に合わないときと、`roomCode` で指定した部屋が違う定員か形で既にあるときは `InvalidParams` です。入ろうとした部屋が定員で埋まっているときや、作られてから 30 分を過ぎているとき（`roomCode` で指定した部屋のほか、`join` が選んだ部屋が入るまでの間にそうなったときも）、部屋の数が上限に達して新しい部屋を作れないとき、GameRush の側で一時的に使えないとき・マルチプレイを止めている間は `Unavailable` です。`InvalidParams` は引数を直すまで通らず、`Unavailable` は時間を置いて `join` し直すと通ることがあります。30 分を過ぎた部屋の `roomCode` は、前の部屋の全員が抜けると、同じ `roomCode` でまた入れます。`Unavailable` で待つ時間が分かるときは、JavaScript の結果に待ち時間 `retryAfterMs`（ミリ秒）が入ります。満員の部屋と 30 分を過ぎた部屋では、待つ時間は入りません。
- join は置き換えです。部屋にいる状態で `join` を呼ぶと、先に現在の部屋が閉じて `close`（`reason` は `replaced`）が届き、それから新しい部屋を取りに行きます。`join` が失敗しても元の部屋には戻らないので、続けたいときは `close` を受けてから `join` し直してください。
- 部屋が1通を捨てると `error`（`code` は `messageTooLarge`・`rateLimited`・`badFrame`・`targetNotAllowed`）が届きます。部屋はつながったままで、続けて送れます。部屋が閉じるときは `close` だけが届きます。`code` は増えることがあります。
- 同じプレイヤーが別のタブや端末から同じ部屋へ入ると、新しい接続が残り、前の接続には `close`（`reason` は `joinedElsewhere`）が届きます。このときは自動で `join` し直さないでください。し直すと2つのタブが互いを追い出し合い、`join` の回数制限に当たるまで続きます。

部屋に入った後、相互フォローの相手をその部屋へ招けます。招かれた人が通知を開くと、そのゲームの [起動パラメータ](launch-params.md#launch) に部屋が入るので、ゲームはその部屋へ `join` します。

```csharp
// Unity
var invited = await GRush.Net.InviteAsync();
if (invited.Ok && invited.Value.Status == GRushInviteStatus.Sent)
{
    ShowToast(invited.Value.Count + " 人を招待しました");
}
```

```gdscript
# Godot
var invited: Dictionary = await GRush.net.invite()
if invited["ok"] and invited["value"]["status"] == "sent":
    show_toast("%d 人を招待しました" % invited["value"]["count"])
```

```javascript
// JavaScript
const invited = await GRush.net.invite();
if (invited.ok && invited.value.status === "sent") showToast(`${invited.value.count} 人を招待しました`);
```

- 招待は引数を取りません。GameRush が相互フォローの相手を選ぶシートを出し、今入っている部屋へ招きます。ゲームは部屋も相手も選べず、受け取るのは結果の `status` と送った人数 `count` だけです（Unity は `Status`・`Count`）。
- `status` は、1人以上へ送ったら `sent`、送らずに閉じたら `cancelled`（`count` は 0）です（Unity は `GRushInviteStatus.Sent`・`Cancelled`）。選べるのは、部屋の空いた席の数と 30 人の小さいほうまでです。
- シートを出している間もゲームは止まらず、部屋の相手との対戦は続きます。結果はシートを閉じたときに返ります。
- シートを出せないときは、出さずにすぐ `cancelled` が返ります。ゲームのスライドが前面にないとき、プレイヤーが別の画面（閲覧など）を見ているとき、送らずに閉じたスライドで閉じてから 60 秒の間です。
- 部屋に入っていなければ `Unavailable`、ゲストなら `SignInRequired`、5 秒に 1 回より多く呼ぶと `RateLimited` です（[呼び出しの回数の上限](sdk-basics.md#rate-limits)）。シートを出せない面（埋め込みなど）と、`protocolVersion` 13 未満の GameRush では `Unsupported` です。Unity は `GRush.IsInviteAvailable` で前もって確かめられます。
- GameRush が招待を送れなかったときは、シートの中に理由が出ます。GameRush のサーバの上限（送り手ごとに 1 時間 30 件・1 日 100 件、同じ相手へ 1 時間 5 件）を超えたとき、空いた席が足りないとき、部屋を出たときなどです。ゲームへエラーは返らず、プレイヤーがシートを閉じると `cancelled` が返ります。
- 招待は作ってから 15 分か、部屋が閉じるまでの早いほうで期限が切れます。招待から開いたスライドで、招待の `mode` と部屋コードのまま `join` すると、招待の部屋にだけ入ります（[起動パラメータ](launch-params.md#launch)）。招いた人が部屋を出た・満員・期限が切れたときは、新しい部屋を作らずに `Unavailable` になります。
- 招待を使えるのは、Unity `v1.18.0`・Godot `v1.15.0`・JavaScript `v0.17.0` 以降の SDK です。
