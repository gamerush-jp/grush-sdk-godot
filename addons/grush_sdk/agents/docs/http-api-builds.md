# HTTP API: ビルドのアップロード

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/developers/api#builds

<a id="builds"></a>
## ビルドのアップロード

ビルドは3段で上げます。権限はどれも `builds:write` で、最上位に `grush.json` を含むビルドでは `leaderboards:write` も要ります。Unity なら [Editor 拡張](editor-upload.md#editor-upload) が同じ手順とプレイヤーの組み立てを持っているので、自分で書く必要はありません。

| 段 | API | 内容 |
|---|---|---|
| 1 | `POST /api/games/:id/builds` | ファイルの一覧を送り、ファイルごとの送り先を受け取る |
| 2 | `PUT <uploadUrls[].url>` | 各ファイルの中身をそのまま送る |
| 3 | `POST /api/builds/:buildId/complete` | 中身を検査して、ゲームの最新ビルドにする |

```json
{
  "engine": "godot",
  "files": [
    { "path": "__grush-player.json", "size": 112 },
    { "path": "index.js", "size": 301224 },
    { "path": "index.wasm", "size": 35651584 },
    { "path": "index.pck", "size": 2097152 }
  ]
}
```

```bash
curl -X POST "https://gamerush.jp/api/games/$GAME_ID/builds" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @manifest.json > build.json

jq -c '.uploadUrls[]' build.json | while read -r ticket; do
  path=$(echo "$ticket" | jq -r '.path')
  url=$(echo "$ticket" | jq -r '.url')
  curl -X PUT "$url" -H "If-None-Match: *" --data-binary @"build/$path"
done

BUILD_ID=$(jq -r '.build.id' build.json)
curl -X POST "https://gamerush.jp/api/builds/$BUILD_ID/complete" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

作成の応答は `{ build, uploadUrls, entryUrl }` です。`build` は作ったビルド（`id` を complete に使う）、`uploadUrls` は送ったファイルごとの `{ path, key, url, headers }`（`path` は一覧に書いた名前、`key` は保存先の識別子、`url` と `headers` は送り先）、`entryUrl` はこのビルドの入口の HTML の URL です。complete の 200 の応答は `{ build, entryUrl }` で、`build` は `ready` になったビルドです。

<a id="builds-manifest"></a>
### ファイルの一覧で決まること

- `engine` は `unity` / `godot` / `gdevelop` / `phaser` / `web` のどれかです。ほかの値はエラーにならず、`null`（エンジン未指定）で保存されます。
- ルートに `index.html` か、ロード設定の `__grush-player.json` のどちらか一方が要ります。無ければ `400` `build.missingEntry`、両方あれば `400` `build.conflictingEntry` です。HTML は圧縮せずに送ってください。ロード設定は 64KB までです。
- ファイル数は 2000 まで、合計は 50MB までです（目安は 15MB 以下で、30MB 以上は危険です）。`size` はそのまま送るバイト数を書きます。
- 使えるファイルの種類は Studio からのアップロードと同じで、拡張子で決まります（大文字小文字は問わず、後ろに `.br` / `.gz` が付いた名前は、その前の拡張子で決まります）。ほかの拡張子のファイルが1つでもあると、作成が `400` `build.unsupportedExtension`（`params.path` に原因のファイル）になります。ソースマップ（`.js.map`）もこれに当たるので、含めないでください。
- Unity の `Build/x.wasm.br` のように、書き出した時点で `.br` / `.gz` が付いたファイルはその名前のまま送ります。自分で圧縮したファイルを送るときは、元の名前の `path` に `"encoding": "gzip"` か `"encoding": "br"` を添え、`size` は圧縮後の大きさにします。ただし HTML は `encoding` を付けても `.gz` / `.br` の名前でも受け付けず、`400` `build.compressedHtml` になります。`grush.json` は `"encoding": "br"` を受け付けません（下）。
- 最上位の `grush.json` はランキングの定義として読みます（書式は [SDK ガイドのランキング](leaderboards.md#leaderboards)）。トークンに `leaderboards:write` が無ければ `403` です。`grush.json` は 64KB までで、圧縮しないか `"encoding": "gzip"` で送ります。`"encoding": "br"` は作成の時点で `400` `build.leaderboardManifestCompressed`、圧縮せずに送る 64KB 超のファイルは `400` `build.leaderboardManifestTooLarge` です。gzip で送ったものの大きさは展開してから確かめ、64KB を超えれば complete が `422` を返します。

使える拡張子は次のとおりです。`.html`・`.js`・`.wasm`・`.data`・`.json`・`.png`・`.jpg`・`.jpeg`・`.gif`・`.bmp`・`.css`・`.unityweb`・`.pck`・`.ico`・`.svg`・`.webp`・`.mp3`・`.m4a`・`.aac`・`.ogg`・`.wav`・`.mp4`・`.txt`・`.csv`・`.xml`・`.yml`・`.yaml`・`.ttf`・`.woff`・`.woff2`・`.webmanifest`・`.bytes`・`.bundle`・`.assetbundle`・`.bin`・`.dat`・`.bank`・`.ress`・`.resource`・`.fnt`・`.atlas`・`.skel`・`.glsl`・`.frag`・`.vert`・`.tmx`・`.tsx`・`.tmj`・`.tsj`・`.otf`・`.webm`・`.ktx`・`.pvr`・`.ktx2`・`.basis`・`.glb`・`.ldtk`

Studio の画面から上げて Unity か Godot と判別されたビルドと、Unity `v1.14.0` 以降の Editor 拡張から上げた Unity のビルドは、GameRush がプレイヤーを組み立て、ローディングバーと起動に要るファイルの優先読み込みを付けます。それより古い Editor 拡張と API から上げたビルドは判別を通らず、`index.html` を送ればそれがそのまま使われます。

Godot のビルドを API から GameRush のプレイヤーで起動するには、上の例のように `index.html` の代わりにロード設定を送ります。中身は次の形です。`executable` は `.pck` / `.wasm` / `.js` に共通の名前です。`fileSizes` は展開後の大きさで、省くとローディングバーが進みません。

```json
{
  "kind": "godot",
  "executable": "index",
  "fileSizes": { "index.wasm": 35651584, "index.pck": 2097152 }
}
```

<a id="builds-put"></a>
### ファイルを送る

- `uploadUrls[].headers` に入っているヘッダーは、そのまま付けて送ってください（いまは `If-None-Match: *` です）。
- 同じファイルは1度しか書けません。2度目は `412` になるので、送信済みとして扱って構いません。途中で止まったときは、残りのファイルだけ送り直せます。
- `url` の期限は 1 時間です。

<a id="builds-complete"></a>
### 完了させる

`complete` は、送ったファイルの大きさ・中身の形式・HTML の内容を検査してから、ゲームの最新ビルドに切り替えます。

| 応答 | 意味 | 次にすること |
|---|---|---|
| 200 | ビルドが `ready` になり、ゲームの最新ビルドになった | — |
| 403 | 最上位に `grush.json` を含むビルドで、トークンに `leaderboards:write` が無い。ビルドには触れない | `leaderboards:write` を持つトークンで呼ぶ |
| 409（`details.missing` 付き） | 送っていないファイルがある。アップロード中のビルドは失敗扱いになる | ビルドの作成からやり直す |
| 409（`details` なし、ゲームの状態が変わった） | アップロード中に、ほかの操作でゲームの状態が変わった | 同じ `complete` をもう一度呼ぶ |
| 409（`details` なし、ビルドが失敗済み・破棄済み） | 前の `complete` で既に失敗したか、ビルドが破棄された | ビルドの作成からやり直す |
| 422 | 中身の検査で弾かれた（`params.path` に原因のファイル）。アップロード中のビルドは消える | ファイルを直してから作成し直す |
| 422（`code` が `build.leaderboardManifest` で始まる） | `grush.json` を読めないか、反映できない宣言がある（下の表）。アップロード中のビルドは消える | `grush.json` を直してから作成し直す |
| 503 | 一時的に処理できなかったか、アップロードの機能を止めている（[エラーの形](http-api.md#errors)） | `Retry-After` があればその秒数だけ待ってから、同じ `complete` をもう一度呼ぶ |

| `grush.json` の 422 の `code` | 原因 |
|---|---|
| `build.leaderboardManifestInvalidJson` | JSON のオブジェクトとして読めない |
| `build.leaderboardManifestUnknownField` | 知らない項目がある（`params.field`） |
| `build.leaderboardManifestInvalidField` | 値が正しくない（`params.field`） |
| `build.leaderboardManifestDuplicateKey` | `key` が重複している（`params.key`） |
| `build.leaderboardManifestTooMany` | 定義が 21 個以上ある |
| `build.leaderboardManifestTooLarge` | 64KB を超える |
| `build.leaderboardManifestSemanticsLocked` | スコアが投稿済みの枠の `sort`・`valueType`・`aggregation`・`period` を変えようとした（`params.key`） |
| `build.leaderboardManifestLimit` | すでにある枠と合わせて 1 ゲーム 20 個を超える |

`grush.json` を含むビルドの 200 の応答には `leaderboards: { applied, unchanged, failed }` が付きます。`applied` は作成か更新をした `key`、`unchanged` は同じ内容で何も書かなかった `key` です。検査の後に投稿が割り込むなどで書けなかった定義は、ビルドを最新にしたまま `failed: [{ key, code }]` に載ります。`grush.json` に書かなかった `key` の枠は、消えも止まりもしません。`public` のゲームで審査を待つビルドは、`grush.json` の検査だけを `complete` で行い、定義は審査で承認されて配信される時点で反映します。このときの応答には `leaderboards` の代わりに `leaderboardsDeferred: true` が付きます。

既に `ready` になったビルドへ `complete` をもう一度呼んで 400・409・422 が返ったときは、ビルドは `ready` のまま残り、配信も続きます。失敗扱いにも削除にもならないので、作成からやり直す必要はありません。

**`public` のゲームに審査前のビルドを完了させると、ゲームは `public` のまま、新しいビルドが審査に積まれます（`review_status` が `pending`）。審査の間は前に承認されたビルドの配信が続き、承認されると新しいビルドに差し替わります。差し戻されたときは、新しいビルドは配信されず、承認済みのビルドの配信が続きます。新しいビルドは Studio の試遊で確かめられます。オーナー本人が運営の認めた審査免除の作者か管理者なら、審査を経ずにすぐ差し替わります。`unlisted` のゲームは審査を経ずに、`unlisted` のままビルドが差し替わります。**

`POST /api/games/:id/builds` の本文に冪等キー `operationId`（1〜100 文字の文字列）を付けると、同じキーでの再送は2つ目のビルドを作らず、先に作ったビルドと出し直した `uploadUrls` を返します。応答が失われたときや、presigned URL の期限が切れて `PUT` が 403 になったときは、同じキーと同じ本文で作成を送り直し、返った URL で続きを送ります。キーはアカウントとゲームごとに区別し（同じアカウントのトークンと Studio で共有します）、24 時間保持します。先に作ったビルドが `ready` なら `uploadUrls` は空です。同じキーで本文が違えば 422（`operation.bodyMismatch`）、先の要求が終わっていなければ 409（`operation.inProgress`。少し待って同じキーで送り直します）、先に作ったビルドが消されたか失敗していれば 410（`operation.gone`）を返します。作成が途中で失敗したときは、本文を直して同じキーで送り直せます。`operationId` を付けない作成は再試行するたびに別のビルドを作るので、機械的に再試行しないでください。
