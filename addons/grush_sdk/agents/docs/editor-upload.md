# Unity Editor からアップロードする

> GameRush の開発者向け文書（https://gamerush.jp/developers）から生成した写しです。SDK を上げたら入れ直してください。
> 元のページ: https://gamerush.jp/sdk#editor-upload

<a id="editor-upload"></a>
## Unity Editor からアップロードする

**Unity から出ずに、ログインからビルドのアップロード、ランキングの宣言まで通せます。**

[API トークン](api-tokens.md#api-tokens) のトークンを手で貼る必要はありません。Editor がブラウザ承認で自分で取ります。

| GameRush メニュー | 内容 |
|---|---|
| GameRush ウィンドウ | アップロードとランキング宣言の画面 |
| ログイン | 既定のブラウザで承認画面を開き、戻ってきたコードをトークンへ交換する |
| ログアウト | 保存したトークンを消す |

トークンはプロジェクトの外（`%APPDATA%\GameRush\` / `~/Library/Application Support/GameRush/` / `$XDG_CONFIG_HOME/gamerush/`）に置きます。`Assets/` にも `EditorPrefs` にも書かないので、リポジトリにもプロジェクト設定にも漏れません。Editor 側のコードは Editor 専用のアセンブリに入っており、書き出したビルドにはコードもトークンも含まれません。

### アップロードの手順

- Unity で WebGL に書き出す。[推奨設定でビルドする](build-settings.md#build) を使うと、書き出した先がそのまま次の手順に入る
- GameRush ウィンドウでゲームを選ぶ。新規作成もできる（`games:create` を要求したトークンが要る。作成の前に、ゲームと第三者アセットの権利を確認するチェックを入れる。`unlisted` で作るときは、全年齢向けの内容であることを申告するチェックも入れる）
- 書き出しディレクトリを選ぶと、上げる前に手元で検査する — Unity の loader / framework / wasm / data がそろっていることを確かめ、拡張子・パス・ファイル数・総量をサーバと同じ規則で見るので、2000 ファイル上げ切ってから弾かれることがない
- アップロードする（進捗が出る。途中で止められる。失敗したファイルだけ再送する）

新規作成ではタイトル・説明・遊び方を入れ、可視性を選べます（`private` か `unlisted`）。エディタ拡張は、説明と遊び方がそれぞれ100文字に届くまで作成のボタンを押せません。遊び方は操作方法・目的・コツなどを複数行で書けます。既存ゲームの説明・遊び方・公開設定は [Studio](https://gamerush.jp/studio) か API の `PATCH /api/games/:id` で変えてください。

**`unlisted` は審査を経ずに選べます。アップロードが終わった時点で、URL を知っている人がすぐ遊べます。フィードと検索に載る `public` は審査を通るので、Studio か API で申請してください。**

### 覚えておくこと

- Unity `v1.14.0` 以降の SDK では GameRush のプレイヤーで起動するので、書き出した `index.html` と `TemplateData` は送らない。カスタムの WebGL テンプレートは使われない。基準解像度には書き出した `index.html` の canvas の大きさが入り、読めないときは Player Settings の Default Canvas Width / Height が入る
- 書き出しディレクトリの直下に `grush.json` を置くと、そのビルドが最新になったときにランキングの定義も反映される（書式は [ランキング](leaderboards.md#leaderboards)）。公開中のゲームでは、ビルドが審査で承認されて配信される時点で反映される。このときトークンに `leaderboards:write` が要る
- 公開中のゲームに上げたビルドは審査に積まれ、審査の間は前に承認されたビルドの配信が続く。承認されると新しいビルドに差し替わる
- Brotli / gzip で書き出したファイルはそのまま上げる。`Build/x.wasm.br` は `.br` が付いた名前のまま登録され、配信側がその名前で `Content-Encoding` を決める
- 作成の失敗を機械的に再試行しない。Editor 拡張はゲームとビルドの作成に冪等キー（`operationId`）を付けないので、再試行が2つ目を作る（個別ファイルの送り直しは安全）
- GameRush が求める最低の版より古い Editor 拡張は、操作を止める。止まったらパッケージを更新する
