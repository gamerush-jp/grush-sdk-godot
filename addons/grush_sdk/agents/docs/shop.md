# アイテムの販売

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#shop

<a id="shop"></a>
## アイテムの販売

作者が値段を決めたゲーム内アイテムを、プレイヤーが買えます。商品の sku（英小文字・数字と `_` `.` `-` の 64 文字まで）・名前・価格・種類は、[GameRush Studio](https://gamerush.jp/studio) か API キーで登録します。ゲームは商品の一覧を読んで、購入を呼ぶだけです。エディタやローカルで試すモックに商品を置くときも、価格は GameRush で付けられる価格から選びます（Unity は `GRushShopPrice`、Godot は `GRush.ShopApi.Price`、JavaScript は `GRush.SHOP_PRICES_JPY`）。

| 種類（type） | 買える回数 | 持っているアイテムのすべて（owned） |
|---|---|---|
| `permanent` | 買い切り。同じプレイヤーは、返金されない限り 1 回だけ | 入る |
| `consumable` | 消費。同じプレイヤーが何度でも | 入らない |

**種類は登録した後は変えられません。消費のアイテムを、ゲーム内通貨（ほかのアイテムや機能と交換する対価）として使うことと、アイテムを抽選（ガチャなど、偶然で中身が決まる仕組み）に使わせることは、販売に関する取り決めで禁じています。**

**GameRush が保証するのは、払ったプレイヤーにアイテムが届くことまでです。ゲームの中でのアイテムの使い方は、改ざんを防げません。**

```csharp
// Unity
// 起動時と、買い終えたときに、届いたアイテムを受け取る。
await ReceiveItemsAsync();

async Task ReceiveItemsAsync()
{
    var pending = await GRush.Shop.PendingAsync();
    if (!pending.Ok || pending.Value.Length == 0) return;
    foreach (var grant in pending.Value)
    {
        if (!save.AppliedGrants.Contains(grant.Id))
        {
            AddItem(save, grant.Sku);
            save.AppliedGrants.Add(grant.Id);
        }
    }
    // セーブを保存してから Ack する。
    if (SaveGame(save)) await GRush.Shop.AckAsync(pending.Value.Select(g => g.Id).ToArray());
}

// 買う: 先にセーブを保存する。
SaveGame(save);
var bought = await GRush.Shop.PurchaseAsync("potion.heal");
if (bought.Ok && bought.Value.Status == GRushShopPurchaseStatus.Purchased) await ReceiveItemsAsync();
```

```gdscript
# Godot
func _ready() -> void:
    receive_items()

func receive_items() -> void:
    var pending: Dictionary = await GRush.shop.pending()
    if not pending["ok"] or pending["value"].is_empty():
        return
    var ids: Array = []
    for grant in pending["value"]:
        if not save["applied_grants"].has(grant["id"]):
            add_item(save, grant["sku"])
            save["applied_grants"].append(grant["id"])
        ids.append(grant["id"])
    # セーブを保存してから ack する。
    if save_game(save):
        await GRush.shop.ack(ids)

# 買う: 先にセーブを保存する。
func buy(sku: String) -> void:
    save_game(save)
    var bought: Dictionary = await GRush.shop.purchase(sku)
    if bought["ok"] and bought["value"] == "purchased":
        await receive_items()
```

```javascript
// JavaScript
async function receiveItems() {
  const pending = await GRush.shop.pending();
  if (!pending.ok || pending.value.length === 0) return;
  for (const grant of pending.value) {
    if (save.appliedGrants.includes(grant.id)) continue;
    addItem(save, grant.sku);
    save.appliedGrants.push(grant.id);
  }
  // セーブを保存してから ack する。
  const saved = await GRush.cloudSave.save(save);
  if (saved.ok) await GRush.shop.ack(pending.value.map((grant) => grant.id));
}

// 起動時に受け取る。
await receiveItems();

// 買う: 先にセーブを保存する。買い終えたら受け取る。
await GRush.cloudSave.save(save);
const bought = await GRush.shop.purchase("potion.heal");
if (bought.ok && bought.value.status === "purchased") await receiveItems();
```

| 呼び出し | Unity | Godot | JavaScript |
|---|---|---|---|
| 商品の一覧 | `Shop.ProductsAsync()` | `shop.products()` | `shop.products()` |
| 買う | `Shop.PurchaseAsync(sku)` | `shop.purchase(sku)` | `shop.purchase(sku)` |
| 届いたアイテム（受け取り待ち） | `Shop.PendingAsync()` | `shop.pending()` | `shop.pending()` |
| 受け取りを確かめる | `Shop.AckAsync(ids)` | `shop.ack(ids)` | `shop.ack(ids)` |
| 持っているアイテムのすべて | `Shop.OwnedAsync()` | `shop.owned()` | `shop.owned()` |

アイテムの販売は `protocolVersion` 12 以上の GameRush で使えます。それより古い GameRush では、どの呼び出しも `Unsupported` です。Unity は `GRush.IsShopAvailable` で確かめられます。

### 取りこぼさない使い方

- 1. 購入を呼ぶ前にセーブを保存します。
- 2. 起動時と、購入の結果が `purchased` のときに、届いたアイテム（受け取り待ち）を読みます。結果が `pending` の購入は、支払いや承認が済むと受け取り待ちに入り、次に読んだときに届きます。
- 3. 届いたアイテムをセーブに反映して保存してから、その付与の ID で受け取りを確かめます（ack）。ack するまで、届いたアイテムは受け取り待ちに残ります。ack に渡せる ID は 1 回 1〜100 件です。
- 4. 反映済みの付与の ID をセーブに持ち、同じ付与を二度反映しないようにします。
- 機種を替えたときなど、セーブを組み直すときは、持っているアイテムのすべて（owned）を読みます。返金されたアイテムと、消費のアイテムは入りません。
- 消費のアイテムでは、ack は「ゲームへ届けた」ことだけを表します。owned で組み直せないので、届いたアイテムをセーブに反映して保存してから ack することと、反映済みの付与の ID をセーブに持つことが、買い切りのアイテムよりも大事です。保存の前に ack すると、保存に失敗したときに買ったアイテムが失われます。

### 買える場所と購入の結果

- アイテムは iOS のアプリで、App Store のアプリ内課金で買います。商品の価格は 100・120・300・500・1,000・2,000・3,000・5,000 円のどれかで、ほかの価格の商品は商品の一覧に出ません。
- Web の GameRush では、商品の一覧と、届いたアイテムの受け取り（受け取り待ち・ack・owned）が使えます。アプリで買ったアイテムも、同じアカウントなら Web で受け取れます。Web で購入を呼ぶと、GameRush はアイテムを iPhone・iPad のアプリで買えることと App Store へのリンクを出し、結果は `cancelled` です。サインインしていないプレイヤーにも同じく出します。
- Android のアプリと LINE では、商品の一覧・購入・届いたアイテムの受け取りのどれも `Unsupported` です。
- 購入を呼ぶと、GameRush がゲーム名・商品名・価格を出して、プレイヤーに確かめます。出す商品名と価格は、ゲームが渡した値ではなく、登録した商品の値です。確かめている間、ゲームは止まります。
- プレイヤーが購入をやめると、同じスライドではその後 5 秒の間、購入を呼んでも確かめずに `cancelled` です。60 秒のうちにまたやめると、その後の 20 秒の間 `cancelled` です。購入を 5 秒のうちに続けて呼んだときも、確かめずに `cancelled` です。プレイヤーがフィードを見ていてゲームが止まっている間の購入も `cancelled` です。
- iOS のアプリでゲストが購入を呼ぶと、GameRush がサインインを求め、結果は `SignInRequired` です。
- 販売していない商品は `Unavailable`、無い sku は `InvalidParams` です。
- ゲームの作者（オーナー・共同制作者）が自分のゲームで購入を呼ぶと、GameRush は「テスト購入（課金なし）」と「購入する（実際に課金）」を出します。テスト購入は課金されず売上にも数えず、アイテムがプレイヤーと同じく受け取り待ちに入り、結果は `purchased` です。購入するは、ほかのプレイヤーの購入と同じく実際に課金され、売上と取り分にも数えます。結果に、テスト購入かどうかと作者かどうかを示す値は載りません（作者かどうかは [作者かどうか](creator.md#creator) で読めます）。Web では「購入する」の代わりにアプリで買えることを出すので、Web で `purchased` が返るのはテスト購入のときだけです。
- 公開していないゲームでは、作者だけが商品の一覧を読め、購入を呼ぶと「テスト購入」だけが出ます。公開の前に、購入から受け取りまでの流れを確かめられます。作者でない人には販売していないものとして見えます。
- 運営が保留にしているゲームでは、販売していないものとして扱い、作者のテスト購入もできません。

| 購入の結果（status） | 意味 |
|---|---|
| `purchased` | 買い終え、アイテムが受け取り待ちに入った（iOS のアプリと、作者のテスト購入） |
| `pending` | 支払いの確認や保護者の承認を待っている。済むと受け取り待ちに入る（iOS のアプリ） |
| `cancelled` | プレイヤーが購入をやめた。Web で購入を呼んだとき |
| `alreadyOwned` | 同じ買い切りの商品をもう持っている。消費のアイテムでは返らない |

購入はプレイヤーが確かめるのを待つので、結果まで最大 10 分かかります。
