# 作者かどうか

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#creator

<a id="creator"></a>
## 作者かどうか

自分のプレイヤーを読むと、遊んでいる人がそのゲームのオーナーか、承諾済みの共同制作者かが分かります。GameRush が決める値で、ゲームからは変えられません。デバッグメニューのような、作者にだけ見せる表示の出し分けに使えます。

```csharp
// Unity
var self = await GRush.Player.GetSelfAsync();
if (self.Ok && self.Value.IsCreator)
{
    debugMenu.SetActive(true);
}
```

```gdscript
# Godot
var self_result: Dictionary = await GRush.player.get_self()
if self_result["ok"] and self_result["value"]["is_creator"]:
    debug_menu.show()
```

```javascript
// JavaScript
const self = await GRush.player.getSelf();
if (self.ok && self.value.isCreator) showDebugMenu();
```

**権限としては使わないでください。ゲームは遊ぶ人のブラウザで動くので、書き換えれば作者でなくても作者に見せられます。アイテムの付与やスコアのように守りたいことを、この値だけで許さないでください。課金のテストには、GameRush が作者かどうかを確かめるテスト購入を使ってください（[アイテムの販売](shop.md#shop)）。**

- ゲストは常に作者ではありません。
- 共同制作者を承諾したときと外したときは、反映に最大 30 秒ほどかかります。
- Unity `v1.20.0`・Godot `v1.17.0`・JavaScript `v0.20.0` 以降の SDK で読めます。
- エディタのモックは、既定で作者として返します。Unity は `GRushMock.IsCreator`、Godot は `GRushMock.is_creator`、JavaScript は `GRush.mock.config.isCreator` を `false` にすると、作者でない人として試せます。

| 値 | Unity | Godot | JavaScript |
|---|---|---|---|
| 作者か | `GRushPlayer.IsCreator` | `get_self()["value"]["is_creator"]` | `getSelf().value.isCreator` |
