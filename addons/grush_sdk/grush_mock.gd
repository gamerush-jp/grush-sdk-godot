class_name GRushMock
extends RefCounted

## モックの相手の疑似 ID。それぞれ rating 付きの公開プレイヤー状態を持ち、届いたメッセージを
## 同じ kind と payload で送り返す。はじめと [method GRushMockInbox.reset] /
## [method GRushMockTrades.reset] の後は、最初の相手からのメッセージ1通と、受付中の出品を2件持つ。
const RIVALS := ["mock-rival-1", "mock-rival-2", "mock-rival-3"]

const STATE_PATH := "user://grush_sdk_mock.cfg"
const STATE_SECTION := "mock"

static var signed_in := true
static var display_name := "Editor Player"
static var avatar_url: Variant = null
static var grant_profile_consent := true
## 通報の確認ダイアログでプレイヤーが押す答え。エディタ用。
static var confirm_player_state_report := true
## 受信箱の通報の確認でプレイヤーが押す答え。
static var confirm_inbox_report := true
## 交換所の通報の確認でプレイヤーが押す答え。
static var confirm_trade_report := true
static var unreliable_drop_rate := 0.0
## モックの部屋の定員の上書き。部屋の定員（[code]GRush.net.join_with[/code] の max_peers、既定 8）と
## 小さいほうが効く。満員を試すときに下げる。
static var max_peers := 100
static var share_available := true
static var share_status := "opened"
static var locale := ""
## `GRush.launch` が返す起動パラメータ（`gp.` を除いたキーと値。どちらも String）。
## GameRush の制限（キー・値の形と 8 個まで）では確かめずにそのまま返す。
static var launch_params: Dictionary = {}
## `GRush.launch` の `invite` に入れる招待の部屋。`{"mode": String, "room_code": String}` を入れると、
## 招待から開いたときを試せる。形が join の規則に合わなければ null として返す。既定 null。
static var launch_invite: Variant = null
## `GRush.net.invite()` の答え。"cancelled" にすると、送らずにシートを閉じたことにする。
## 部屋に居なければ unavailable、[member signed_in] が false なら signInRequired で、この設定によらない。
static var invite_status := "sent"
## `GRush.net.invite()` で偽のフレンドへ送ったことにする人数。部屋の空いた席の数と 30 の小さいほうまでに絞り、
## 0 になれば "cancelled" を返す。
static var invite_count := 1
## モックが受けた分析イベント。GameRush へ渡すのと同じ形の Dictionary で、直近の 200 件を古い順に持つ。
## 空にするときは clear() する。
static var analytics_events: Array[Dictionary] = []


## モックの自分の疑似 ID。初めて読んだときに作り、user:// に残す。
static func local_pseudo_id() -> String:
	var config := ConfigFile.new()
	config.load(STATE_PATH)
	var stored := str(config.get_value(STATE_SECTION, "pseudo_id", ""))
	if stored != "":
		return stored
	var created := "mock-local-" + str(randi()) + str(randi())
	config.set_value(STATE_SECTION, "pseudo_id", created)
	config.save(STATE_PATH)
	return created
