# API トークン

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#api-tokens ・ https://gamerush.jp/developers/api#loopback

<a id="api-tokens"></a>
## API トークン

Studio の **API トークン** から資格情報を発行すると、ランキングの宣言・ゲームの作成と設定変更（サムネイル・実況ポリシー・公開設定など）・ビルドのアップロード・アナリティクスの取得・ゲーム内アイテムの商品の登録を HTTP で行えます。CI から流しても構いません。エンドポイントごとの詳細は [API リファレンス](http-api.md) にあります。

**トークンをゲームのビルドへ入れないでください。ビルドに入れたものは公開したのと同じで、出回った後は取り消せません。**

置き場所はエンジンプロジェクトの外側、つまり手元の環境変数か CI のシークレットです。

- [GameRush Studio](https://gamerush.jp/studio) の **API トークン** から発行する
- 権限は要るものだけ選ぶ（宣言だけなら `leaderboards:read` と `leaderboards:write`。ゲーム ID を調べるなら `games:read`）
- 対象のゲームを絞れる。絞ったトークンを他のゲームへ向けると `404` になる
- **平文が出るのは発行直後の一度だけ。失くしたら失効させて出し直す**

| 権限 | できること |
|---|---|
| `games:read` | ゲームの一覧と1本の取得 |
| `games:create` | ゲームの新規作成（**特権**） |
| `games:write` | 作成後の設定変更。タイトル・説明・元 URL・サムネイル（正方形・16:9・9:16）・実況ポリシー・公開設定（**特権**） |
| `builds:write` | ビルドの作成とアップロード（**特権**）。最上位に `grush.json` を含むビルドは `leaderboards:write` も要る |
| `leaderboards:read` | ランキング定義の一覧 |
| `leaderboards:write` | ランキング定義の作成・更新・削除 |
| `analytics:read` | ゲーム別アナリティクスの取得 |
| `shop:write` | ゲーム内アイテムの商品の登録と、名前・価格・販売中かの変更（**特権**）と、収益の分け方の読み取り。自分がオーナーか承諾済みの共同制作者のゲームで、運営がオーナーの販売を開いているときだけ。分け方を変えることは API キーではできない |

特権の4つは、作品そのものを増やす・差し替える・プレイヤーに見える姿を変える権限と、売り物の値段を変える権限です。発行画面と承認画面で印が付くので、渡す相手をよく確かめてください。

```bash
curl -X PUT "https://gamerush.jp/api/games/$GAME_ID/leaderboards/high_score" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"ハイスコア","sort":"desc","valueType":"int","aggregation":"best","period":"all_time","minValue":0,"maxValue":1000000}'
```

`PUT` は `key` での冪等な適用です。無ければ作り、あって内容が違えば更新し、同じ内容なら何もしません。同じコマンドを何度流しても結果は変わらないので、宣言をリポジトリのスクリプトに置いて毎回流して構いません。

- 一覧は `GET /api/games/$GAME_ID/leaderboards`、ゲーム ID は `GET /api/games` で取れる
- 投稿が1件でもある枠では `sort` / `valueType` / `aggregation` / `period` を変えられない（`409`）。保存済みの値の意味が後から変わるため。変えたいときは別の key を作る。同じ値を流し直す分は変更ではないので通る
- 値域（`minValue` / `maxValue`）は両方揃って初めて意味を持つ。宣言が無い枠は投稿を受け付けない

<a id="loopback"></a>
### 自分のツールから取る（loopback 承認）

Unity を使うなら自分で実装する必要はありません。[Unity Editor からアップロードする](editor-upload.md#editor-upload) の Editor 拡張がこの手順を持っています。ここは自前の CLI やエディタ拡張を書く人向けです。

ターミナルからビルドを上げるなら、[grush-sdk-js](https://github.com/gamerush-jp/grush-sdk-js) に付いている `grush` コマンドもこの手順を持っています。`grush login` でブラウザ承認してトークンを保存し、`grush upload <フォルダか zip> --game <ゲーム ID>` で上げます（`--new <タイトル>` なら `private` のゲームを作ってから上げます）。Node.js 20 以上で `npx -p github:gamerush-jp/grush-sdk-js grush login` のように動かせ、CI では Studio で発行したトークンを環境変数 `GRUSH_TOKEN` に入れて使えます。フォルダの中身をそのまま上げるので、Unity と Godot のビルドを GameRush のプレイヤーで起動させるには Editor 拡張か Studio から上げてください。使い方はリポジトリの README にあります。

手元でループバックのサーバを立てて `/studio/authorize` を開き、承認後に戻ってきたコードを交換します（[RFC 8252](https://www.rfc-editor.org/rfc/rfc8252) + PKCE）。手順とパラメータは [API リファレンスの loopback 承認](api-tokens.md#loopback) にあります。

- `redirect_uri` は `http://127.0.0.1:<port>` / `http://localhost:<port>` / `http://[::1]:<port>` だけ。ポートは任意で、クエリもフラグメントも付けられない
- `code_challenge_method` は `S256` のみ。`code_verifier` は 43〜128 文字
- コードはワンタイムで 5 分。`code_verifier` が合わない交換ではコードを使い切らないので、5 分以内なら正しい `code_verifier` でやり直せる
- こうして取ったトークンは Studio の一覧に発行元のクライアント名つきで並ぶので、手発行と見分けられる
- `games:create` はゲームの許可リストと併用できない（発行時に `400`、使用時に `403`）。まだ無いゲームは許可リストに載せられないため

<a id="loopback"></a>
## 自分のツールからトークンを取る

作者に Studio でトークンを発行して貼ってもらう代わりに、ブラウザで承認してもらって自分のツールがトークンを受け取る形も取れます（[RFC 8252](https://www.rfc-editor.org/rfc/rfc8252) のループバック + PKCE）。Unity の Editor 拡張はこの形です。

- ツールが手元で `http://127.0.0.1:<port>` の HTTP サーバを立て、`code_verifier`（`A-Z` `a-z` `0-9` と `.` `_` `~` `-` だけからなる 43〜128 文字のランダムな文字列）を作る
- ブラウザで下の URL を開く。作者がログインして内容を確かめ、承認ボタンを押す
- ブラウザが `redirect_uri?code=…&state=…` へ戻ってくる。`state` が送ったものと同じか確かめる
- `exchange` に `code` と `code_verifier` を送り、トークンを受け取る

```bash
https://gamerush.jp/studio/authorize
  ?redirect_uri=http://127.0.0.1:53682
  &code_challenge=<base64url(sha256(code_verifier))>
  &code_challenge_method=S256
  &client_name=My%20Build%20Tool
  &scopes=games:read,builds:write
  &state=<ランダムな値>
```

```bash
curl -X POST "https://gamerush.jp/api/api-token-authorizations/exchange" \
  -H "Content-Type: application/json" \
  -d '{"code":"<戻ってきた code>","codeVerifier":"<code_verifier>","redirectUri":"http://127.0.0.1:53682"}'
```

- `redirect_uri` は `http://127.0.0.1:<port>` / `http://localhost:<port>` / `http://[::1]:<port>` だけです。クエリもフラグメントも付けられません。
- `code_challenge_method` は `S256` だけです。
- `scopes` はカンマ区切りです。`game_ids` にゲーム ID をカンマ区切りで渡すと、トークンの対象をそのゲームに絞れます。50 件までで、`games:create` とは一緒に使えません。
- `state` は任意で、200 文字までです。200 文字を超えた `state` はエラーにならずに捨てられ、ブラウザは `state` を付けずに戻ってくるので、ツールの側の照合が失敗します。
- `client_name` は承認画面と Studio のトークン一覧に出ます。60 文字を超えた分は切り詰められ、改行と制御文字は空白になります。
- `code` はワンタイムで 5 分です。`code_verifier` か `redirectUri` が合わない交換は `code` を消費しないので、5 分以内なら正しい値で `exchange` をやり直せます。
- `exchange` の失敗は、`code` の期限切れ・使用済み・`code_verifier` の不一致・形の誤りのどれでも、`400` `Invalid authorization code.` です。
- 応答は `{ token, secret }` で、`secret` がトークンの本体です。有効期限は 90 日です。有効なトークンが 20 本あると `409` になります。このときも `code` は消費されないので、Studio でトークンを1本失効させてから、5 分以内なら同じ `code` で `exchange` をやり直せます。
