# エディタとモックでの動作確認

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#testing ・ https://gamerush.jp/sdk#samples

<a id="testing"></a>
## エディタでの動作確認

WebGL / Web 書き出し以外では、SDK は自動的にモックへ落ちます。JavaScript 版と、Web に書き出した Godot は、`localhost`・`127.0.0.1`・`[::1]`・`file://` で開いたときにモックへ落ちます。これが無いとエディタで一切テストできないため、モックは付属品ではなく SDK 本体の一部として扱っています。

| 切り替え | Unity | Godot | JavaScript |
|---|---|---|---|
| サインイン状態 | `GRushMock.SignedIn` | `GRushMock.signed_in` | `GRush.mock.config.signedIn` |
| 表示名 | `GRushMock.DisplayName` | `GRushMock.display_name` | `GRush.mock.config.displayName` |
| 名前とアイコンを表示する設定 | `GRushMock.GrantProfileConsent` | `GRushMock.grant_profile_consent` | `GRush.mock.config.grantProfileConsent` |
| unreliable の欠落率 | `GRushMock.UnreliableDropRate` | `GRushMock.unreliable_drop_rate` | `GRush.mock.config.unreliableDropRate` |
| 2人目の peer | `GRushMock.AddPeer(name)` | `GRush.mock_add_peer(name)` | `GRush.mock.addPeer(name)` |
| 部屋のエラー | `GRushMock.RaiseRoomError(code, message)` | `GRush.mock_raise_room_error(code, message)` | `GRush.mock.raiseRoomError(code, message)` |
| ランキングの枠 | `GRushMockLeaderboards.Define(key, title, …)` | `GRushMockLeaderboards.define(key, title, …)` | `GRush.mock.defineLeaderboard(key, { … })` |
| ランキングの枠を grush.json の中身で宣言（[ランキング](leaderboards.md#leaderboards)） | `GRushMockLeaderboards.LoadManifest(json)` | `GRushMockLeaderboards.load_manifest(json_text)` | `GRush.mock.loadLeaderboards(manifest)` |
| ランキングの他プレイヤー | `GRushMockLeaderboards.AddRival(key, name, value)` | `GRushMockLeaderboards.add_rival(key, name, value)` | `GRush.mock.addRival(key, name, value)` |
| 他プレイヤーの公開状態 | `GRushMockPlayerStates.Define(id, json, hidden)` | `GRushMockPlayerStates.define(id, payload, hidden)` | `GRush.mock.definePlayerState(id, payload, { hidden })` |
| rating 付きの公開状態（相手探し） | `GRushMockPlayerStates.Define(id, json, hidden, rating)` | `GRushMockPlayerStates.define(id, payload, hidden, rating)` | `GRush.mock.definePlayerState(id, payload, { rating })` |
| 確認用の表示の状態を届ける | `GRushMockPlayerStates.Preview(id, json, revision, rating)` | `GRushMockPlayerStates.preview(id, payload, revision, rating)` | `GRush.mock.previewPlayerState(id, payload, { revision, rating })` |
| モックの相手の疑似ID | `GRushMock.Rivals` | `GRushMock.RIVALS` | `GRush.mock.rivals` |
| 相手からのメッセージを届ける | `GRushMockInbox.Receive(from, kind, json)` | `GRushMockInbox.receive(from, kind, payload)` | `GRush.mock.receiveInbox(from, kind, payload)` |
| 相手が出品する | `GRushMockTrades.Offer(from, offer, want, options)` | `GRushMockTrades.offer(from, offer, want, options)` | `GRush.mock.offerTrade(from, offer, want, options)` |
| 相手が自分の出品を受ける | `GRushMockTrades.Accept(tradeId, give, by)` | `GRushMockTrades.accept(trade_id, give, by)` | `GRush.mock.acceptTrade(tradeId, give, by)` |
| 出品をいま期限切れにする | `GRushMockTrades.Expire(tradeId)` | `GRushMockTrades.expire(trade_id)` | `GRush.mock.expireTrade(tradeId)` |
| 受信箱・交換所の通報の確認の答え | `GRushMock.ConfirmInboxReport / ConfirmTradeReport` | `GRushMock.confirm_inbox_report / confirm_trade_report` | `GRush.mock.config.confirmInboxReport / confirmTradeReport` |
| プレイヤー状態の通報の確認の答え | `GRushMock.ConfirmPlayerStateReport` | `GRushMock.confirm_player_state_report` | `GRush.mock.config.confirmPlayerStateReport` |
| 共有の結果（opened / cancelled） | `GRushMock.ShareStatus` | `GRushMock.share_status` | `GRush.mock.config.shareStatus` |
| 共有できるか | `GRushMock.ShareAvailable` | `GRushMock.share_available` | `GRush.mock.config.shareAvailable` |
| 表示言語（空なら端末の言語）。変更の通知を出すのは Unity だけで、値が変わらなければ出しません | `GRushMock.SetLocale(tag)` | `GRushMock.locale` | `GRush.mock.config.locale` |
| 起動パラメータ（既定は空。GameRush の制限では確かめずにそのまま返す） | `GRushMock.LaunchParams["item"] = "sword"` | `GRushMock.launch_params = {"item": "sword"}` | `GRush.mock.config.launchParams = { item: "sword" }` |

`AddPeer` / `mock_add_peer` / `mock.addPeer` が返す相手は、同じプロセス内の2人目の peer として実際に部屋へ入り、送受信が往復します。実機やサーバへ繋がずに2人分の挙動を確認できます。

**モックが再現するのは、実サーバの縛りの一部です。**

- ランキング: 宣言していない key と、宣言した値域の外の値を `InvalidParams` で弾きます。止めた枠（`enabled: false`）への投稿と取得、`grush.json` で `minValue` / `maxValue` を書かなかった枠への投稿も、実サーバと同じく弾きます。集約（`best` / `last` / `sum`）も実サーバと同じように働きます。値の型（`int` と `duration_ms` の枠に小数、`duration_ms` の枠に負の値）も、実サーバと同じく値域より先に弾きます。JavaScript 版は、入れ子が 3000 段を超える `metadata`、キーか値に対になっていないサロゲートを含む `metadata`、対になっていないサロゲートを含む `operationId` も、実サーバと同じく値域より先に弾きます。Unity 版は、`metadataJson` に JSON のエスケープ（`\ud83d` など）で書いた切れ端だけを同じく弾き、文字列にそのまま入れた切れ端は U+FFFD に替えて受け付けます。Godot 版は、切れ端を U+FFFD に替えるので切れ端では弾かず、入れ子は Godot が送って読み戻せる深さ（[Godot 4](setup-godot.md#godot)）を超えたものを弾きます。
- 公開プレイヤー状態: 実サーバと同じく、JSON オブジェクトでない payload、配列とオブジェクトの入れ子が 3000 段を超える payload、キーか値に対になっていないサロゲートを含む payload、UTF-8 のバイト数で 4KB を超える payload を `InvalidParams` で弾きます。Unity 版は文字列のエスケープ（`\u3042` など）を書いたまま数えるので、エスケープを含む payload を実サーバより大きく数えることがあります。JavaScript 版は base64 のような読めない長い文字列も弾きます。Godot 版は、入れ子が 3000 段より浅くても、Godot が送って読み戻せる深さ（[Godot 4](setup-godot.md#godot)）を超えた `payload` を弾きます。Unity 版と Godot 版は、WebGL / Web の書き出しで GameRush へ渡すときと同じく、文字列にそのまま入れた切れ端を U+FFFD に替えてから確かめます。Unity 版の生の JSON に、JSON のエスケープ（`\ud83d` など）で書いた切れ端は、そのまま届いて弾かれます。
- クラウドセーブ（JavaScript 版）: ゲストは `signInRequired`、スロット名と payload の誤りは `invalidParams`、`baseRevision` の食い違いは `conflict` になります。スロット名と payload の大きさの検査はサインインの確認より先なので、ゲストでも誤っていれば `invalidParams` になります。入れ子が 3000 段を超える payload と、キーか値に対になっていないサロゲートを含む payload も、実サーバと同じく、クラウドへ保存するときに `invalidParams` で弾きます。
- マルチプレイ: `join` の mode・部屋コード・目安の人数・定員・形を、GameRush と同じ規則で `InvalidParams` で弾きます。モックの部屋はゲームが入ったときの定員と形を覚え、違う定員か形の `join` は、部屋コードを渡さなければ新しい部屋で始めます。部屋コードを渡すと、JavaScript 版と Godot 版はどの部屋コードでも `InvalidParams` です。Unity 版は今の部屋の部屋コードのときだけ `InvalidParams` で、ほかの部屋コードなら新しい部屋で始めます。`hub` の部屋では、ホスト以外の送信の宛先を GameRush と同じく確かめます。ホストは番号の最も小さい参加者で、ホストの選び方・入力の 50ms ごとの束ね・送信の上限・ホストの交代は再現しません。満員を試すときは、JavaScript は `GRush.mock.config.maxPeers`、Godot は `GRushMock.max_peers` を下げます（部屋の定員と小さいほうが効きます）。Unity は定員の小さい部屋へ入ってから `AddPeer` します。
- 相手探し: モックの相手3人は rating 付きの公開状態を持ち、自分と伏せた状態を除いてランダムに返します。件数と rating の範囲の誤りは `InvalidParams` です。
- 受信箱と交換所: payload・offer・want・give の形と大きさ、自分宛ての禁止、`operationId` での冪等、受付中の出品の 10 件の上限、受諾の結果、pending と ack を実サーバと同じ規則で扱います。モックの相手は届いたメッセージを同じ kind と payload で送り返し、はじめは相手からのメッセージ1通と相手の受付中の出品2件があります。通報を承諾すると相手をブロックし、その相手のメッセージと出品は見えなくなります。送信と出品の頻度の上限は再現しません。
- クラウドセーブの `fallback: "local"`（JavaScript 版）: `signedIn` が `false` のときはモックの中の端末の保存先に読み書きし、`storage: "local"`・`revision: 0` を返します。`signedIn` を `true` に戻すと、`load` はクラウドに無ければ端末のセーブを返し、`save` と `remove` はクラウドで成功すると端末のセーブを消します。端末の保存先はページを読み直すと空になり、`GRush.mock.reset()` でも空になります。

session 束縛・有効プレイ 10 秒・投稿上限はエディタでは意味を持たないので省いてあります。つまりエディタで通った投稿が実環境で 400 / 403 / 429 になることはあるので、投稿の失敗経路はゲーム側で必ず扱ってください。

招待のモックはシートを出さず、選んだ結果（既定は 1 人へ送った sent）をそのまま返します。招待の部屋への `join` は再現しないので、起動パラメータに入れた招待の部屋へ `join` すると、GameRush と違い、招いた人の居ない新しい部屋になります。

共有のモックは確認シートを出さず、選んだ結果（既定は opened）をそのまま返します。添えた起動パラメータは GameRush と同じ制限で確かめ、合わなければ `InvalidParams` を返します。本文と画像の検査はしないので、弾かれる本文（[ゲームからの共有](share.md#share)）は GameRush 上で確かめてください。

**`UnreliableDropRate` / `unreliableDropRate` は既定 0 ですが、出荷前に必ず 0 より大きくして試してください。**

GameRush では、WebRTC で直結した相手への `unreliable` は落ち、並びも替わります。ただ、中継を通る相手には落ちずに届き、直結した相手にも通信が安定していればほとんど落ちないので、実際に遊ぶだけでは落ちる前提で書けているかを確かめられません。モックの欠落率を上げて確かめてください（[リアルタイムマルチプレイ](multiplayer.md#multiplayer)）。

<a id="samples"></a>
## サンプル

Unity と Godot は各2本、JavaScript は1本です。Unity と Godot のサンプルはシーンアセットを持たないので、空のシーンにノード（Unity は GameObject、Godot は Control）を1つ作ってスクリプトを付けてください。

| サンプル | 内容 |
|---|---|
| Score Attack | 疑似IDと表示名の取得。ベストスコアはローカル保存 |
| Score Attack（JavaScript） | 10 秒タップ。ランキングへの投稿と上位表示。localhost から開くとモックで動く |
| Duel | 2人対戦。paddle は unreliable、ボールはホストが送る。エディタではモックの相手が動く |

Unity と Godot のサンプルではランキングと公開プレイヤー状態を使っていないので、[ランキング](leaderboards.md#leaderboards)・[公開プレイヤー状態](player-state.md#player-state) の API を直接呼んでください。
