# JavaScript の SDK の導入と API

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#javascript

<a id="javascript"></a>
## JavaScript・TypeScript

HTML と JavaScript で書いたゲームと、Phaser などを TypeScript で書いたゲーム向けです。素の HTML ならバンドラは要らず、`<script>` タグ 1 行でも、ES Modules の import でも読めます。TypeScript で使うときは、下の「TypeScript」を見てください。

### 導入

[grush-sdk-js](https://github.com/gamerush-jp/grush-sdk-js) の `grush-sdk.js`（グローバル版）か `grush-sdk.mjs`（ES Modules 版）をゲームのフォルダへコピーするか、CDN から読んでください。依存はありません。CDN から読むときは版を固定してください。版を固定しないと、アップロード済みのビルドの挙動が後から変わります。

```html
<script src="https://cdn.jsdelivr.net/gh/gamerush-jp/grush-sdk-js@v0.24.0/grush-sdk.js"></script>
<script>
  GRush.leaderboards.submit("high_score", 12000).then((result) => {
    if (result.ok) console.log("rank", result.value.rank);
    else console.log("not sent", result.code);
  });
</script>
```

グローバル版は `window.GRush` に入ります。同じ名前の変数が既にあるときは上書きせず、`window.GRushSdk` だけに入ります。

```html
<script type="module">
  import GRush from "./grush-sdk.mjs";

  const self = await GRush.player.getSelf();
  if (self.ok) console.log(self.value.pseudoId);
</script>
```

AI エージェント（Claude Code・Codex など）向けに、開発者向けの文書と同じ内容の Markdown を SDK に同梱しています。プロジェクトのフォルダで `npx -p github:gamerush-jp/grush-sdk-js grush agents` を実行すると、`.gamerush/` に入り、プロジェクトの `AGENTS.md`（あれば `CLAUDE.md` も）から指されます。JavaScript `v0.23.0` 以降の SDK で使えます。

<a id="typescript"></a>
### TypeScript

SDK には TypeScript の型（`grush-sdk.d.ts`）が入っていて、別のパッケージは要りません。npm には出していないので、GitHub から版を固定して入れてください。Vite などのバンドラでビルドすると、SDK はゲームのビルドに含まれます。

```bash
npm install github:gamerush-jp/grush-sdk-js#v0.23.0
```

```typescript
import GRush, { type GRushCode } from "grush-sdk-js";

const result = await GRush.leaderboards.submit("high_score", 12000);
if (result.ok) {
  console.log("rank", result.value.rank); // number | null
} else {
  const code: GRushCode = result.code; // "rateLimited" など
  console.log("not sent", code);
}
```

結果は `ok` を確かめると、`value` の型か `code` の型に絞り込まれます。`GRushResult`・`GRushCode` など、型の名前も import できます。

`<script>` タグで CDN から読むときは、同じ版を `npm install -D` で開発用に入れ、型の参照を 1 行書きます。`window.GRush` に型が付きます。

```typescript
/// <reference types="grush-sdk-js" />

const self = await window.GRush.player.getSelf();
if (self.ok) console.log(self.value.pseudoId);
```

### API

```javascript
const self = await GRush.player.getSelf();
const profile = await GRush.player.requestProfile();

const saved = await GRush.cloudSave.save({ stage: 3 }, "default");
const loaded = await GRush.cloudSave.load("default");

const joined = await GRush.net.join({ mode: "duel" });
if (joined.ok) {
  const room = joined.value;
  room.on("message", (message) => {
    if (message.isStale) return;
    apply(message.from, message.json());
  });
  room.on("peerjoin", (peer) => console.log(peer.index));
  room.on("error", ({ code }) => console.warn(code));
  room.on("close", ({ reason }) => console.log(reason));
  room.sendJson({ x: 1, y: 2 }, { channel: GRush.CHANNEL_UNRELIABLE, to: GRush.EVERYONE });
  const now = room.serverTimeMs();
  await room.leave();
}
```

結果はすべて `{ ok, value, code, message }` の形の Promise で返り、reject しません。`code` は Unity の `GRushErrorCode` と同じ名前を小文字始まりにした文字列（`invalidParams` など）です（[エラーコード](sdk-basics.md#error-codes)）。JavaScript 版だけにある `conflict` は、クラウドセーブの版ずれ（`baseRevision` の不一致）です。回数の上限で `rateLimited` になったときと、`join` が `unavailable` になったときは、待つ時間が分かれば `retryAfterMs` が入ります。

- 送れるのは `ArrayBuffer`・型付き配列・文字列です。`sendJson` は値を JSON 文字列にして送ります。受け取ったメッセージは `text()` と `json()` で読めます。
- `GRush.cloudSave` は、本人だけが読むクラウドセーブです。他プレイヤーへは見えません。ゲストは `signInRequired` になります。ゲストの分を端末に置くときは、下の「クラウドセーブの端末への保存」の `fallback: "local"` を使います。
- クラウドセーブの payload は、JSON にして 256KB までです。サインインしてクラウドへ保存するときは、配列とオブジェクトの入れ子は 3000 段までで、キーにも値にも、対になっていないサロゲート（UTF-16 の文字列を文字の途中で切った切れ端）を含む文字列は入れられません。外れると `invalidParams` になります。スロット名は英数字と `.` `_` `:` `-` の 1〜64 文字で、省略すると `default` です。
- サインインしているときの `save` は、GameRush が端末に控えた時点で成功を返し、クラウドへはまとめて送ります。返る項目の `synced`（JavaScript SDK `v0.19.0` から）が `false` なら、まだクラウドへ届いていません。届く前でも、同じ端末の `load` は最後に保存した中身を返します。`revision` は、クラウドに書けたときに付くと見込んだ版で、次の `save` の `baseRevision` にそのまま渡せます。保存の回数に GameRush が決めた上限はありませんが、毎フレームは呼ばず、区切りのよいところで保存してください。
- 別の端末の方が新しく、控えた保存をクラウドへ送れなかったときは、クラウドを上書きしません。そのスロットの次の `save` が `conflict` になるので、`load` してから書き直してください。`shop.purchase`・`shop.ack`・`trade.create`・`trade.accept`・`trade.ack` は、呼ぶ前に控えた保存をクラウドへ送り切ります。送り切れなければ `unavailable` になるので、時間を置いて呼び直してください。
- 15 秒待っても GameRush から答えが無ければ `timeout` で返り、Promise が止まったままになることはありません。`timeout` の `save` は届いたかどうか分からないので、`load` で確かめてから書き直すか、`baseRevision` を付けて送り直してください。
- ゲームを止めたときの `visibilitychange` と時計の扱いは、[一時停止](sdk-basics.md#pause) にあります。セーブは止められたときに送ってください。
- `GRush.backend` は、GameRush 上では `web`、`localhost`・`127.0.0.1`・`[::1]`・`file://` では `mock`、それ以外のサイトでは `none` になります。`none` のときは、どの呼び出しも `unsupported` を返します。

```javascript
const joined = await GRush.net.join({
  mode: "arena",
  maxPeers: 32,
  topology: "hub",
  hostSelection: "auto",
});
if (joined.ok) {
  const room = joined.value;
  console.log(room.maxPeers, room.topology); // 古い GameRush のアプリでは 8 と "mesh"
}
```

`join` には、部屋の定員 `maxPeers`（1〜100、省略すると 8）、形 `topology`（`"mesh"` か `"hub"`、省略すると `"mesh"`）、ホストの選び方 `hostSelection`（`"auto"`）を渡せます。どれかを渡すと、`protocolVersion` 11 未満の GameRush では `unsupported` が返ります。入った部屋の定員と形は `room.maxPeers` と `room.topology` で読めます。`hub` の部屋で送れる宛先と送信の上限は [リアルタイムマルチプレイ](multiplayer.md#multiplayer) にあります。

### クラウドセーブの端末への保存

`load`・`save`・`remove` の最後の引数に `{ fallback: "local" }` を渡すと、GameRush がプレイヤーのサインインを確かめられないとき（渡さなければ `signInRequired` になるとき）だけ、セーブを端末に読み書きします。JavaScript 版だけの機能です。

```javascript
const loaded = await GRush.cloudSave.load("default", { fallback: "local" });
if (loaded.ok) {
  const revision = loaded.value?.revision ?? 0;
  const saved = await GRush.cloudSave.save({ stage: 3 }, "default", {
    baseRevision: revision,
    fallback: "local",
  });
  if (saved.ok) console.log(saved.value.storage); // "cloud" か "local"
}
```

- 返る項目の `storage` は、クラウドに置いたときは `cloud`、端末に置いたときは `local` です。`local` は、GameRush がサインインを確かめられず端末に保存したことを表します。端末のセーブの `revision` は常に `0` です。
- 端末のセーブは、その端末のそのアプリ（ブラウザ）の中にだけあります。別の端末やアプリからは読めず、ブラウザが消すこともあります。
- サインインしても、端末のセーブは自動ではクラウドへ上がりません。サインイン後の `load` でクラウドに無ければ端末のセーブが返るので、それを `save` するとクラウドへ上がります。クラウドにあればクラウドのセーブが返ります。
- 端末のセーブには、保存した時点で GameRush が分かっていたアカウントを記録します。サインイン済みの `load` では、別のアカウントのものと分かっている端末のセーブは返りません。どのアカウントか分からないまま保存した端末のセーブは、サインインしたどのアカウントにも返ります。
- サインインを確かめられないときの `load` と `remove` は、どのアカウントで保存したかに関係なく、その端末のセーブを返し、消します。共用の端末では、前に使った人の端末のセーブが返ることがあります。
- `fallback: "local"` 付きの `save` と `remove` がクラウドで成功すると、同じスロットの、そのプレイヤーの端末のセーブと、どのアカウントのものか分からない端末のセーブが消えます。別のアカウントのものは残ります。
- 一度サインインを確かめられなくなった後でサインインが戻ると、クラウドのセーブが優先されます。その間に端末へ保存した新しい分は、クラウドにセーブがあれば `load` で返りません。`fallback: "local"` 付きの保存がクラウドで成功すると、そのプレイヤーの端末のセーブは消えます。
- 端末への書き込みでは `baseRevision` を見ず、最後の書き込みが残ります。端末のセーブの `revision`（`0`）をそのまま `baseRevision` に渡すと、クラウドが空なら書け、クラウドにあれば `conflict` になります。
- サインインの直後の `save` が `conflict` になったら、`load` してから保存し直してください。
- 切り替えるのはサインインを確かめられないときだけです。通信の失敗・版ずれ・上限超えなど、ほかの失敗では端末に保存せず、そのまま失敗を返します。
- `fallback` に `"local"` と `null` 以外の値を渡すと `invalidParams` です。`null` は渡さないときと同じです。`protocolVersion` が 5 未満の GameRush では `fallback` を無視し、渡さないときと同じ呼び出しになります（ゲストは `signInRequired`）。
