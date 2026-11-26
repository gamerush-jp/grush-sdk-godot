# Godot 4 の SDK の導入と API

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#godot

<a id="godot"></a>
## Godot 4

### 導入

[grush-sdk-godot のリリース](https://github.com/gamerush-jp/grush-sdk-godot/releases/tag/v1.19.0)（`v1.19.0`）を取得し、`addons/grush_sdk/` をプロジェクトの `addons/` へコピーし、**Project Settings > Plugins** で有効にしてください。autoload シングルトン `GRush` が自動登録されます。書き出しは Web です。

AI エージェント（Claude Code・Codex など）向けに、開発者向けの文書と同じ内容の Markdown を SDK に同梱しています。メニューの **Project > Tools > GameRush: AI エージェント向けの文書を入れる** で、プロジェクトの根の `.gamerush/` に入り、プロジェクトの `AGENTS.md`（あれば `CLAUDE.md` も）から指されます。Godot `v1.19.0` 以降の SDK で使えます。

### API

```gdscript
var self_result: Dictionary = await GRush.player.get_self()
if self_result["ok"]:
    print(self_result["value"]["pseudo_id"])

var joined: Dictionary = await GRush.net.join("duel")
if not joined["ok"]:
    return

var room: GRushRoom = joined["value"]
room.message_received.connect(func(message: Dictionary) -> void:
    if message["is_stale"]:
        return
    apply(message["from"], message["payload"]))
room.peer_joined.connect(func(peer: Dictionary) -> void: print(peer["index"]))
room.transport_changed.connect(func(transport: String) -> void: print(transport))
room.error_received.connect(func(error: Dictionary) -> void: push_warning(error["code"]))
room.closed.connect(func(reason: String) -> void: print(reason))

room.send(bytes, GRush.CHANNEL_UNRELIABLE, GRush.EVERYONE)
var now := room.server_time_ms()
await room.leave()
```

結果はすべて `{"ok": bool, "value": Variant, "code": String, "message": String}` の形で返ります。Unity 版と同じ形を GDScript の慣習（snake_case・`Dictionary`・`signal`）に置いたものです。

```gdscript
var arena: Dictionary = await GRush.net.join_with(
    {"mode": "arena", "max_peers": 32, "topology": "hub", "host_selection": "auto"}
)
if arena["ok"]:
    var arena_room: GRushRoom = arena["value"]
    print(arena_room.max_peers, arena_room.topology) # 古い GameRush のアプリでは 8 と "mesh"
```

部屋の定員と形とホストの選び方を選ぶときは、`GRush.net.join` の代わりに `GRush.net.join_with` に辞書を渡します。キーは `mode`・`room_code`・`target_room_size` と、定員 `max_peers`（1〜100、省略すると 8）、形 `topology`（`"mesh"` か `"hub"`、省略すると `"mesh"`）、ホストの選び方 `host_selection`（`"auto"`）で、どれも省略できます。`join` と違い、`join_with` は `0` や空文字もそのまま値として送り、`"invalidParams"` になるので、使わないキーは辞書に入れないでください。`max_peers`・`topology`・`host_selection` のどれかを渡すと、`protocol_version` 11 未満の GameRush では `"unsupported"` が返ります。入った部屋の定員と形は `GRushRoom` の `max_peers` と `topology` で読めます。`hub` の部屋で送れる宛先と送信の上限は [リアルタイムマルチプレイ](multiplayer.md#multiplayer) にあります。

Godot の SDK は、公開プレイヤー状態の `payload` やランキングの `metadata` などの辞書と配列を、Godot の `JSON.stringify` で JSON にして GameRush へ渡し、応答を JSON として読み戻します。書き出して読み戻せる入れ子は、公開プレイヤー状態の `payload` では、文字列や数などの値を中に持つ配列と辞書で 1022 段まで、空の配列と辞書で 1023 段までです。ランキングの `metadata` などほかの値では、それぞれ 1021 段まで、1022 段までです。これより深い値と、一番外の値も含めて値が 50 万個を超える値は、送らずに `code` を `"invalidParams"` にして返します。GameRush が受け付ける入れ子（3000 段まで）より低い上限です。モック（エディタ、Web 以外の書き出し、手元のサーバや `file://` で開いた Web の書き出しで使われます。[エディタでの動作確認](testing.md#testing)）も同じ上限で返します。

Godot の `String` は、UTF-16 のバイト列から作った文字列などに、対になっていないサロゲート（UTF-16 の文字列を文字の途中で切った切れ端）を持つことがあります。SDK は、`payload`・`metadata`・`operation_id`・共有の本文と起動パラメータの文字列にある切れ端を、U+FFFD 1つに替えて送ります（モックも同じです）。そのため、切れ端だけが違う辞書のキーは同じキーになり、切れ端だけが違う `operation_id` は同じ値になって、同じ投稿の再送として扱われます。分析のイベントの文字列は、切れ端をエスケープで書いて送るので、GameRush がそのイベントを拒みます（モックも拒みます）。
