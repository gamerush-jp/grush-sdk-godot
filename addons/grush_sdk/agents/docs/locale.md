# 表示言語

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#locale

<a id="locale"></a>
## 表示言語

プレイヤーが GameRush をどの言語で使っているかを読めます。ゲームの文言をそれに合わせて切り替えるのに使います。

```csharp
// Unity
GRush.Locale.Changed += (next) => ApplyLanguage(PickLanguage(next));
var locale = await GRush.Locale.GetAsync();
if (locale.Ok) ApplyLanguage(PickLanguage(locale.Value));
```

```gdscript
# Godot
GRush.locale.changed.connect(func(next): apply_language(pick_language(next)))
var locale: Dictionary = await GRush.locale.fetch()
if locale["ok"]:
    apply_language(pick_language(locale["value"]))
```

```javascript
// JavaScript
GRush.locale.onChange((next) => applyLanguage(pickLanguage(next)));
const locale = await GRush.locale.get();
if (locale.ok) applyLanguage(pickLanguage(locale.value));
```

| 値 | 意味 |
|---|---|
| `locale` | `source` が `user` か `system` なら GameRush の画面が表示している言語（いまは `ja`・`en`・`ko`・`zh-Hans`・`zh-Hant`・`id`・`fil`・`vi`・`th` のどれか）、`device` なら端末の言語の先頭（`fr-FR` など）。GameRush の言語は今後増えるので、知らない値が来ても動くように書いてください |
| `source` | `user` はプレイヤーが GameRush で言語を選んだ、`system` は端末の言語に従っている、`device` は GameRush から答えが無く端末の言語だけで決めた。`source` は必ず入っています。`source` も今後増えるので、知らない値は `device` と同じに扱ってください |
| `languages` | 言語の優先順。`source` が `user` なら先頭が `locale` で、続けて端末の言語が並びます。`system` と `device` では端末の言語の一覧そのままなので、`locale` が入っているとは限りません。空にはなりません（GameRush が空の一覧を渡したときは `[locale]`） |

**ゲームが持っている言語の中から、`languages` の先頭から順に最初に一致したものを選ぶのがおすすめです（`en-US` が無ければ `en` のように、地域を落とした言語でも比べます）。中国語は `zh-Hans-HK`（簡体字・香港）のように用字の付いたタグで来ることがあり、その直後には用字を落とした `zh-HK` も並びます。簡体字と繁体字を分けて用意しているなら、用字（`Hans`・`Hant`）で比べてください。どれにも一致しなければ `locale` で比べ、それでも無ければゲームの既定の言語にします。GameRush に無い言語（フランス語など）を用意しているなら、端末の言語に従っているプレイヤーにはその言語で出せます。通知を受け取り損ねないよう、取得より先に変更の通知を購読してください。**

| 呼び出し | Unity | Godot | JavaScript |
|---|---|---|---|
| いまの言語を取る | `Locale.GetAsync()` | `locale.fetch()` | `locale.get()` |
| 取れていれば同期で返す（まだなら null） | `Locale.Current` | `locale.current()` | `locale.current()` |
| 言語が変わったら知らせる | `Locale.Changed` | `locale.changed` | `locale.onChange(handler)` |

変更の通知は、言語が初めて決まったときと、プレイヤーがプレイ中に GameRush の言語を変えたときに届きます。同じ値のままなら届きません。GameRush の外と、ゲームに読み込まれる GameRush のスクリプトが表示言語に対応する前の古いものだったときは `Unsupported` が返るので、エンジン自身の言語判定に戻してください。スクリプトは新しくても GameRush のアプリ側が古くて答えられないときは、`Unsupported` ではなく `source` が `device` の値が返ります。Godot だけ `get` ではなく `fetch` なのは、`Object.get` と名前がぶつかるためです。バックエンドを差し替えても（Unity `GRush.UseBackend`、Godot `GRush.use_backend`、JavaScript `GRush.configure`）、変更の通知の購読は続きます。
