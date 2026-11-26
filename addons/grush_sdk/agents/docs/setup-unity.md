# Unity の SDK の導入と API

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#unity

<a id="unity"></a>
## Unity

### 導入

Package Manager の **Add package from git URL...** に `https://github.com/gamerush-jp/grush-sdk-unity.git#v1.23.0` を入れてください。`#` の後ろが版で、新しい版へ上げるときはここを書き換えます。Unity 2021.3 以降、ビルドターゲットは WebGL です。パッケージ識別子は `cc.gamerush.sdk` です（ソースは [grush-sdk-unity](https://github.com/gamerush-jp/grush-sdk-unity)）。

入れると **GameRush** メニューが増え、Unity から出ずにログインしてビルドを上げられます（[Unity Editor からアップロードする](editor-upload.md#editor-upload)）。

AI エージェント（Claude Code・Codex など）向けに、開発者向けの文書と同じ内容の Markdown を SDK に同梱しています。メニューの **GameRush/AI エージェント向けの文書を入れる** で、プロジェクトのフォルダの `.gamerush/` に入り、プロジェクトの `AGENTS.md`（あれば `CLAUDE.md` も）から指されます。Unity `v1.22.0` 以降の SDK で使えます。

### API

```csharp
using GRushSdk;

var self = await GRush.Player.GetSelfAsync();
if (self.Ok) Debug.Log(self.Value.PseudoId);

var joined = await GRush.Net.JoinAsync("duel");
if (!joined.Ok) return;

var room = joined.Value;
room.Message += message =>
{
    if (message.IsStale) return;
    Apply(message.From, message.Payload);
};
room.PeerJoined += peer => Debug.Log(peer.Index);
room.TransportChanged += transport => Debug.Log(transport);
room.Error += error => Debug.LogWarning(error.Code);
room.Closed += reason => Debug.Log(reason);

room.Send(bytes, GRushChannel.Unreliable, GRushRoom.Everyone);
var now = room.ServerTimeMs();
await room.LeaveAsync();
```

```csharp
var arena = await GRush.Net.JoinAsync(new GRushJoinOptions
{
    Mode = "arena",
    MaxPeers = 32,
    Topology = GRushTopology.Hub,
    HostSelection = GRushHostSelection.Auto,
});
// 古い GameRush のアプリでは 8 と Mesh
if (arena.Ok) Debug.Log(arena.Value.MaxPeers + " " + arena.Value.Topology);
```

| 型 | 内容 |
|---|---|
| `GRushResult<T>` | `Ok` / `Value` / `Code`（`GRushErrorCode`）/ `Message` |
| `GRushPlayer` | `PseudoId` / `IsGuest` / `ProfileConsent` / `DisplayName` / `AvatarUrl`（`ProfileConsent` は、GameRush の設定で名前とアイコンの表示がオンのとき `true`。ゲストは常に `false`） |
| `GRushPeer` | `Index` / `PseudoId` / `DisplayName` / `AvatarUrl`（表示名とアイコンは、その相手が GameRush の設定で表示をオフにしていないときだけ入る。設定オフとゲストでは `null`） |
| `GRushMessage` | `From` / `Channel` / `Seq` / `Payload` / `IsStale` |
| `GRushRoom` | `LocalPeerId` / `HostPeerId` / `IsHost` / `Peers` / `MaxPeers` / `Topology` / `Stats.Transport` / `RoomCode` / `RoomEpoch` |
| `GRushJoinOptions` | `Mode` / `RoomCode` / `TargetRoomSize` / `MaxPeers`（1〜100。0 は未指定で 8）/ `Topology`（`GRushTopology.Mesh`・`Hub`。`null` は未指定で `Mesh`）/ `HostSelection`（`GRushHostSelection.Auto` で GameRush がホストを選ぶ）。`GRush.Net.JoinAsync(options)` に渡す |

`MaxPeers`・`Topology`・`HostSelection` のどれかを渡すと、`GRush.RoomConfigProtocolVersion`（11）が要り、`GRush.IsRoomConfigAvailable` が `false` の GameRush では部屋へ入らずに `Unsupported` が返ります。`hub` の部屋で送れる宛先と送信の上限は [リアルタイムマルチプレイ](multiplayer.md#multiplayer) にあります。

JS からのコールバックは次の `Update` で発火します。イベントハンドラの中は Unity のメインスレッドなので、そのまま Unity の API を触って構いません。

WebGL の SDK は、C# の文字列を UTF-8 にして GameRush へ渡します。対になっていないサロゲート（UTF-16 の文字列を文字の途中で切った切れ端）は UTF-8 で表せないので、文字列にそのまま入った切れ端は U+FFFD 1つに替えて送ります（エディタのモックも同じです）。そのため、切れ端だけが違う payload や `metadataJson` のキーは同じキーになり、切れ端だけが違う `operationId` は同じ値になって、同じ投稿の再送として扱われます。payload や `metadataJson` の生の JSON に JSON のエスケープ（`\ud83d` など）で書いた切れ端はそのまま届き、GameRush が `InvalidParams` で断ります。分析のイベントの文字列は、切れ端をエスケープで書いて送るので、GameRush がそのイベントを拒みます。
