# HTTP API: ゲームとサムネイル

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/developers/api#games ・ https://gamerush.jp/developers/api#thumbnail

<a id="games"></a>
## ゲーム

| API | 権限 | 内容 |
|---|---|---|
| `GET /api/games` | `games:read` | 自分のゲームと、共同制作者として加わっているゲームの一覧 |
| `GET /api/games/:id` | `games:read` | ゲーム1本と最新ビルド |
| `POST /api/games` | `games:create` | ゲームの新規作成 |
| `PATCH /api/games/:id` | `games:write` | タイトル・説明・遊び方とそれらの言語と訳・元 URL・サムネイル・実況ポリシー・公開設定の変更 |

`GET` の応答は `{ games: [...] }` / `{ game }` です。各ゲームには `id`・`title`・`visibility`・`review_status`・`requested_visibility`・`streaming_policy`・`thumb_url`・`thumb_wide_url`・`thumb_tall_url`・`play_count` などと、最新ビルドの `latestBuild` が入ります。`public` のゲームで最新ビルドが審査待ちか差し戻しのあいだは、配信中の承認済みのビルドが `publishedBuild` に入ります（それ以外は `null`）。`latestBuild` と `publishedBuild` に、ビルドのファイルの一覧（`file_manifest`）は入りません。`approved_build_id` は承認済みのビルドの id です。`leaderboard_manifest_build_id` は、`grush.json` のランキングの定義を承認の時点まで繰り延べているビルドの id で、繰り延べていなければ `null` です。`title` と `description` から読んだハッシュタグは、全角と半角などの互換の違いと大文字・小文字をそろえ `#` を外した形で、タイトル、説明の順に `hashtags` に入ります。`hashtags` はタイトルか説明を書くときに書くので、タイトルや説明に `#` があっても `hashtags` に無いタグを持つ作品があり、タイトルか説明を保存し直すと入ります。既定の文面を書いた言語は `source_locale` に、言語ごとの訳は `localizations` に入ります（[訳を書く](http-api-games.md#games-localizations)）。`entryUrl` は、最新ビルドが `ready` のときのその入口の HTML の URL で、それ以外は `null` です。`viewerRole` は呼んだ人の立場（`owner` か `collaborator`）、`viewerCanAdminister` はオーナーにだけできる操作（ゲームの削除・オーナーの譲渡・共同制作者の管理）ができるかです。

<a id="games-create"></a>
### ゲームを作る

```bash
curl -X POST "https://gamerush.jp/api/games" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "ねこジャンプ",
    "description": "タップで跳ぶだけのショートゲーム。迫ってくる壁のすき間をくぐり抜け、どこまで遠くへ進めるかを競います。進むほどスピードが上がり、壁の形も変わっていきます。ランキングで友だちと記録を比べたり、毎日のチャレンジでコインを集めたりできます。#ねこ",
    "howToPlay": "画面のどこかをタップすると、ねこが少しだけ跳びます。長押しすると高く跳べます。壁のすき間に合わせてタイミングよく跳び、壁にぶつかるとゲームオーバーです。ときどき出てくる魚を取るとシールドが付き、1回だけ壁に当たっても続けられます。",
    "visibility": "public",
    "streamingPolicy": "allowed",
    "acceptTerms": true,
    "confirmAssetRights": true,
    "declareAllAges": true
  }'
```

| フィールド | 内容 |
|---|---|
| `title` | 必須。120 文字まで。改行は空白になる。`#パズル` のように書いた語はゲームのハッシュタグになり、検索の `#パズル` で完全一致で見つかる。ハッシュタグは `description` と合わせて5個まで（同じタグは1つと数える）で、超えると 400（`title.tooManyHashtags`）。`PATCH` でも同じだが、保存済みのタイトルと説明が合わせて上限を超えているときに、どちらも変えない要求（同じ値を送るか、送らない）は、400 にせず、タイトルと説明を書かずにほかの項目を書く |
| `description` | 任意。2000 文字まで（前後の空白を除いた文字数）。100 文字以上を勧めるが、短くても空でも作れる。空文字と省略は `null` になる。`#パズル` のように書いた語は `title` と同じくハッシュタグになる。URL の中の `#` はハッシュタグにならない |
| `howToPlay` | 任意。遊び方（操作やルール）。2000 文字まで（前後の空白を除いた文字数）。100 文字以上を勧めるが、短くても空でも作れる。空文字と省略は `null` になる |
| `sourceLocale` | `title`・`description`・`howToPlay` を書いた言語。`ja` / `en` / `ko` / `zh-Hans` / `zh-Hant` / `id` / `fil` / `vi` / `th` のどれか。省略するか `null` なら未設定（[既定の文面の言語](http-api-games.md#games-source-locale)） |
| `localizations` | 言語ごとの訳。形と検証は `PATCH` と同じ（[訳を書く](http-api-games.md#games-localizations)）。空の項目と、`title` などの既定の文面と同じ訳は保存されない。`sourceLocale` を指定したときは、保存した後にその言語の訳が残る要求は 400（`localizations.sourceLocale`）。既定と同じ文面か空の項目だけなら、正規化で落ちて残らないので通る（[既定の文面の言語](http-api-games.md#games-source-locale)） |
| `visibility` | `public` / `unlisted` / `private`。`unlisted` と `private` は指定した可視性で作られる。`public` を指定したゲームは原則 `private` で始まり、最初のビルドが完了した時点で審査に積まれる（オーナー本人が審査免除の作者か管理者なら審査を経ずに `public` で作られる）。省くか、ほかの値（`Public` のような打ち間違いを含む）を送ると、エラーにはならず `private` で作られる（`PATCH` ではほかの値は 400） |
| `sourceUrl` | 元の配布ページなど。`http` / `https` で 500 文字まで |
| `streamingPolicy` | 実況ポリシー。下の表を参照 |
| `streamingPolicyNote` | `conditional` のときだけ保存される条件の説明。500 文字まで |
| `officialFeatureOptOut` | GameRush 公式の特集記事や SNS での紹介を断るなら `true`。省略すると `false`（紹介してよい）。真偽値でなければ 400 |
| `acceptTerms` | 必須。[利用規約](https://gamerush.jp/terms) と [ゲーム掲載ポリシー](https://gamerush.jp/import-policy) に同意するなら `true` |
| `termsVersion` | 任意。同意した利用規約の版（`2026-10-07` のような施行日の文字列）。送ると作成の時点で施行中の版と照合し、違えばゲームを作らずに 409（`terms.versionMismatch`。施行中の版を `details.termsVersion` に入れる）を返す。文字列でなければ 400（`terms.versionRequired`）。省略するか `null` なら照合しない |
| `confirmAssetRights` | 必須。画像・音・コードなどの素材をすべて自分で作ったか、使う権利を持っているなら `true`。`true` でなければゲームを作らずに 403（`rights.confirmRequired`） |
| `declareAllAges` | `visibility` が `public` / `unlisted` なら必須。ゲームが全年齢向けに適した内容であることを申告するなら `true`。申告した時刻と申告した人をゲームに記録する（`private` で送っても記録する）。`public` / `unlisted` で `false` か省略ならゲームを作らずに 403（`ageRating.declarationRequired`）。`private` なら省略しても作れ、公開へ変えるときに求められる。真偽値でなければ 400 |
| `thumbnail` | サムネイルを同時に上げるとき（16:9 の `thumbnailWide`、9:16 の `thumbnailTall` も同じ）。[サムネイル](http-api-games.md#thumbnail) を参照 |

**応答は `{ game, mediaUploads }` です。本文に冪等キー `operationId`（1〜100 文字の文字列）を付けると、応答が失われた後に同じキーと同じ本文で送り直しても2つ目のゲームはできず、先に作ったゲームが返ります。`mediaUploads` には、まだ上がっていないサムネイルの URL だけが、ゲームが一度も審査を経ておらず審査待ちでもない間だけ入ります。キーはアカウントごとに区別し（同じアカウントのトークンと Studio で共有します）、24 時間保持します。`termsVersion` だけが違う再送は同じ本文として扱います。同じキーで本文が違えば 422（`operation.bodyMismatch`）、先の要求が終わっていなければ 409（`operation.inProgress`。少し待って同じキーで送り直します）、先に作ったゲームが消されていれば 410（`operation.gone`）、今はそのゲームを管理できなければ 403 を返します。作成が途中で失敗したときは、本文を直して同じキーで送り直せます。`operationId` を付けない作成は再試行するたびに別のゲームを作るので、機械的に再試行せず、応答が失われたら `GET /api/games` で作られたかを確かめてからやり直します。**

**トークンでゲームを作るスクリプトや CI も、`visibility` に `public` / `unlisted` を指定するときは `declareAllAges: true` を送る必要があります。無ければ 403 になり、ゲームは作られません。`private` で作る要求は `declareAllAges` が無くても作れます（`confirmAssetRights: true` はどちらでも必須です）。**

対象ゲームを絞ったトークンではゲームを作れません（まだ無いゲームは対象に入れられないため）。

<a id="games-update"></a>
### 設定を変える

`PATCH` は送ったフィールドだけを変えます。Studio の保存ボタンと同じ処理を通るので、審査やホールドの扱いも画面と同じです。

```bash
curl -X PATCH "https://gamerush.jp/api/games/$GAME_ID" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "streamingPolicy": "conditional",
    "streamingPolicyNote": "収益化した配信ではクレジットを表示してください",
    "visibility": "unlisted",
    "declareAllAges": true
  }'
```

| streamingPolicy の値 | 意味 |
|---|---|
| `allowed` | 実況・動画投稿を許可する |
| `conditional` | 条件付きで許可する（条件は `streamingPolicyNote`） |
| `prohibited` | 実況・動画投稿を許可しない |
| `unspecified` | 未設定（既定） |

実況ポリシーの意味と、プレイヤーにどう見えるかは [ゲーム実況ポリシー](https://gamerush.jp/streaming-policy) にあります。`officialFeatureOptOut` も `PATCH` で切り替えられ、真偽値でなければ 400 になります。`sourceUrl` に `null` か空文字を送ると消えます。

`PATCH` の `description` と `howToPlay` も、長さの下限を持ちません。`null` か空文字を送ると消えます。

`title` か `description` を送ると、ハッシュタグも書いた後のタイトルと説明から読み直して書きます。変えた結果が合わせて5個を超えると 400（`title.tooManyHashtags`）です。上限ができる前に保存した、タイトルだけで上限を超えるゲームでは、タイトルを変えずに説明だけを変える要求は、説明を書き、タイトルとハッシュタグは書きません。

全年齢の申告（`declareAllAges`）の記録が無いゲームは、`PATCH` で `declareAllAges: true` を送ると申告を記録できます。公開設定とは関係なく、`private` のままでも送れます。記録が無いゲームを `private` から `public` / `unlisted` へ変えるときは必須です（[公開設定と審査](http-api-games.md#visibility)）。申告は一度記録したら変わらず、記録済みのゲームに送っても何も起きません。公開設定を上げない要求では、ほかのトークンや別の要求が同時に申告していても失敗せず、同じ要求のほかの変更もそのまま保存されます。`private` から上げる要求では、申告は公開設定の変更と一緒に保存され、別の要求が先に申告していたときは公開設定も変えずに `409` `review.stateChanged` になります。`false` を送っても記録は消えず、何も起きません。真偽値でなければ 400 になります。

**`streamingPolicy` に表に無い値（`"Allowed"` のような打ち間違いを含む）を送ると、エラーにはならず `unspecified` として保存されます。`title` / `description` / `howToPlay` / `streamingPolicyNote` は上限を超えた分が切り詰められます。`description` / `howToPlay` / `streamingPolicyNote` の改行は LF に揃い、制御文字（タブを含む）は空白に、行末の空白は削られます。応答の `game` で保存された値を確かめてください。**

<a id="games-localizations"></a>
### 訳を書く

`title`・`description`・`howToPlay` は作品の既定の文面です。これとは別に、言語ごとの訳を `POST` と `PATCH` の `localizations` で書けます。プレイヤーの表示言語の訳があればそれを、無い言語と空の項目には既定の文面を出します。

```bash
curl -X PATCH "https://gamerush.jp/api/games/$GAME_ID" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "localizations": {
      "en": { "title": "Cat Jump", "howToPlay": "Tap to jump." },
      "ko": null
    }
  }'
```

| localizations に送る値 | 内容 |
|---|---|
| キー | 言語。`ja` / `en` / `ko` / `zh-Hans` / `zh-Hant` / `id` / `fil` / `vi` / `th` のどれかを、この綴りのまま書く。`en-US`・`zh-TW` のような地域付きの形、`zh-hans` のような大文字小文字の違う形、ほかの言語は 400 |
| `{ "title", "description", "howToPlay" }` | その言語の訳。送った項目だけを変え、送らなかった項目は今の訳を残す。上限と正規化は既定の文面と同じ |
| `null` | その言語の訳をすべて消す |
| 項目に `null` か `""` | その項目の訳を消す（既定の文面に戻る） |

**応答と `GET` の `localizations` は、`{ "en": { "title": "...", "description": "...", "how_to_play": "..." } }` の形で、保存されている訳だけが入ります。遊び方のキーは `how_to_play` です。既定の文面と同じ訳は保存されないので、`title` と同じ文字列を `en` の `title` に送ると、`en` の `title` は消えます。**

訳は今の値に重ねて保存します。読んでから保存するまでの間に、Studio やほかのトークンが同じゲームの訳か `sourceLocale` を変えていたときは、保存せずに `409` `localizations.changed` を返します。`GET /api/games/:id` で最新の訳を読んでからやり直してください。

<a id="games-source-locale"></a>
### 既定の文面の言語

`sourceLocale` は、`title`・`description`・`howToPlay` を書いた言語です。値は `localizations` のキーと同じく `ja` / `en` / `ko` / `zh-Hans` / `zh-Hant` / `id` / `fil` / `vi` / `th` のどれかを、この綴りのまま送ります。`null` は未設定です。ほかの値（`en-US`・`zh-hans` など）は 400 です。`POST` で省略すると未設定、`PATCH` で省略すると今の値のまま、`PATCH` で `null` を送ると未設定に戻ります。`localizations` を送らない `PATCH` で今と同じ値を送ったときは、省略したときと同じです（毎回送っても、ほかの変更の保存には影響しません）。`GET` と応答の `source_locale` で今の値を確かめられます（未設定は `null`）。

指定したゲームでは、この言語の閲覧者に既定の文面を出し、ゲームの紹介ページはこの言語の版で検索に載ります。英語で書いたゲームは `sourceLocale` を `en` にしてください。未設定のゲーム（`sourceLocale` を送らずに作ったゲームを含む）は、既定の文面を日本語の版として扱い、`ja` を含むどの言語の訳も書けて、閲覧者の言語の訳があればそれを出します。

**`sourceLocale` を指定したゲームは、その言語の訳を持てません。保存した後の `localizations` に `sourceLocale` の言語の訳が残る要求は、何も保存せずに `400` `localizations.sourceLocale` を返します。未設定から指定するときと、別の言語に変えるときに、その言語の訳が残っているときも同じです。既定と同じ文面か空の項目だけを送った言語は、正規化で落ちて残らないので通ります。その言語の訳を消す `null` は送れます。**

既定の文面と訳を入れ替えるときは、1回の `PATCH` に新しい `sourceLocale`・その言語の既定の文面・新しい言語の訳を消す `null`・前の言語の文面を訳として送ります。既定の文面は3項目（`title`・`description`・`howToPlay`）をすべて送ってください。送らなかった項目は前の言語の文面のまま既定に残り、新しい言語のその項目の訳は `null` で消えます。前の言語の訳にも、3項目をすべて送ります。下の例は、日本語で書いて英語の訳を持つゲームを、英語の既定の文面と日本語の訳に入れ替えます。

```bash
curl -X PATCH "https://gamerush.jp/api/games/$GAME_ID" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "sourceLocale": "en",
    "title": "Cat Jump",
    "description": "Tap to jump through the gaps in the walls that keep coming. The farther you go, the faster it gets. Compare records on the leaderboard.",
    "howToPlay": "Tap anywhere to make the cat jump a little, and hold to jump higher. Time your jumps to the gaps; hitting a wall ends the run.",
    "localizations": {
      "en": null,
      "ja": {
        "title": "ねこジャンプ",
        "description": "タップで跳ぶだけのショートゲーム。迫ってくる壁のすき間をくぐり抜け、どこまで遠くへ進めるかを競います。進むほどスピードが上がり、壁の形も変わっていきます。ランキングで友だちと記録を比べたり、毎日のチャレンジでコインを集めたりできます。",
        "howToPlay": "画面のどこかをタップすると、ねこが少しだけ跳びます。長押しすると高く跳べます。壁のすき間に合わせてタイミングよく跳び、壁にぶつかるとゲームオーバーです。ときどき出てくる魚を取るとシールドが付き、1回だけ壁に当たっても続けられます。"
      }
    }
  }'
```

<a id="visibility"></a>
### 公開設定と審査

- `private` への変更はすぐに反映され、審査待ちがあれば取り消されます。
- `unlisted` への変更は、審査を経ずにすぐに反映されます。審査待ちがあれば取り消されます。
- `public` への変更は、最新ビルドが審査済みならすぐに反映されます。そうでなければ `requested_visibility` に希望が入り、`review_status` が `pending` になります。`visibility` は、`unlisted` のゲームなら `unlisted` のまま、承認済みのビルドを配信している `public` のゲームなら `public` のまま、それ以外は `private` のままです。
- `public` のゲームが配信するのは、審査で承認されたビルドです。新しいビルドが審査を待つ間と差し戻された後も、承認済みのビルドの配信が続きます。
- ビルドがまだ無いゲームは `public` にも `unlisted` にもできません（`409` `review.buildRequired`）。
- 素材の権利をまだ確認していないゲームを公開へ変えるときは、`confirmAssetRights: true` を一緒に送ります。無ければ `403` `rights.confirmRequired` になります。
- 全年齢の申告の記録が無いゲームを `private` から `public` / `unlisted` へ変えるとき（公開の審査の申請を含む）は、`declareAllAges: true` を一緒に送ります。無ければ `403` `ageRating.declarationRequired` になり、同じ要求のほかの変更も保存されません。審査免除の作者と管理者、トークンからの変更も同じです。`public` と `unlisted` の間の変更と、`private` への変更では求めません。
- ホールド中のゲームは公開設定を変えられません（`403` `hold.locked`）。
- ホールド中のゲームで `description` か `howToPlay`（どちらかの訳を含む）の内容を変えると、一般公開の審査に積まれます。
- 審査待ち（`review_status` が `pending`）のゲームで `title`・`description`・`howToPlay`・それらの訳・サムネイル・`sourceUrl` の内容を変えると、運営は新しい内容で審査し直します。審査の順番は、変えた時点で申請したものとして後ろへ回ります。
- 変更の途中で審査の状態が変わったときは `409` `review.stateChanged` になります。最新の状態を読んでからやり直してください。

**審査を飛ばせるのは、オーナー本人が運営の認めた審査免除の作者か管理者のときだけです。その場合はトークンからでも Studio と同じく即時に反映されます。共同制作者の立場では審査を飛ばせません。審査免除の作者の場合、運営が最後に差し戻したゲームは審査に回ります。全年齢の申告の記録が無いゲームの申請も、審査を飛ばさずに審査に回ります。**

<a id="thumbnail"></a>
## サムネイル

サムネイルは2段で上げます。まず `POST /api/games` か `PATCH /api/games/:id` にファイルの名前と大きさだけを送り、返ってきた `mediaUploads` の `url` へ画像そのものを `PUT` します。確定の呼び出しはありません。

サムネイルは露出面ごとに3種類あります。正方形の `thumbnail` は「お気に入りのゲーム」などに使う基本の1枚で、ホームの横長カード（オススメ・話題の新作・人気・特集棚）には 16:9 の `thumbnailWide` を出します。フィードではカードの形に合わせ、PC ブラウザなどでカードが横長のときは 16:9 の `thumbnailWide`、スマホなどで縦長のときは 9:16 の `thumbnailTall` を出します。16:9 と 9:16 は任意で、形に合う方が無ければその面でも正方形を使います。3種類とも GIF とアニメーション WebP を使え、その面でアニメーションします。

```bash
SIZE=$(wc -c < thumb.png)
curl -X PATCH "https://gamerush.jp/api/games/$GAME_ID" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"thumbnail\":{\"fileName\":\"thumb.png\",\"size\":$SIZE,\"contentType\":\"image/png\"}}" \
  > patch.json

UPLOAD_URL=$(jq -r '.mediaUploads[] | select(.kind == "thumbnail") | .url' patch.json)
curl -X PUT "$UPLOAD_URL" --data-binary @thumb.png
```

| フィールド | kind | 受け付ける形 |
|---|---|---|
| `thumbnail` | `thumbnail` | png / jpg / webp / gif、1MB まで。これが無いと下の4つ（Small / Compact / Large / Og）も無視される |
| `thumbnailSmall` | `thumbnail-small` | 長辺 512px の webp / jpg、1MB まで。GIF のときは無視 |
| `thumbnailCompact` | `thumbnail-compact` | `thumbnailSmall` を長辺 288px に縮めたもの（一覧の小さな枠向け）。`thumbnailSmall` と同じ形式の webp / jpg、1MB まで。`thumbnailSmall` が無いか形式が違えば無視 |
| `thumbnailLarge` | `thumbnail-large` | 長辺 1920px の webp / jpg、1MB まで。GIF のときは無視 |
| `thumbnailOg` | `thumbnail-og` | SNS の共有カード用の静止 jpg、1MB まで。GIF と WebP のときだけ使い、png / jpg では無視 |
| `thumbnailWide` | `thumbnail-wide` | 横長の 16:9（ホームのカードと、横長に表示したフィード）。推奨 1280×720 の png / jpg / webp / gif、1MB まで |
| `thumbnailTall` | `thumbnail-tall` | 縦長の 9:16（縦長に表示したフィード）。推奨 1080×1920 の png / jpg / webp / gif、1MB まで |
| `thumbSound` | `thumb-sound` | サムネイル音（フィードでカードを選んでいる間に流れる音）。mp3 / m4a、20 秒・512KB まで。`PATCH` だけで受け付け、`thumbSoundGain` が必須 |

- 各フィールドは `{ fileName, size, contentType }` です。形式は `fileName` の拡張子で決まります。
- `url` の期限は 1 時間です。切れたら同じ `PATCH` をやり直して新しい `url` を取ります。
- ゲームのサムネイルの URL は `PATCH` の時点で新しいものへ切り替わります。`PUT` を終えるまでは画像が出ないので、続けて上げてください。
- `thumbnailWide` / `thumbnailTall` は `thumbnail` と独立しています。片方だけ送っても構いませんし、正方形を差し替えても 16:9・9:16 は残ります。
- アニメーション WebP の `thumbnail` に `thumbnailSmall` を送らなければ、一覧向けの縮小版をアニメーションを保ったままサーバが後から作ります。GIF と違い `thumbnailSmall` / `thumbnailLarge` は無視されず、送った派生はそれを使う面でそのまま出ます。
- 16:9・9:16 を外して正方形へ戻すときは、`PATCH` に `clearThumbnailWide: true` / `clearThumbnailTall: true` を送ります。同じ呼び出しでファイルも送った場合はファイルが優先されます。
- `thumbSound` には、音量をそろえる再生の倍率 `thumbSoundGain`（正の数）を一緒に送ります。0.25〜2 の外の値は範囲に寄せて保存します。Studio は音の大きさを測ってこの値を決めます。長さ（20 秒まで）はサーバでは確かめないので、送る前に確かめてください。外すときは `clearThumbSound: true` を送ります。
