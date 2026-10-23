extends RefCounted

## 公開プレイヤー状態（他プレイヤーへ見せる進捗）。
##
## **これは他プレイヤーへ見えるユーザー生成コンテンツである。** 通報とモデレーション
## の対象になるため、payload は人間が読める構造化 JSON（辞書）に限られる。4KB を
## 超えるもの、base64 のような読めない文字列を含むものはサーバが弾く。
##
## クラウドセーブ（本人だけが読む非公開データ）とは別の入れ物であり、
## この経路からクラウドセーブは一切読めない。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

## 公開プレイヤー状態が使えるランタイムの版数。
const PLAYER_STATE_PROTOCOL_VERSION := 2

## 相手探し（[method sample] と [method set_mine] の rating）が使えるランタイムの版数。
const MATCHMAKING_PROTOCOL_VERSION := 7

## 確認用の表示（[signal preview_received]）が使えるランタイムの版数。
const PREVIEW_PROTOCOL_VERSION := 10

## GameRush の確認用の表示で、この公開プレイヤー状態がほかのプレイヤーにどう見えるかを描くよう
## 頼まれたときに発火する。[param state] は [method get_mine] の値と同じ形の Dictionary
## （`pseudo_id`・`payload`・`revision`・`rating`・`updated_at`）。受け取ったら、ほかのプレイヤーの
## 状態を見せるのと同じ画面で描く。`pseudo_id` は決まった値で、`rating` は null。
## 同じ状態は1回だけ届く。接続より先に届いた状態は、接続した後に届く。
## JavaScript の呼び出しの中ではなく `call_deferred` で後から配る。
## 版数が [constant PREVIEW_PROTOCOL_VERSION] 未満のランタイムと GameRush の外では発火しない。
## [method GRush.use_backend] でバックエンドを差し替えても接続はそのまま、新しいバックエンドから届く。
signal preview_received(state: Dictionary)

var _grush: Node
var _backend: RefCounted
var _preview_transport: RefCounted
var _preview_watching := false
var _disposed := false
# use_backend のたびに増やす。差し替える前の受け取り口から call_deferred で積まれた状態を捨てるため。
var _preview_generation := 0


func _init(grush: Node, backend: RefCounted, preview_transport: RefCounted = null) -> void:
	_grush = grush
	use_backend(backend, preview_transport)


## 呼び出し先と、確認用の表示の受け取り口を差し替える。[signal preview_received] への接続はそのまま、
## 新しい受け取り口から届く。GRush.use_backend が呼ぶ。
func use_backend(backend: RefCounted, preview_transport: RefCounted = null) -> void:
	_backend = backend
	_stop_preview_poll()
	if _preview_transport != null:
		_preview_transport.dispose()
	_preview_transport = preview_transport
	_preview_watching = false
	_preview_generation += 1
	_sync_preview_watch()


func dispose() -> void:
	_disposed = true
	_stop_preview_poll()
	if _preview_transport != null:
		_preview_transport.dispose()
	_preview_transport = null
	_grush = null


## 自分の状態を読む。運営が hidden にしていても本人には返る。
func get_mine() -> Dictionary:
	var response := await _call("playerState.getMine", {})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var state: Variant = raw.get("state") if raw is Dictionary else null
	return Result.ok(null if state == null else _state_of(state))


## 自分の状態を書く。`base_revision` を渡すと楽観ロックになり、他所で
## 更新されていた場合は invalidParams（409 相当）で戻る。
## [param options] の `rating` は相手探しに使う数値（-1e9 より大きく 1e9 より小さい）で、
## null を渡すと消し、渡さなければ今の値のまま。版数が [constant MATCHMAKING_PROTOCOL_VERSION]
## 未満のランタイムでは rating を送らず、payload だけを書く。それ以上でも古い GameRush 本体では
## rating が黙って捨てられるので、書けたかは返る状態の `rating` で確かめる。
## NaN と無限大は送らずに invalidParams で返す。
func set_mine(payload: Dictionary, base_revision: Variant = null, options: Dictionary = {}) -> Dictionary:
	var params := {"payload": payload}
	if base_revision != null:
		params["baseRevision"] = int(base_revision)
	if options.has("rating") and _grush.protocol_version() >= MATCHMAKING_PROTOCOL_VERSION:
		if options["rating"] != null and not _is_finite_number(options["rating"]):
			return Result.failure(Result.CODE_INVALID_PARAMS, "rating must be a finite number or null.")
		params["rating"] = options["rating"]
	var response := await _call("playerState.setMine", params)
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var state: Variant = raw.get("state") if raw is Dictionary else null
	if not (state is Dictionary):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable player state.")
	return Result.ok(_state_of(state))


## 他プレイヤーの状態を疑似IDで引く（1回 50 件まで）。
## **運営が hidden にしたものは返らない。**
func get_many(pseudo_ids: Array) -> Dictionary:
	var response := await _call("playerState.get", {"pseudoIds": pseudo_ids})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var states: Array = []
	if raw is Dictionary and raw.get("states") is Array:
		for entry in raw["states"]:
			states.append(_state_of(entry))
	return Result.ok(states)


