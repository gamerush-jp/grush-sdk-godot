# アナリティクス（ゲームから送るイベント）

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#analytics

<a id="analytics"></a>
## アナリティクス

ゲームの中で起きたことを送ると、[Studio](https://gamerush.jp/studio) の作品詳細のアナリティクスに集計が出ます。送れるのは、オンボーディングとファネルのステップ（「ファネル」のタブ）、ゲームが決めた出来事（「カスタムイベント」のタブ）、ゲーム内の通貨の入手と消費（「エコノミー」のタブ）です。Unity は v1.6.0、Godot は v1.5.0、JavaScript は v0.7.0 以降の SDK で使えます。導入の節の版（Unity `v1.22.0`・Godot `v1.19.0`・JavaScript `v0.23.0`）は、どれも対応しています。

**[共通の約束](sdk-basics.md#promises) の例外です。どの呼び出しも結果オブジェクトではなく真偽値を同期で返し、例外を投げません。待たずに、どこからでも呼べます。`true` は GameRush へ渡したことで、保存されたことではありません。**

```csharp
// Unity
GRush.Analytics.LogOnboardingStep(1, "tutorial_start");
GRush.Analytics.LogFunnelStep("shop", "visit-1", 2, "item_selected");
GRush.Analytics.LogCustomEvent(
    "boss_defeated",
    1,
    new Dictionary<string, string> { { "stage", "3" } }
);
GRush.Analytics.LogEconomyEvent(
    GRushEconomyFlowType.Sink,
    "coin",
    50,
    120,
    GRushEconomyTransactionType.Shop,
    itemSku: "sword"
);
```

```gdscript
# Godot
GRush.analytics.log_onboarding_step(1, "tutorial_start")
GRush.analytics.log_funnel_step("shop", "visit-1", 2, "item_selected", {"tab": "weapons"})
GRush.analytics.log_custom_event("boss_defeated", 1, {"stage": "3"})
GRush.analytics.log_economy_event(
    GRush.AnalyticsApi.FLOW_SINK, "coin", 50, 120, GRush.AnalyticsApi.TRANSACTION_SHOP, "sword"
)
```

```javascript
// JavaScript
GRush.analytics.logOnboardingStep(1, "tutorial_start");
GRush.analytics.logFunnelStep("shop", "visit-1", 2, "item_selected", { fields: { tab: "weapons" } });
GRush.analytics.logCustomEvent("boss_defeated", 1, { fields: { stage: "3" } });
GRush.analytics.logEconomyEvent("sink", "coin", 50, 120, "Shop", { itemSku: "sword" });
```

| 送るもの | Unity | Godot | JavaScript |
|---|---|---|---|
| オンボーディングのステップ | `Analytics.LogOnboardingStep(step, stepName, fields)` | `analytics.log_onboarding_step(step, step_name, fields)` | `analytics.logOnboardingStep(step, stepName, { fields })` |
| ファネルのステップ | `Analytics.LogFunnelStep(funnel, funnelSessionId, step, stepName, fields)` | `analytics.log_funnel_step(funnel, funnel_session_id, step, step_name, fields)` | `analytics.logFunnelStep(funnel, funnelSessionId, step, stepName, { fields })` |
| カスタムイベント | `Analytics.LogCustomEvent(name, value, fields)` | `analytics.log_custom_event(event_name, value, fields)` | `analytics.logCustomEvent(name, value, { fields })` |
| 通貨の入手と消費 | `Analytics.LogEconomyEvent(flowType, currency, amount, endingBalance, transactionType, itemSku, fields)` | `analytics.log_economy_event(flow_type, currency, amount, ending_balance, transaction_type, item_sku, fields)` | `analytics.logEconomyEvent(flowType, currency, amount, endingBalance, transactionType, { itemSku, fields })` |
| GameRush の中で送れるか | `Analytics.IsAvailable` | `analytics.is_available()` | `analytics.isAvailable()` |

**名前・値・`fields` に、個人を識別できる情報を入れないでください。プレイヤーの名前・メールアドレス・アカウントの ID のような値は、集計のための名前や値として送るものではありません。**

| 項目 | 制限 |
|---|---|
| `step` | 1〜100 の整数 |
| `value`（カスタムイベント） | 省略で 1。絶対値 1e9 まで |
| `amount`（エコノミー） | 正の値で 1e12 まで |
| `endingBalance`（エコノミー） | その後の残高。省略できません。絶対値 1e15 まで |
| `flowType`（エコノミー） | `source`（入手）か `sink`（消費） |
| `transactionType`（エコノミー） | 標準の値は `TimedReward`・`Onboarding`・`Shop`・`Gameplay`・`ContextualPurchase`。ほかの値も受けます |
| イベント名・ファネル名・`funnelSessionId` | 英数字と `.` `_` `:` `-` で 1〜64 文字 |
| `funnelSessionId`（ファネル） | 省略できます。Unity は `null`、Godot は空文字、JavaScript は `undefined` を渡します |
| 通貨・`transactionType` | 英数字と `.` `_` `:` `-` で 1〜32 文字 |
| `stepName`・`itemSku`・`fields` の値 | 1行のテキストで 40 文字まで |
| `fields` | 3つまで。キーは英数字と `_` で 1〜32 文字 |

- 形が合わないときは `false` を返し、理由ごとに1回だけコンソールに警告が出ます。`stepName`・`itemSku`・`fields` の値は、改行・制御文字・双方向の上書きと isolate を空白に直し、前後の空白を落としてから数えます。直した結果が空の `stepName` と `itemSku` は省略と同じに扱い、空の `fields` の値は拒みます。
- オンボーディングとファネルの同じステップは、1セッションで最初の1回だけが残ります。セッションはページを読み直しても続きます。同じファネルを何度も通るなら、通るたびに別の `funnelSessionId` を渡してください。
- ゲームが前面に出るまでの分は、GameRush が溜めてから送ります。溜められるのは 30 件までで、超えた分は `false` です。
- `true` が返っても、GameRush が掛ける上限を超えた分は保存されません。前面に出た後は 500ms に1件、まとめて最大 30 件までを受け、送る前の列は合計 200 件までです。保存はセッションあたり、オンボーディングを含むファネルのステップ 200 件・カスタムイベント 500 件・エコノミー 500 件までです。送れなかった分は送り直しません。

古い GameRush（`protocolVersion` 6 未満）と GameRush の外では、どの呼び出しも `false` です。ゲームに読み込まれる GameRush のスクリプトは新しくても、アナリティクスに対応する前の古い GameRush のアプリ（ストアの更新を待つ iOS・Android のアプリなど）の上では、`true` が返っても送られません。そのぶん集計の人数は、遊んだ人数より少なくなることがあります。

エディタとモックでは、GameRush と同じ検査をして、通ったイベントを1件ずつコンソールに出し、直近の 200 件を持ちます（Unity は `GRushMock.AnalyticsEvents`、Godot は `GRushMock.analytics_events`、JavaScript は `GRush.mock.analyticsEvents()`）。どこへも送りません。前面に出るまでの溜め・GameRush の上限・同じステップを最初の1回だけ残す扱い・セッションあたりの上限は再現しないので、モックでは `true` の分がすべて記録に残ります。
