# HTTP API: ランキングの定義とアナリティクス

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/developers/api#leaderboards ・ https://gamerush.jp/developers/api#analytics

<a id="leaderboards"></a>
## ランキングの定義

ゲームから投稿するランキングの枠を宣言します。ゲーム側からの投稿と取得は SDK の役目で、ここにあるのは作者の手元から枠を管理する API です（[SDK ガイドのランキング](leaderboards.md#leaderboards)）。

API を使わずに、ビルドの最上位に置いた `grush.json` で同じ定義を宣言することもできます（書式は [SDK ガイドのランキング](leaderboards.md#leaderboards)、アップロードでの扱いは [ビルドのアップロード](http-api-builds.md#builds)）。`grush.json` に書いた `key` の枠は、`grush.json` を含むビルドが最新になるたびにファイルの中身で書き換わります。`public` のゲームで審査を待つビルドの定義は、そのビルドが承認されて配信される時点で反映されます。ここの API で `title`・値域・`enabled` を変えても、そのようなビルドを次に上げたときにファイルの値へ戻ります。投稿のある枠の `sort` / `valueType` / `aggregation` / `period` を API で変えたときは、`grush.json` も合わせてください。食い違ったままのビルドは `422` で失敗します。

| API | 権限 | 内容 |
|---|---|---|
| `GET /api/games/:id/leaderboards` | `leaderboards:read` | 定義の一覧（停止中も含む） |
| `PUT /api/games/:id/leaderboards/:key` | `leaderboards:write` | `key` での冪等な作成・更新。定義を丸ごと置き換える。スクリプトから流すならこれ |
| `POST /api/games/:id/leaderboards` | `leaderboards:write` | 作成。同じ `key` があれば `409` |
| `PATCH /api/games/:id/leaderboards/:leaderboardId` | `leaderboards:write` | 送ったフィールドだけ更新 |
| `DELETE /api/games/:id/leaderboards/:leaderboardId` | `leaderboards:write` | 削除。投稿済みのエントリも消える |
| `GET /api/games/:id/leaderboards/anomalies` | `leaderboards:read` | 不審な投稿として印が付いたエントリの一覧 |

| フィールド | POST / PUT | 値 |
|---|---|---|
| `key` | `POST` は必須。`PUT` はパスで渡す（本文に書くならパスと同じ値） | 英数字と `.` `_` `:` `-` で 64 文字まで |
| `title` | 必須 | 60 文字まで。改行は空白になる |
| `sort` | 必須 | `desc`（大きいほど上）/ `asc` |
| `valueType` | 必須 | `int` / `float` / `duration_ms` |
| `aggregation` | 必須 | `best` / `last` / `sum` |
| `period` | 必須 | `all_time` / `daily` / `weekly` / `monthly` |
| `minValue` / `maxValue` | 任意（投稿を受けるには要る） | 受け付ける値域。両方そろえて指定し、`minValue` は `maxValue` より小さくする（そうでなければ `400`）。省くと値域なし |
| `enabled` | 任意 | `false` で投稿を止める。省くと `true` |

**値域を宣言していない枠は、ゲームからの投稿をすべて拒みます。投稿を受ける枠には、必ず `minValue` と `maxValue` を指定してください。**

**`PUT` は、本文の内容で定義を丸ごと置き換えます。省いたフィールドは今の値を残さず、`minValue` / `maxValue` は `null`（値域なし）に、`enabled` は `true` に戻ります。止めている枠や値域を持つ枠を `PUT` で流すときは、`enabled: false` や `minValue` / `maxValue` も毎回送ってください。一部のフィールドだけを変えるなら `PATCH` を使います。`PATCH` で値域を変えるときも、`minValue` と `maxValue` を両方送ります。**

**`DELETE` は枠と一緒に、その枠に投稿されたエントリもすべて消します。元に戻せません。投稿を止めるだけなら `PATCH` か `PUT` で `enabled: false` にしてください。**

一覧の応答は `{ leaderboards: [...] }`、作成・`PUT`・`PATCH` の応答は `{ leaderboard }`、`DELETE` の応答は `{ deleted: true }` です。定義には上の表のフィールドに加えて `id`・`gameId`・`createdAt`・`updatedAt` が入ります。`PATCH` と `DELETE` の `:leaderboardId` は、この `id` です（`key` ではありません）。

`anomalies` の応答は `{ anomalies: [...] }` で、印の新しい順に 200 件までです。各項目は `entryId`・`leaderboardKey`・`leaderboardTitle`・`pseudoId`（プレイヤーの仮名の id）・`value`・`status`（`visible` / `hidden`）・`reason`（印を付けた理由）・`flaggedAt` を持ちます。印は記録だけで、エントリは自動では隠れません。

1ゲームあたり 20 枠までです。投稿が1件でもある枠では `sort` / `valueType` / `aggregation` / `period` を変えられません（`409`）。コマンドの例と注意は [SDK ガイドの API トークン](api-tokens.md#api-tokens) にあります。

<a id="analytics"></a>
## アナリティクス

`GET /api/analytics/games/:id` で、Studio のアナリティクス画面の「概要」と「パフォーマンス」と同じ数字をゲーム1本ぶん取れます。「プレイ時間と離脱」の数字は下の `GET /api/analytics/games/:id/engagement` で、「ファネル」の数字は `GET /api/analytics/games/:id/funnels` で、「カスタムイベント」の数字は `GET /api/analytics/games/:id/events` で、「エコノミー」の数字は `GET /api/analytics/games/:id/economy` で取ります。権限はどれも `analytics:read` です。

```bash
curl "https://gamerush.jp/api/analytics/games/$GAME_ID?period=7d" \
  -H "Authorization: Bearer $GRUSH_TOKEN"
```

`period` は `24h` / `7d` / `28d`（既定）/ `90d` / `all` です。

| フィールド | 内容 |
|---|---|
| `game` | `validPlays`（有効プレイ数）・`uniquePlayers`・`totalSessions`・`avgDurationSec`・`opens`・`skips`・`likeCount`・`commentCount`・`retention`（翌日の再訪率と 7 日後の再訪率） |
| `series` | `bucket` ごとの `plays` / `sessions` / `durationSec`。期間に応じて1時間・6時間・1日で区切る |
| `performance` | 端末で測った `load`（ロード時間。`samples`・`players`・`avgMs`・`minMs`・`p95Ms`（95% の読み込みが収まる時間）・`outcomePlayers`・`outcomes`・`abandoned`・`abandonRate`（途中離脱率））と `fps`（フレームレート。`sessions`・`players`・`sampledSec`・`avgFps`・`p10Fps`・`lowFpsShare`）と `memory`（ゲームが使うメモリの見積もりの、プレイごとの最大値。`sessions`・`players`・`p50Bytes`（中央値のバイト数）・`p90Bytes`（90% のプレイが収まるバイト数）・`highShare`（600MB 以上のプレイの割合）・`criticalShare`（1000MB 以上のプレイの割合）。MB は 1024 × 1024 バイト。見積もりは WebGL の画像・頂点データと描画領域の大きさから計算する目安で、wasm や JavaScript のヒープなどを数えない一方で多めに数える分もあり、実際の使用量とは上にも下にもずれる）。標本が少ないうちは件数だけを返し、各値が `null` になる。`memory` は、セッションが 5 未満か人数が 3 人未満なら件数と人数のほかを `null` にする。`load` は、ロード時間の人数（`players`）が 3 人未満なら `avgMs`・`minMs`・`p95Ms` を、途中離脱の人数（`outcomePlayers`）が 3 人未満なら `outcomes`・`abandoned`・`abandonRate` を `null` にする。`load`・`fps`・`memory` は、集計に失敗すると `source` が `failed` か `unavailable` になり、ほかの値を持たない |
| `surfaces` | 面ごとの数。`{ source, feed, home, external, feature, search, browseSince, series }` の形で、`feed` は `landings`（着地数）・`plays`（1秒以上遊ばれた数）・`minutePlays`（1分以上遊ばれた数）・`validPlays`、`home` は `clicks`（クリック数）・`plays`・`minutePlays`・`validPlays`・`impressions`（カードの表示数。取れないときは `null`）・`impressionsSince`（表示数を記録し始めた時刻。まだ記録が無ければ `null`）、`external`（プラットフォームの外から作品に直接着地した回）は `landings`・`plays`・`minutePlays`・`validPlays` と入口ごとの `byEntry`（`share`（シェアリンク）/ `sharePage`（ゲームが作った共有のページ。集計できないときは `null`）/ `direct` / `embed`（ほかのサイトに置いた埋め込み。`plays`・`minutePlays` も持つ。集計できないときは `null`）/ `other` ごとの `landings`・`validPlays`）、`feature`（特集タブ）と `search`（検索の結果）はどちらも `impressions`（カードの表示数）・`impressionsSince`（その面の表示数を記録し始めた時刻。まだ記録が無ければ `null`）・`clicks`（その面から遊び始めた数）・`validPlays`・`countedClicks`（`clicks` のうち `impressionsSince` より後に始まった数）で、集計できないときは `null`。`feed`・`home`・`external` はどれも、フィードの閲覧モードの `browseViews`（カードが画面に出た数）・`browseClicks`（そこからプレイへ移った数）・`clickedValidPlays`（そのうち有効プレイになった数）も持つ。`browseSince` は閲覧モードの表示を記録し始めた時刻で、まだ記録が無ければ `null`。`series` は `bucket` ごとの `feedLandings`・`feedValidPlays`・`homeClicks`・`homeValidPlays`・`homeImpressions`・`externalLandings`・`externalValidPlays`・`homePlays`・`feedPlays`・`externalPlays`・`homeMinutePlays`・`feedMinutePlays`・`externalMinutePlays` と、面ごとの `homeBrowseViews`・`homeBrowseClicks`・`homeClickedValidPlays`・`feedBrowseViews`・`feedBrowseClicks`・`feedClickedValidPlays`・`externalBrowseViews`・`externalBrowseClicks`・`externalClickedValidPlays` で、記録のある区切りだけを持つ。閲覧モードの数と `plays`・`minutePlays` は、集計できないときは `null`。`source` が `unavailable` / `failed` のときは数を返さない |
| `engagementSeries` | `{ source, series, d1Days }` の形で、`series` は `bucket` ごとの `uniquePlayers` / `opens` / `likes` / `comments` / `follows`（その作品の画面から付いたフォローの数。集計の無い DB では null）。`d1Days` は初めにプレイした UTC の日（`day`）ごとの 1日後 リテンションの対象の人日（`cohort`）と、そのうち翌日も遊んだ人日（`retained`）で、翌日が終わった日だけを持ち、集計の無い DB では null。`source` が `unavailable` / `failed` のときは `series` と `d1Days` を持たない |
| `period` / `generatedAt` | 集計の期間と、集計した時刻 |

ホーム・特集タブ・検索の表示数は記録を始めた時刻から後だけを数えます。期間の始まりが `impressionsSince` より前のときは、表示数は期間の一部しか数えておらず、期間の全部を数えたクリック数と割り合わせると率が高く出ます。特集タブと検索の CTR は `countedClicks` を表示数で割ってください。

閲覧モードの `browseViews`・`browseClicks`・`clickedValidPlays` も、記録を始めた時刻（`browseSince`）から後だけを数えます。期間の始まりが `browseSince` より前のときは、3つとも期間の一部しか数えていません。数はどれもセッションの開始時刻で期間と区切りを切るので、`browseClicks` は `browseViews` を、`clickedValidPlays` は `browseClicks` を超えません。

有効プレイは、遊び始めてから 1 分（60 秒）以上続いたプレイだけを数えます。ユニークプレイヤー数は 10 秒以上遊んだ人を数えます。ロード時間の数字は [ゲームの最適化ガイド](optimization.md) の効き目を確かめるのに使えます。

`GET /api/analytics/games/:id/engagement` で、Studio の「プレイ時間と離脱」と同じ数字を取れます。プレイヤーがどこで遊ぶのをやめるかを、経過時間ごとの割合で返します。`period` は上と同じです。

```bash
curl "https://gamerush.jp/api/analytics/games/$GAME_ID/engagement?period=7d" \
  -H "Authorization: Bearer $GRUSH_TOKEN"
```

| フィールド | 内容 |
|---|---|
| `engagement` | `sessions`・`firstSessions`・`players` と、`sessionCurve`・`firstSessionCurve`・`playerCurve`（`edgesSec` の各秒の時点でまだ遊んでいた割合）・`p50Sec` / `p75Sec` / `p90Sec`（1回のプレイ時間）・`avgPlayerSec`・`funnel`（`opened` → `revealed` → `played1s` → `played10s`）。標本が少ないうちは件数だけを返し、値は `null` |
| `series` | `{ source, points }` の形で、`points` は `bucket` ごとの `sessions` / `players` / `durationSec` / `medianSec`。区切りは上の `series` と同じ |
| `edgesSec` | 曲線の横軸の秒。60 分以上は最後の点にまとめる |
| `scope` | 数えた範囲。作者・共同制作者・運営のプレイは含まない |

曲線・分位・平均と `series` が数えるのは、プレイモードでゲームの表示を待ち始め、その回のうちに読み込みが終わった回だけです。待ち始めた後で閲覧モードへ戻った回は入り、閲覧モードで通り過ぎただけの回は入りません。`funnel.opened` だけは、表示の前に離れた回も数えます。`engagement` と `series` は、集計に失敗すると `source` が `failed` か `unavailable` になり、ほかの値（`series` では `points`）を持ちません。

`GET /api/analytics/games/:id/funnels` で、Studio の「ファネル」と同じ数字を取れます。ゲームが SDK から送ったファネルのステップを、ステップごとの到達と離脱で返します。`period` は上と同じです。`funnel` は `onboarding` か `recurring:` に続けたファネルの名前で、省くか、一覧に無い値なら一覧の先頭のファネルを返します。

```bash
curl "https://gamerush.jp/api/analytics/games/$GAME_ID/funnels?period=28d&funnel=recurring:Shop" \
  -H "Authorization: Bearer $GRUSH_TOKEN"
```

| フィールド | 内容 |
|---|---|
| `list` | `hasEvents`（期間を問わず、数える範囲のイベントが届いたことがあるか）・`hasAnyEvents`（作者・共同制作者・運営のものも含めて届いたことがあるか）・`funnels`（`funnel`・`units`・`players`）・`other`（一覧に入れなかったファネルの `funnels` と `players`。無ければ `null`） |
| `report` | 選んだファネルの `funnel`・`units`・`players`・`steps`・`biggestDropStep`（前のステップからの率がいちばん低いステップ）。期間に始めた回のあるファネルが無ければ `source` が `none` |
| `playersBasis` | 人数の数え方。`period` は期間の中で重なりを除いた人数、`peak` は期間の人数の下限（下の注記）。`recurring` のファネルの `players` に効き、`onboarding` は `peak` でも重なりの無い人数 |
| `report.steps` | `step`・`name`・`reached`・`reachedPlayers`・`fromStartRate`・`fromPreviousRate`・`dropped`。`onboarding` は `playSec`（届いたときの累計プレイ秒の `p25` / `p50` / `p75` / `p90`）と `medianDays`、`recurring` は `medianElapsedSec`（回を始めてからの秒）。分位と中央値は人ごとの値の上で取る |
| `scope` | 数えた範囲。作者・共同制作者・運営のイベントは含まない |
| `collecting` | ゲームからの分析イベントを今保存しているか。`false` の間は送ったイベントが残らない |

`onboarding` は人で、`recurring` は人と `funnelSessionId` の組（省いたステップはプレイセッション）を1回として数えます。期間の中で始めた回だけを数え、その回のステップは今までの到達をすべて数えます。先のステップに届いた回は、飛ばした手前のステップにも届いたと数えます。ファネルの名前は人数の多い上位 10 個まで返し、3人未満のファネルは `other` にまとめます。3人未満しか送っていないステップ名は `null` に、到達した人が5人未満のステップの時間は `null` になります。`list` と `report` は、集計に失敗すると `source` が `failed` か `unavailable` になります。

`playersBasis` が `peak` のとき、期間の人数（`players` など）は重なりを除いた実際の人数ではなく、その下限です。期間の中で人数のいちばん多い日か、期間にまるごと入る月の人数の大きいほうを出します。実際の人数はこれ以上で、人数で割った値は実際より大きく出ます。どちらの数え方になるかは期間で変わります。

`GET /api/analytics/games/:id/events` で、Studio の「カスタムイベント」と同じ数字を取れます。ゲームが SDK から送ったカスタムイベントを、イベント名ごとの指標・推移・custom field ごとの内訳で返します。`period` は上と同じです。`event` はイベント名で、省くか、一覧に無い値なら一覧の先頭のイベントを返します。`field` は内訳に使う custom field のキーで、省くか、選べないキーなら内訳を返しません。

```bash
curl "https://gamerush.jp/api/analytics/games/$GAME_ID/events?period=28d&event=level_clear&field=stage" \
  -H "Authorization: Bearer $GRUSH_TOKEN"
```

| フィールド | 内容 |
|---|---|
| `list` | `hasEvents`・`hasAnyEvents`（`funnels` と同じ）・`events`（`key`・`count`・`players`）・`other`（一覧に入れなかったイベント名の `events`・`count`・`players`。無ければ `null`） |
| `report` | 選んだイベントの `event`・`totals`・`series`（`bucket` ごとの指標）・`fields`（内訳に選べるキー。人数の多い上位 20 個まで）・`breakdown`。名前を出せるイベントが期間に無ければ `source` が `none` |
| `playersBasis` | 人数の数え方。`funnels` と同じ。`peak` のときは、期間の `totals` と内訳の行の `perPlayer` が `null` になる |
| `指標` | `count`（回数）・`sum`（value の合計）・`players`（人数）・`avg`・`min`・`max`（人ごとの value の平均の、平均・最小・最大）・`perPlayer`（合計を人数で割った値） |
| `report.breakdown` | `field`・`values`（`value` と指標）・`other`（`values` に入れなかった値をまとめた指標）・`otherValues`（その値の種類の数）・`unset`（そのキーを持たないイベントの指標） |
| `scope` | 数えた範囲。作者・共同制作者・運営のイベントは含まない |
| `collecting` | ゲームからの分析イベントを今保存しているか。`false` の間は送ったイベントが残らない |

期間の中に送られたイベントを数えます。イベント名は人数の多い上位 100 個まで返し、3人未満のイベント名は `other` にまとめます。custom field のキーと値も3人未満のものは名前を出さず、値は上位 20 個まで返して残りを `breakdown.other` にまとめます。`sum`・`avg`・`min`・`max`・`perPlayer` は、対象の人数が5人未満なら `null` になります。推移の区切りと内訳の行（`other` を含む）も、それぞれの人数で同じです。期間の `sum` から見えている区切りや行の `sum` を引いて隠した値が戻るときは、人数のいちばん少ない区切りや行の `sum` と `perPlayer` も `null` にします。`list` と `report` は、集計に失敗すると `source` が `failed` か `unavailable` になります。

`GET /api/analytics/games/:id/economy` で、Studio の「エコノミー」と同じ数字を取れます。ゲームが SDK から送った通貨の入手（source）と消費（sink）を、通貨ごとの合計・日ごとの推移・所持・内訳で返します。`period` は上と同じです。`currency` は通貨の名前で、省くか、一覧に無い値なら人数のいちばん多い通貨を返します。

```bash
curl "https://gamerush.jp/api/analytics/games/$GAME_ID/economy?period=28d&currency=Gold" \
  -H "Authorization: Bearer $GRUSH_TOKEN"
```

| フィールド | 内容 |
|---|---|
| `list` | `hasEvents`・`hasAnyEvents`（`funnels` と同じ）・`currencies`（`currency`・`players`）・`other`（一覧に入れなかった通貨の `currencies` と `players`。無ければ `null`） |
| `report` | 選んだ通貨の `currency`・`players`・`sourcePlayers`・`sinkPlayers`・`totals`（`source`・`sink`・`net`）・`latestBalance`（人ごとの期間の中の最後の所持の `p50` / `p90`）・`days`・`breakdown`。期間に行のある通貨が無ければ `source` が `none` |
| `playersBasis` | 人数の数え方。`funnels` と同じ |
| `report.days` | UTC の日ごとの `day`・`source`・`sink`・`net`・`players`・`sourcePlayers`・`sinkPlayers`・`balanceAvg`（人ごとのその日の最後の所持の平均）。行の無い日は `players` が 0 で、量は 0、`balanceAvg` は `null`。期間を区切ると、最初の日は期間の始まりの時刻から後だけを数える |
| `report.breakdown` | `transactionType` と `itemSku` のそれぞれに、`source` と `sink` ごとの `items`（`name`・`amount`・`players`）と `other`（`names`・`amount`・`players`）。品目を送らなかった行の `name` は `null` |
| `scope` | 数えた範囲。作者・共同制作者・運営のイベントは含まない |
| `collecting` | `funnels` と同じ |

量はどれも正の値で、`net` は入手から消費を引いた値です。量と所持はゲームが送った値のままで、GameRush は確かめません。通貨は人数の多い上位 10 個まで、取引の種類と品目は入手と消費のそれぞれで人数の多い上位 20 個まで返し、3人未満の名前は `other` にまとめます。`latestBalance` は人数が5人未満なら `null`、`balanceAvg` はその日の人数が5人未満なら `null` です。量（`totals`・`days` の `source` / `sink`・内訳の `amount`）も、入手（消費）した人が5人未満なら `null` で、`net` は入手と消費の両方を出せるときだけ値を持ちます。隠した量を同じ応答の合計から引き算で戻せないよう、和の関係（期間の合計 ↔ `days`、期間の合計 ↔ 内訳の行と `other`）の中で隠した値が1つだけになるときは、人数が最小のほかの値も `null` にします。期間の違う2つの応答の差からは戻せることがあります。`list` と `report` は、集計に失敗すると `source` が `failed` か `unavailable` になります。