## 相手探し。同じゲームの他プレイヤーの公開状態をランダムに返す。自分と運営が伏せた状態は
## 返らず、名前も返らない。[param options] は `count`（1〜20、既定 10）と、一緒に渡す
## `min_rating` / `max_rating`（範囲を渡すと rating の無い状態は返らない）。
## 版数が [constant MATCHMAKING_PROTOCOL_VERSION] 未満のランタイムでは unsupported。
func sample(options: Dictionary = {}) -> Dictionary:
	if _grush.protocol_version() < MATCHMAKING_PROTOCOL_VERSION:
		return Result.unsupported()
	var params := {}
	if options.has("count"):
		params["count"] = int(options["count"])
	for key in ["min_rating", "max_rating"]:
		if options.has(key) and options[key] != null and not _is_finite_number(options[key]):
			return Result.failure(
				Result.CODE_INVALID_PARAMS, "min_rating and max_rating must be finite numbers."
			)
	if options.has("min_rating"):
		params["minRating"] = options["min_rating"]
	if options.has("max_rating"):
		params["maxRating"] = options["max_rating"]
	var response := await _call("playerState.sample", params)
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var list: Variant = raw.get("states") if raw is Dictionary else raw
	if not (list is Array):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned unreadable player states.")
	var states: Array = []
	for entry in list:
		states.append(_state_of(entry))
	return Result.ok(states)


## 他プレイヤーの状態を通報する。**ゲームは通報 UI を描けない。**
## 確認ダイアログは親（信頼済み UI）が出し、承諾されたときだけ送られる。
func report(pseudo_id: String) -> Dictionary:
	var response := await _call("playerState.report", {"pseudoId": pseudo_id})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var reported: bool = bool(raw.get("reported", false)) if raw is Dictionary else false
	return Result.ok(reported)


# ランタイムへの登録を、preview_received に接続があるときだけにそろえる。Godot の signal は接続と切断を
# 知らせないので、フレームごとに has_connections で確かめる。
# - 接続が無いうちに登録すると、ランタイムは1回だけ渡す状態を SDK に渡し、受け手がいないまま捨てることになる。
#   ランタイムは登録より先に来た状態も登録したときに渡すので、接続ができてから登録すれば取りこぼさない。
# - 接続が無くなったら登録を外す。外さないと、その後に来た状態を受け手がいないまま受け取ったことにしてしまう。
#   外した後に来た状態は、接続し直して登録したときに届く。
# - 確かめるのは、確認用の表示が使える間はずっと続ける。止めると、遅れて接続したゲームが受け取れない。
#   1回の確かめは接続の有無を読むだけで軽い。
func _sync_preview_watch() -> void:
	if not _preview_supported():
		_stop_preview_poll()
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_sync_preview_watch):
		tree.process_frame.connect(_sync_preview_watch)
	var connected := has_connections("preview_received")
	if connected == _preview_watching:
		return
	_preview_watching = connected
	if connected:
		var generation := _preview_generation
		_preview_transport.watch(func(raw: Variant) -> void: _on_preview(generation, raw))
	else:
		_preview_transport.unwatch()


func _stop_preview_poll() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_sync_preview_watch):
		tree.process_frame.disconnect(_sync_preview_watch)


# JavaScript の呼び出しの中でゲームのコードを動かさない。
func _on_preview(generation: int, raw: Variant) -> void:
	if raw is Dictionary:
		_emit_preview.call_deferred(generation, _state_of(raw))


func _emit_preview(generation: int, state: Dictionary) -> void:
	if not _disposed and generation == _preview_generation:
		preview_received.emit(state)


func _preview_supported() -> bool:
	return (
		not _disposed
		and _preview_transport != null
		and _grush.is_available()
		and _grush.protocol_version() >= PREVIEW_PROTOCOL_VERSION
	)


func _call(method: String, params: Dictionary) -> Dictionary:
	# 基本機能ごと止めない。公開プレイヤー状態が使えない古いランタイムでは
	# この機能だけ unsupported にする。
	if not _grush.is_available() or _grush.protocol_version() < PLAYER_STATE_PROTOCOL_VERSION:
		return Result.unsupported()
	var pending := Call.new()
	_backend.call_api(method, params, func(result: Dictionary) -> void: pending.resolve(result))
	return await pending.completed


## `rating` は書かれていなければ null。
static func _state_of(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var rating: Variant = source.get("rating")
	return {
		"pseudo_id": str(source.get("pseudoId", "")),
		"payload": source.get("payload", {}),
		"revision": int(source.get("revision", 0)),
		"rating": float(rating) if rating is int or rating is float else null,
		"updated_at": str(source.get("updatedAt", "")),
	}


# NaN と無限大は JSON の数値に書けない。Web の層は JSON を通して渡すので、そのまま送ると壊れた値が届き、
# rating と分からない文言で返る。
static func _is_finite_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return not is_nan(value) and not is_inf(value)
	return false
