# HTTP API の約束

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/developers/api#overview

作者の手元・CI・エディタ拡張から、ゲームの作成と設定変更・サムネイルとビルドのアップロード・ランキングの宣言・アナリティクスの取得・ゲーム内アイテムの商品の登録を行う HTTP API です。

ゲームの中から呼ぶ API（ランキングへの投稿・公開プレイヤー状態・[リアルタイムマルチプレイ](multiplayer.md#multiplayer)）は [SDK ガイド](../AGENTS.md) を見てください。

<a id="overview"></a>
## はじめに

API はすべて `https://gamerush.jp/api/` の下にあります。本文は JSON で送り、応答も JSON で返ります。成功は `200` です（商品の作成だけ `201`）。

認証は、[Studio](https://gamerush.jp/studio) の **API トークン** で発行したトークンを `Authorization: Bearer` に載せるだけです。発行のしかた・権限の選び方・置き場所の注意は [SDK ガイドの API トークン](api-tokens.md#api-tokens) にあります。

```bash
export GRUSH_TOKEN="grush_pat_..."
curl "https://gamerush.jp/api/games" \
  -H "Authorization: Bearer $GRUSH_TOKEN"
```

**トークンをゲームのビルドへ入れないでください。ここにある API は、作者の手元・CI・エディタ拡張から呼ぶためのものです。**

- トークンで呼べるのは、このページに載っている API だけです。アカウントの操作・コメント・フォローなどは、トークンでは `401` になります。
- トークンから新しいトークンは発行できません。
- 運営の管理権限はトークンには乗りません。管理者が発行したトークンでも、触れるのは本人がオーナーか共同制作者のゲームだけです。

<a id="errors"></a>
### エラーの形

失敗すると、`error`（英語の説明文）と `code`（機械で読める識別子）の片方か両方を持つ JSON が返ります。`code` には `params` が添えられることがありますが、付かないこともあります。`details` が付くこともあります。

```json
{ "error": "API token is missing the games:write scope." }
{ "code": "build.tooManyFiles", "params": { "limit": 2000 } }
{ "error": "This feature is temporarily unavailable.", "code": "service.featureDisabled", "params": { "feature": "uploads" } }
```

| HTTP | よくある原因 |
|---|---|
| 400 | リクエストの形が違う（必須の項目が無い、ビルドのファイル一覧の形が違う、パスのゲーム・ビルド・ランキングの id が UUID の形でない など） |
| 401 | トークンが無い・形が違う・期限切れ・失効済み |
| 403 | トークンに必要な権限が無い。規約や素材の権利への同意が無い。アカウントがゲームの投稿を止められている（`post.banned`） |
| 404 | ゲームが無い。トークンの対象ゲームに入っていない。自分がオーナーでも共同制作者でもない |
| 409 | 状態がぶつかった（審査の途中で変わった、同じ key が既にある など）。作成の冪等キーで先の要求が終わっていない（`operation.inProgress`。少し待って同じキーで送り直す） |
| 410 | 作成の冪等キーで先に作ったものが消されたか、ビルドが失敗している（`operation.gone`。新しいキーで作り直す） |
| 422 | アップロードしたビルドの中身の検査で弾かれた。作成の冪等キーを違う本文で使った（`operation.bodyMismatch`） |
| 503 | サービス全体を止めている（`service.suspended`）か、アップロードの機能を止めている（`service.featureDisabled`、`params.feature` が `uploads`）。ビルドの完了の一時的な失敗でも返る |

アップロードの機能を止めている間に `503` になるのは、ゲームの作成（`POST /api/games`）、ビルドの作成（`POST /api/games/:id/builds`）と完了（`POST /api/builds/:id/complete`）、サムネイルなど画像の項目を含む `PATCH /api/games/:id` です。読み取りと、画像を含まない設定の変更は通ります。

**止めているときの `503` の応答には `Retry-After: 300` が付きます。止めている間は何度呼んでも同じなので、すぐに再試行せず、`Retry-After` の秒数だけ待ってから呼び直してください。`Retry-After` の無い `503` は一時的な失敗で、少し待てば呼び直せます。**

対象ゲームを絞ったトークンを他のゲームへ向けたときは、存在を漏らさないために `403` ではなく `404` になります。
