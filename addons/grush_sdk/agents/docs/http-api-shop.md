# HTTP API: アイテムの商品

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/developers/api#shop

<a id="shop"></a>
## アイテムの販売

ゲームの中で売るアイテムの商品を、作者の手元から登録・管理する API です。商品の種類は、同じプレイヤーが 1 回だけ買える買い切り（`permanent`）と、何度でも買える消費（`consumable`）の 2 つです。消費のアイテムは、ゲーム内通貨（ほかのアイテムや機能と交換する対価）や抽選（ガチャなど、偶然で中身が決まる仕組み）に使えません（販売に関する取り決めの第5条）。

使えるのは、自分がオーナーか承諾済みの共同制作者のゲームです。ゲームを売れるかはオーナーで決まり、運営がオーナーの販売を開いていないゲームと、オーナーかあなたのアカウントが止められているときは `403`（`shop.notEnabled`）になります。

商品を足す・名前や価格を変える・販売を再開するには、オーナーが Studio のゲームの「アイテム販売」で、販売に関する取り決めの今の版に同意しておく必要があります。共同制作者が呼んでも、見るのはオーナーの同意です。同意していないと `403`（`shop.agreementRequired`）になります。同意は API キーではできません。一覧を読むことと、`active: false` だけを送って販売をやめることは、同意していなくてもできます。

| API | 権限 | 内容 |
|---|---|---|
| `GET /api/games/:id/shop/catalog` | `shop:write` | 商品の一覧（販売をやめた商品も含む） |
| `POST /api/games/:id/shop/catalog` | `shop:write` | 商品を足す。成功は `201`。同じ `sku` があれば `409`（`shop.skuTaken`） |
| `PATCH /api/games/:id/shop/catalog/:sku` | `shop:write` | 送ったフィールドだけ更新。`sku` と `type` は変えられず、本文に `type` があれば `400`。無い商品は `404` |
| `GET /api/games/:id/shop/revenue-split` | `shop:write` | 収益の分け方（作者の取り分を、オーナーと共同制作者で分ける割合）。共同制作者には自分の割合だけを返す |
| `PUT /api/games/:id/shop/revenue-split` | Studio のログインだけ | 分け方を変える。オーナーだけが Studio のゲームの「アイテム販売」で行い、API キーでは scope によらず `403` |

```bash
curl -X POST "https://gamerush.jp/api/games/$GAME_ID/shop/catalog" \
  -H "Authorization: Bearer $GRUSH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sku":"sword","name":"剣","priceJpy":500}'
```

| フィールド | POST | PATCH | 値 |
|---|---|---|---|
| `sku` | 必須 | パスで渡す | 英小文字・数字と `_` `.` `-` で 64 文字まで。先頭は英小文字か数字。ゲームの中でアイテムを見分ける値 |
| `name` | 必須 | 任意 | 1〜30 文字。改行は空白になる |
| `priceJpy` | 必須 | 任意 | 税込みの円。100・120・300・500・1000・2000・3000・5000 のどれか（アプリ内課金の価格） |
| `type` | 任意 | — | `permanent`（買い切り）か `consumable`（消費）。省くと `permanent`。足した後は変えられない |
| `active` | — | 任意 | `false` で販売をやめる。足した商品は販売中から始まる |

**商品は消せません。売るのをやめるときは `PATCH` で `active: false` にしてください。買われたアイテムは、販売をやめた後もプレイヤーの手元に残ります。**

一覧の応答は `{ products: [...] }`、作成と `PATCH` の応答は `{ product }` です。商品は上の表のフィールドに加えて `productId`・`createdAt`・`updatedAt` を持ちます。本文は 4KB までで、超えると `413` です。

運営が販売の機能を止めている間は、どれも `503`（`service.featureDisabled`、`params.feature` が `shop`）になります。
