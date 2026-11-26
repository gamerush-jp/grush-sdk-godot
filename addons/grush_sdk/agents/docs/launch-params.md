# 起動パラメータ

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#launch

<a id="launch"></a>
## 起動パラメータ

ゲームのページの URL に `gp.` を付けて載せたキーと値を、ゲームから読めます。シェアしたリンクから特定のアイテムやダンジョンへ直接飛ばすのに使います。`https://gamerush.jp/g/<ゲームのコード>?gp.item=sword&gp.dungeon=3` なら、ゲームには `item` が `sword`、`dungeon` が `3` として渡ります。

ゲームから共有するときに起動パラメータを添えると、GameRush がこの形の URL を作ります（[ゲームからの共有](share.md#share) の「起動パラメータを添える」）。

```csharp
// Unity
var launch = await GRush.Launch.GetAsync();
if (launch.Ok && launch.Value.TryGet("item", out var item) && Inventory.Owns(item))
{
    OpenItem(item);
}
```

```gdscript
# Godot
var launch: Dictionary = await GRush.launch.fetch()
if launch["ok"]:
    var item: String = launch["value"]["params"].get("item", "")
    if item != "" and inventory.owns(item):
        open_item(item)
```

```javascript
// JavaScript
const launch = await GRush.launch.get();
const item = launch.ok ? launch.value.params.item : undefined;
if (item && inventory.owns(item)) openItem(item);
```

**値を信用しないでください。リンクは誰でも作れます。アイテムが存在するか・プレイヤーが持っているか・ダンジョンが解放済みかをゲームの側で確かめ、確かめられなければ無視してください。**

| URL の書き方 | 制限 |
|---|---|
| `gp.<キー>=<値>` | ゲームに渡るキーは `gp.` を除いた部分です |
| キー | 英数字と `_` `-` で 1〜32 文字（`__proto__` は使えません） |
| 値 | 英数字と `.` `_` `~` `:` `,` `-` で 0〜128 文字（空の値も渡ります） |
| 個数 | 8 個まで |

形の合わない項目は GameRush が1つずつ落とし、残りだけを渡します。同じキーを2回書いたときは、そのキーを落とします。有効な項目が 8 個を超えたときは全部を落とします。

| 呼び出し | Unity | Godot | JavaScript |
|---|---|---|---|
| 届くまで待って取る | `Launch.GetAsync()` | `launch.fetch()` | `launch.get()` |
| 届いていれば同期で返す（まだなら null） | `Launch.Current` | `launch.current()` | `launch.current()` |
| 1つのキーを読む | `Current.TryGet("item", out var item)` | `params.get("item", "")` | `params.item` |

起動パラメータが渡るのは、プレイヤーがそのリンクで最初に開いたスライドのゲームだけです。別のゲームへスワイプしてから戻ってきたときは、パラメータは空になります。フィードでページを読み直したときも空になります。単体表示や埋め込みでは、ページを読み直すと同じパラメータがまた渡ることがあるので、何度渡っても困らないように書いてください。パラメータの無い起動でも取得は失敗せず、空のパラメータが返ります。

[フレンドの招待](multiplayer.md#multiplayer) の通知から開いたときは、起動パラメータに招待の部屋 `invite`（`mode` と部屋コード）が入ります。ほかの起動では `invite` は null です。そのまま `join` に渡すと、招いた人の部屋へ入ります。招待の部屋への `join` は渡した定員と形を見ず、部屋の定員と形で入ります。招いた人が部屋を出た・満員・招待の期限が切れたときは、新しい部屋を作らずに `Unavailable` になります。招待で一度部屋に入った後の `join`（部屋が閉じた後や切断の後の入り直し）は招待の `join` にならず、部屋コードを渡した普通の `join` になります。別のゲームへスワイプしてから戻った後の `join` も同じです。

```csharp
// Unity
var launch = await GRush.Launch.GetAsync();
if (launch.Ok && launch.Value.Invite != null)
{
    var joined = await GRush.Net.JoinAsync(launch.Value.Invite.Mode, launch.Value.Invite.RoomCode);
}
```

```gdscript
# Godot
var launch: Dictionary = await GRush.launch.fetch()
if launch["ok"] and launch["value"]["invite"] != null:
    var invite: Dictionary = launch["value"]["invite"]
    var joined: Dictionary = await GRush.net.join(invite["mode"], invite["room_code"])
```

```javascript
// JavaScript
const launch = await GRush.launch.get();
if (launch.ok && launch.value.invite) {
  const joined = await GRush.net.join(launch.value.invite);
}
```

部屋は Unity は `Invite.Mode`・`Invite.RoomCode`、Godot は `invite["mode"]`・`invite["room_code"]`、JavaScript は `invite.mode`・`invite.roomCode` で読めます。招待の部屋が入るのは、`protocolVersion` 13 以上の GameRush で、Unity `v1.18.0`・Godot `v1.15.0`・JavaScript `v0.17.0` 以降の SDK です。それより前では、招待から開いても `invite` は null です。

GameRush の外と、ゲームに読み込まれる GameRush のスクリプトが起動パラメータに対応する前の古いもの（`protocolVersion` 8 未満）だったときは `Unsupported` が返り、同期の取得は null です。スクリプトは新しくても GameRush のアプリ側が古くて答えられないときは、`Unsupported` ではなく空のパラメータが返ります。Godot だけ `get` ではなく `fetch` なのは、`Object.get` と名前がぶつかるためです。
